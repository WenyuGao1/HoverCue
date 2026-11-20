@preconcurrency import AVFoundation
import Foundation
import Speech

final class MicrophoneAudioCapture: @unchecked Sendable {
    private static let recoveryDelay = DispatchTimeInterval.milliseconds(300)
    private static let stableCaptureDelay = DispatchTimeInterval.seconds(2)

    private let controlQueue = DispatchQueue(
        label: "com.wenyugao.hovercue.microphone-control",
        qos: .userInitiated
    )
    private let outputQueue = DispatchQueue(
        label: "com.wenyugao.hovercue.microphone-audio",
        qos: .userInitiated
    )
    private let inFlightSlots = DispatchSemaphore(value: 3)

    // Accessed only on controlQueue.
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var configurationObserver: NSObjectProtocol?
    private var recoveryWorkItem: DispatchWorkItem?
    private var stableCaptureWorkItem: DispatchWorkItem?
    private var recoveryBudget = MicrophoneRecoveryBudget()
    private var activeGeneration: UInt64 = 0
    private var activeSource: AudioSource?
    private var activeTargetFormat: AVAudioFormat?
    private var activeAudioHandler: (@Sendable (AnalyzerInput) -> Void)?
    private var activeStopHandler: (@Sendable (String) -> Void)?

    // Accessed only on outputQueue.
    private var outputGeneration: UInt64 = 0
    private var converter: AudioBufferConverter?
    private var outputAudioHandler: (@Sendable (AnalyzerInput) -> Void)?

    func start(
        source: AudioSource,
        targetFormat: AVAudioFormat,
        onAudio: @escaping @Sendable (AnalyzerInput) -> Void,
        onStopped: @escaping @Sendable (String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            controlQueue.async { [self] in
                stopLocked()
                activeGeneration &+= 1
                let generation = activeGeneration
                do {
                    try startLocked(
                        source: source,
                        targetFormat: targetFormat,
                        onAudio: onAudio,
                        onStopped: onStopped,
                        generation: generation
                    )
                    continuation.resume()
                } catch {
                    stopLocked()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            controlQueue.async { [self] in
                stopLocked()
                continuation.resume()
            }
        }
    }

    private func startLocked(
        source: AudioSource,
        targetFormat: AVAudioFormat,
        onAudio: @escaping @Sendable (AnalyzerInput) -> Void,
        onStopped: @escaping @Sendable (String) -> Void,
        generation: UInt64
    ) throws {
        guard source.isMicrophone else {
            throw MicrophoneCaptureError.selectedDeviceUnavailable
        }

        let deviceID = try MicrophoneDeviceCatalog.deviceID(for: source)
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if !source.isSystemDefaultMicrophone {
            try input.auAudioUnit.setDeviceID(deviceID)
        }
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw MicrophoneCaptureError.noInputDevice
        }

        outputQueue.sync {
            outputGeneration = generation
            converter = AudioBufferConverter(targetFormat: targetFormat)
            outputAudioHandler = onAudio
        }

        input.installTap(
            onBus: 0,
            bufferSize: 4_096,
            format: hardwareFormat
        ) { [weak self] buffer, _ in
            self?.enqueue(buffer, generation: generation)
        }
        tapInstalled = true

        self.engine = engine
        activeSource = source
        activeTargetFormat = targetFormat
        activeAudioHandler = onAudio
        activeStopHandler = onStopped
        installConfigurationObserver(for: engine, generation: generation)

        engine.prepare()
        try engine.start()
        scheduleStableCaptureCheck(for: engine, generation: generation)
    }

    private func installConfigurationObserver(
        for engine: AVAudioEngine,
        generation: UInt64
    ) {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            // AVAudioEngine stops itself before posting this notification. Defer
            // teardown so the engine is never deallocated inside Apple's callback.
            self?.scheduleRecovery(generation: generation)
        }
    }

    private func stopLocked() {
        recoveryWorkItem?.cancel()
        recoveryWorkItem = nil
        stableCaptureWorkItem?.cancel()
        stableCaptureWorkItem = nil
        recoveryBudget.markStable()
        activeGeneration &+= 1
        teardownEngineLocked()
        activeSource = nil
        activeTargetFormat = nil
        activeAudioHandler = nil
        activeStopHandler = nil
        clearOutputLocked(generation: activeGeneration)
    }

    private func teardownEngineLocked() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        if let engine {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
            engine.reset()
            self.engine = nil
        }
    }

    private func scheduleRecovery(generation: UInt64) {
        controlQueue.async { [weak self] in
            guard let self, self.activeGeneration == generation else { return }
            self.recoveryWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.recoverLocked(expectedGeneration: generation)
            }
            self.recoveryWorkItem = workItem
            self.controlQueue.asyncAfter(
                deadline: .now() + Self.recoveryDelay,
                execute: workItem
            )
        }
    }

    private func recoverLocked(expectedGeneration: UInt64) {
        guard activeGeneration == expectedGeneration,
              let engine,
              activeSource != nil,
              let targetFormat = activeTargetFormat,
              let onAudio = activeAudioHandler,
              let onStopped = activeStopHandler else { return }

        recoveryWorkItem = nil
        if engine.isRunning {
            scheduleStableCaptureCheck(for: engine, generation: expectedGeneration)
            return
        }
        guard recoveryBudget.beginAttempt() else {
            stopLocked()
            onStopped(MicrophoneCaptureError.unstableConfiguration.localizedDescription)
            return
        }

        stableCaptureWorkItem?.cancel()
        stableCaptureWorkItem = nil
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        activeGeneration &+= 1
        let generation = activeGeneration
        clearOutputLocked(generation: generation)

        do {
            // Keep the existing I/O unit and its selected device. Rebinding a fresh
            // engine here can itself produce another configuration-change event.
            let input = engine.inputNode
            let hardwareFormat = input.outputFormat(forBus: 0)
            guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
                throw MicrophoneCaptureError.noInputDevice
            }

            outputQueue.sync {
                outputGeneration = generation
                converter = AudioBufferConverter(targetFormat: targetFormat)
                outputAudioHandler = onAudio
            }
            input.installTap(
                onBus: 0,
                bufferSize: 4_096,
                format: hardwareFormat
            ) { [weak self] buffer, _ in
                self?.enqueue(buffer, generation: generation)
            }
            tapInstalled = true
            installConfigurationObserver(for: engine, generation: generation)
            engine.prepare()
            try engine.start()
            scheduleStableCaptureCheck(for: engine, generation: generation)
        } catch {
            stopLocked()
            onStopped(error.localizedDescription)
        }
    }

    private func scheduleStableCaptureCheck(
        for engine: AVAudioEngine,
        generation: UInt64
    ) {
        stableCaptureWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak engine] in
            guard let self,
                  let engine,
                  self.engine === engine,
                  self.activeGeneration == generation,
                  engine.isRunning else { return }
            self.recoveryBudget.markStable()
            self.stableCaptureWorkItem = nil
        }
        stableCaptureWorkItem = workItem
        controlQueue.asyncAfter(
            deadline: .now() + Self.stableCaptureDelay,
            execute: workItem
        )
    }

    private func clearOutputLocked(generation: UInt64) {
        outputQueue.sync {
            outputGeneration = generation
            converter = nil
            outputAudioHandler = nil
        }
    }

    private func enqueue(_ buffer: AVAudioPCMBuffer, generation: UInt64) {
        guard inFlightSlots.wait(timeout: .now()) == .success else { return }
        guard let ownedBuffer = AudioBufferConverter.copyPCMBuffer(buffer) else {
            inFlightSlots.signal()
            return
        }
        outputQueue.async { [weak self] in
            guard let self else { return }
            defer { self.inFlightSlots.signal() }
            guard self.outputGeneration == generation,
                  let input = self.converter?.convert(ownedBuffer) else { return }
            self.outputAudioHandler?(input)
        }
    }
}

enum MicrophoneCaptureError: LocalizedError, Sendable {
    case noInputDevice
    case selectedDeviceUnavailable
    case unstableConfiguration

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            "No microphone input is available."
        case .selectedDeviceUnavailable:
            "The selected microphone is no longer available."
        case .unstableConfiguration:
            "The selected microphone could not settle into a stable audio configuration."
        }
    }
}

struct MicrophoneRecoveryBudget: Sendable {
    static let maximumConsecutiveAttempts = 3

    private(set) var consecutiveAttempts = 0

    mutating func beginAttempt() -> Bool {
        guard consecutiveAttempts < Self.maximumConsecutiveAttempts else { return false }
        consecutiveAttempts += 1
        return true
    }

    mutating func markStable() {
        consecutiveAttempts = 0
    }
}

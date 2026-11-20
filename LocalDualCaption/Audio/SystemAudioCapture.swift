@preconcurrency import AVFoundation
import AppKit
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit
import Speech

final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let outputQueue = DispatchQueue(label: "com.wenyugao.hovercue.system-audio", qos: .userInitiated)
    private var stream: SCStream?
    private var converter: AudioBufferConverter?
    private var audioHandler: (@Sendable (AnalyzerInput) -> Void)?
    private var stopHandler: (@Sendable (String) -> Void)?

    @MainActor static func availableSources() async throws -> [AudioSource] {
        let content = try await SCShareableContent.current
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let applications = content.applications
            .filter { $0.processID != ownPID && !$0.applicationName.isEmpty }
            .map { application in
                let running = NSRunningApplication(processIdentifier: application.processID)
                return AudioSource(
                    id: "\(application.bundleIdentifier)-\(application.processID)",
                    title: application.applicationName,
                    bundleIdentifier: application.bundleIdentifier,
                    processID: application.processID,
                    isAuxiliary: ApplicationAudioSourceCatalog.isAuxiliary(
                        isRegularApplication: running?.activationPolicy == .regular,
                        bundleURL: running?.bundleURL,
                        runningBundleID: running?.bundleIdentifier,
                        captureBundleID: application.bundleIdentifier
                    )
                )
            }
            .sorted { lhs, rhs in
                let preferred = ["Microsoft Teams", "zoom.us", "Google Chrome", "Safari", "QuickTime Player"]
                let leftRank = preferred.firstIndex(where: { lhs.title.localizedCaseInsensitiveContains($0) }) ?? preferred.count
                let rightRank = preferred.firstIndex(where: { rhs.title.localizedCaseInsensitiveContains($0) }) ?? preferred.count
                return leftRank == rightRank ? lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending : leftRank < rightRank
            }
        return [.allSystemAudio] + applications
    }

    func start(
        source: AudioSource,
        targetFormat: AVAudioFormat,
        onAudio: @escaping @Sendable (AnalyzerInput) -> Void,
        onStopped: @escaping @Sendable (String) -> Void
    ) async throws {
        await stop()
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else { throw AudioCaptureError.noDisplay }

        let filter: SCContentFilter
        if source.id == AudioSource.allSystemAudio.id {
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let ownApplications = content.applications.filter { $0.processID == ownPID }
            filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        } else {
            guard let selected = content.applications.first(where: {
                if let processID = source.processID { return $0.processID == processID }
                return $0.bundleIdentifier == source.bundleIdentifier
            }) else { throw AudioCaptureError.sourceUnavailable }
            filter = SCContentFilter(display: display, including: [selected], exceptingWindows: [])
        }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = Int(targetFormat.sampleRate)
        configuration.channelCount = Int(targetFormat.channelCount)
        configuration.queueDepth = 3
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
        outputQueue.sync {
            converter = AudioBufferConverter(targetFormat: targetFormat)
            audioHandler = onAudio
            stopHandler = onStopped
        }
        self.stream = stream
        try await stream.startCapture()
    }

    func stop() async {
        guard let stream else {
            outputQueue.sync {
                converter = nil
                audioHandler = nil
                stopHandler = nil
            }
            return
        }
        self.stream = nil
        try? await stream.stopCapture()
        try? stream.removeStreamOutput(self, type: .audio)
        outputQueue.sync {
            converter = nil
            audioHandler = nil
            stopHandler = nil
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        autoreleasepool {
            guard let input = converter?.convert(sampleBuffer) else { return }
            audioHandler?(input)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        stopHandler?(error.localizedDescription)
    }
}

enum AudioCaptureError: LocalizedError, Sendable {
    case noDisplay
    case sourceUnavailable

    var errorDescription: String? {
        switch self {
        case .noDisplay: "No active display is available for system-audio capture."
        case .sourceUnavailable: "The selected application is no longer running."
        }
    }
}

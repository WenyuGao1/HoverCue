import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import Speech
import SwiftUI
import Translation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status: CaptionStatus = .stopped
    @Published private(set) var segments: [CaptionSegment] = []
    @Published private(set) var interimSourceText = ""
    @Published private(set) var audioSources: [AudioSource] = [
        .systemDefaultMicrophone,
        .allSystemAudio
    ]
    @Published var selectedSourceID: String {
        didSet {
            settings.selectedAudioSourceID = selectedSourceID
            if audioSources.contains(where: { $0.id == selectedSourceID && $0.isAvailable }),
               Self.sourceAvailabilityNotices.contains(notice ?? "") { notice = nil }
        }
    }
    @Published private(set) var screenPermission: PermissionState = .notDetermined
    @Published private(set) var microphonePermission: PermissionState = .notDetermined
    @Published private(set) var speechPermission: PermissionState = .notDetermined
    @Published private(set) var speechModelState: ModelState = .checking
    @Published private(set) var translationModelState: ModelState = .checking
    @Published private(set) var modelPreparationActive = false
    @Published private(set) var translationPreparationActive = false
    @Published private(set) var notice: String?
    @Published private(set) var contextualTranslationStatusKey: String?
    @Published var translationConfiguration: TranslationSession.Configuration?
    @Published private(set) var overlayVisible = false
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var translationVoiceOptions: [TranslationSpeechVoiceOption] = []

    let history: TranslationHistoryStore
    let settings: OverlaySettings

    private let speechModelManager = SpeechModelManager()
    private let speechService = OnDeviceSpeechService()
    private let translationSpeechService = OnDeviceTranslationSpeechService()
    private let translationService = OnDeviceTranslationService()
    private let systemAudioCapture = SystemAudioCapture()
    private let microphoneAudioCapture = MicrophoneAudioCapture()
    private var pipeline = CaptionPipelineState()
    private var translationQueue = OrderedTranslationQueue(
        capacity: BoundedTranslationSpeechQueue.completeModeCapacity
    )
    private var translationWorker: Task<Void, Never>?
    private var overlayController: CaptionPanelController?
    private var hotKeyManager: GlobalHotKeyManager?
    private var modelPreparationTask: Task<Void, Never>?
    private var modelPreparationGeneration: UInt64 = 0
    private var activeModelPreparationGeneration: UInt64?
    private var resumeAfterWake = false
    private var activeSourceSelection: CaptionLanguageSelection?
    private var activeTranslationTermRules: [TranslationTermRule] = []
    private var translationContext = TranslationContextWindow()
    private var terminationRequested = false

    var historyHasPendingCleanup: Bool { history.hasPendingWrites }
    var captionSessionGeneration: Int { pipeline.generation }

    var controlsLocked: Bool {
        running || starting || modelPreparationActive
    }

    init(settings: OverlaySettings? = nil, history: TranslationHistoryStore? = nil) {
        self.history = history ?? TranslationHistoryStore()
        let resolvedSettings = settings ?? OverlaySettings()
        self.settings = resolvedSettings
        selectedSourceID = resolvedSettings.selectedAudioSourceID
        refreshTranslationVoices()
    }

    func attachUIHelpers() {
        history.interfaceLanguage = settings.appLanguage.rawValue
        Task { await history.reload() }
        if overlayController == nil {
            overlayController = CaptionPanelController(model: self, settings: settings)
        }
        if hotKeyManager == nil {
            hotKeyManager = GlobalHotKeyManager { [weak self] identifier in
                guard let self else { return }
                switch identifier {
                case 1: Task { self.running ? await self.stopCaptions() : await self.startCaptions() }
                case 2: self.toggleOverlay()
                default: break
                }
            }
        }
    }

    func refreshEnvironment() async {
        await history.refreshDigestAvailability()
        refreshPermissions()
        await refreshSelectedModelStates()
        await refreshAudioSources()
    }

    func refreshPermissions() {
        screenPermission = CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        microphonePermission = Self.mapMicrophonePermission(
            AVAudioApplication.shared.recordPermission
        )
        speechPermission = Self.mapSpeechPermission(SFSpeechRecognizer.authorizationStatus())
    }

    func refreshTranslationModelState() async {
        translationModelState = .checking
        translationModelState = await TranslationModelManager.state(
            source: settings.sourceSelection,
            target: settings.targetSelection,
            preference: settings.translationModelPreference
        )
    }

    func refreshSelectedModelStates() async {
        refreshTranslationVoices()
        let source = settings.sourceSelection
        let target = settings.targetSelection
        let localeIdentifier = settings.localeIdentifier
        speechModelState = .checking
        translationModelState = .checking
        async let speechState = speechModelManager.state(for: localeIdentifier)
        async let translationState = TranslationModelManager.state(
            source: source,
            target: target,
            preference: settings.translationModelPreference
        )
        speechModelState = await speechState
        translationModelState = await translationState
    }

    func requestSpeechPermission() async {
        let authorization = await Self.requestSpeechAuthorization()
        guard !Task.isCancelled, !terminationRequested else { return }
        speechPermission = Self.mapSpeechPermission(authorization)
    }

    func requestScreenPermission() async {
        let granted = CGRequestScreenCaptureAccess()
        screenPermission = granted ? .granted : .denied
        if granted {
            await refreshAudioSources()
            notice = "If macOS asks you to restart after a permission change, quit and reopen HoverCue."
        }
    }

    func requestMicrophonePermission() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard !Task.isCancelled, !terminationRequested else { return }
        microphonePermission = granted ? .granted : .denied
    }

    func refreshAudioSources() async {
        var refreshedSources: [AudioSource] = [.systemDefaultMicrophone]
        do {
            refreshedSources += try MicrophoneDeviceCatalog.availableSources()
        } catch {
            notice = error.localizedDescription
        }

        if screenPermission == .granted {
            do {
                refreshedSources += try await SystemAudioCapture.availableSources()
            } catch {
                refreshedSources.append(.allSystemAudio)
                notice = error.localizedDescription
                refreshPermissions()
            }
        } else {
            refreshedSources.append(.allSystemAudio)
        }

        let selection = ApplicationAudioSourceCatalog.preservingSelection(
            selectedSourceID, previous: audioSources, refreshed: refreshedSources
        )
        audioSources = selection.sources
        selectedSourceID = selection.selectedID
        if let selected = audioSources.first(where: { $0.id == selectedSourceID }), !selected.isAvailable {
            notice = selected.isMicrophone
                ? "The selected microphone is no longer available."
                : "The selected audio source is no longer available."
        }
    }

    private static let sourceAvailabilityNotices = [
        "The selected microphone is no longer available.",
        "The selected audio source is no longer available."
    ]

    func prepareOfflineModels() {
        guard !terminationRequested, !running, !controlsLocked else { return }
        modelPreparationGeneration &+= 1
        let generation = modelPreparationGeneration
        activeModelPreparationGeneration = generation
        modelPreparationActive = true
        notice = nil
        translationPreparationActive = false
        modelPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performOfflineModelPreparation(generation: generation)
            guard self.activeModelPreparationGeneration == generation else { return }
            self.modelPreparationTask = nil
            if !self.translationPreparationActive {
                self.finishModelPreparation(generation: generation)
            }
        }
    }

    private func performOfflineModelPreparation(generation: UInt64) async {
        let source = settings.sourceSelection
        let target = settings.targetSelection
        let localeIdentifier = settings.localeIdentifier
        if speechPermission != .granted { await requestSpeechPermission() }
        guard isCurrentModelPreparation(generation), !Task.isCancelled else { return }
        guard speechPermission == .granted else {
            notice = "Speech Recognition permission is required before the local model can be prepared."
            return
        }
        do {
            speechModelState = .downloading
            try await speechModelManager.prepare(identifier: localeIdentifier)
            guard isCurrentModelPreparation(generation), !Task.isCancelled else { return }
            speechModelState = await speechModelManager.state(for: localeIdentifier)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentModelPreparation(generation) else { return }
            speechModelState = .error
            notice = error.localizedDescription
            return
        }

        guard isCurrentModelPreparation(generation), !Task.isCancelled else { return }
        translationModelState = await TranslationModelManager.state(
            source: source,
            target: target,
            preference: settings.translationModelPreference
        )
        guard isCurrentModelPreparation(generation), !Task.isCancelled else { return }
        guard translationModelState != .unsupported else {
            notice = "The selected language pair is not supported by the on-device translation model."
            return
        }
        if settings.translationModelPreference == .contextual,
           ContextualModelAvailability.current(source: source, target: target) == .available {
            translationModelState = .installed
            return
        }
        translationModelState = .downloading
        translationPreparationActive = true
        if #available(macOS 26.4, *) {
            var configuration = TranslationSession.Configuration(
                source: source.translationLanguage,
                target: target.translationLanguage,
                preferredStrategy: settings.translationModelPreference.strategy
            )
            configuration.invalidate()
            translationConfiguration = configuration
        } else {
            var configuration = TranslationSession.Configuration(
                source: source.translationLanguage,
                target: target.translationLanguage
            )
            configuration.invalidate()
            translationConfiguration = configuration
        }
    }

    func handleTranslationSession(_ session: TranslationSession) async {
        guard let generation = activeModelPreparationGeneration,
              isCurrentModelPreparation(generation),
              translationPreparationActive else {
            session.cancel()
            return
        }
        let expectedSource = settings.sourceSelection
        let expectedTarget = settings.targetSelection
        guard let sessionSource = session.sourceLanguage,
              let sessionTarget = session.targetLanguage,
              expectedSource.matches(sessionSource),
              expectedTarget.matches(sessionTarget) else {
            session.cancel()
            translationPreparationActive = false
            translationConfiguration = nil
            finishModelPreparation(generation: generation)
            return
        }
        do {
            try await translationService.prepareAndUse(session, expectedTarget: expectedTarget)
            guard isCurrentModelPreparation(generation),
                  !Task.isCancelled,
                  expectedSource == settings.sourceSelection,
                  expectedTarget == settings.targetSelection else {
                translationService.cancel()
                return
            }
            translationModelState = .installed
            translationPreparationActive = false
            translationConfiguration = nil
            notice = nil
        } catch is CancellationError {
            guard isCurrentModelPreparation(generation) else { return }
            translationPreparationActive = false
            translationConfiguration = nil
        } catch {
            guard isCurrentModelPreparation(generation) else { return }
            translationModelState = .error
            translationPreparationActive = false
            translationConfiguration = nil
            notice = error.localizedDescription
        }
        finishModelPreparation(generation: generation)
    }

    func startCaptions() async {
        guard !terminationRequested, !running, !starting else { return }
        starting = true
        defer { starting = false }
        notice = nil
        refreshPermissions()
        guard let source = audioSources.first(where: { $0.id == selectedSourceID }) else {
            status = .error("The selected audio source is no longer available.")
            return
        }
        guard source.isAvailable else {
            status = .error(source.isMicrophone
                ? "The selected microphone is no longer available."
                : "The selected audio source is no longer available.")
            return
        }
        guard speechPermission == .granted else {
            status = .error("Speech Recognition permission is not granted.")
            return
        }
        if source.isMicrophone {
            if microphonePermission == .notDetermined {
                await requestMicrophonePermission()
            }
            guard microphonePermission == .granted else {
                status = .error("Microphone permission is not granted.")
                return
            }
        } else {
            guard screenPermission == .granted else {
                status = .error("Screen & System Audio Recording permission is not granted.")
                return
            }
        }

        let sourceSelection = settings.sourceSelection
        let targetSelection = settings.targetSelection
        let localeIdentifier = settings.localeIdentifier
        guard sourceSelection.language != targetSelection.language else {
            status = .error("Source and target languages must be different.")
            return
        }
        speechModelState = await speechModelManager.state(for: localeIdentifier)
        translationModelState = await TranslationModelManager.state(
            source: sourceSelection,
            target: targetSelection,
            preference: settings.translationModelPreference
        )
        guard speechModelState == .installed else {
            status = .error("Prepare the selected source-language speech model first.")
            return
        }
        guard translationModelState == .installed else {
            status = .error("Prepare the selected translation model first.")
            return
        }

        status = .preparing
        pipeline.start()
        history.setCaptionsActive(true)
        beginHistorySession()
        publishPipeline()
        translationQueue.cancelAll()
        translationContext.reset()
        do {
            try translationService.activateInstalledSession(
                source: sourceSelection,
                target: targetSelection,
                preference: settings.translationModelPreference
            )
            contextualTranslationStatusKey = translationService.contextualStatusKey
            activeSourceSelection = sourceSelection
            activeTranslationTermRules = settings.currentTermDraft.parsed.rules
            let captureGeneration = pipeline.generation
            let speechService = self.speechService
            let format = try await speechService.start(
                localeIdentifier: localeIdentifier,
                vocabulary: Array((activeTranslationTermRules.map(\.source) + settings.vocabulary).prefix(200)),
                onEvent: { [weak self] event in
                    Task { @MainActor [weak self] in self?.receiveSpeechEvent(event, generation: captureGeneration) }
                },
                onError: { [weak self] message in
                    Task { @MainActor [weak self] in
                        guard let self, self.pipeline.generation == captureGeneration else { return }
                        self.runtimeFailed(message)
                    }
                }
            )
            guard !terminationRequested else { throw CancellationError() }
            if source.isMicrophone {
                try await microphoneAudioCapture.start(
                    source: source,
                    targetFormat: format,
                    onAudio: { input in Task { await speechService.append(input) } },
                    onStopped: { [weak self] message in
                        Task { @MainActor [weak self] in
                        guard let self, self.pipeline.generation == captureGeneration else { return }
                        self.runtimeFailed(message)
                    }
                    }
                )
            } else {
                try await systemAudioCapture.start(
                    source: source,
                    targetFormat: format,
                    onAudio: { input in Task { await speechService.append(input) } },
                    onStopped: { [weak self] message in
                        Task { @MainActor [weak self] in
                        guard let self, self.pipeline.generation == captureGeneration else { return }
                        self.runtimeFailed(message)
                    }
                    }
                )
            }
            guard !terminationRequested else { throw CancellationError() }
            running = true
            status = .listening
            showOverlay()
        } catch {
            await systemAudioCapture.stop()
            await microphoneAudioCapture.stop()
            await speechService.stop()
            translationSpeechService.stop()
            translationService.cancel()
            history.finishSession()
            history.setCaptionsActive(false)
            activeSourceSelection = nil
            activeTranslationTermRules = []
            running = false
            status = .error(error.localizedDescription)
        }
    }

    func stopCaptions() async {
        await stopCaptions(finalStatus: .stopped)
    }

    private func stopCaptions(finalStatus: CaptionStatus) async {
        hideOverlay()
        guard running || status != .stopped else { return }
        running = false
        history.finishSession()
        _ = pipeline.stop()
        publishPipeline()
        translationWorker?.cancel()
        translationWorker = nil
        translationQueue.cancelAll()
        translationContext.reset()
        translationService.cancel()
        contextualTranslationStatusKey = nil
        translationSpeechService.stop()
        activeSourceSelection = nil
        activeTranslationTermRules = []
        await systemAudioCapture.stop()
        await microphoneAudioCapture.stop()
        await speechService.stop()
        status = finalStatus
        history.setCaptionsActive(false)
    }

    func toggleOverlay() { overlayController?.toggle(); overlayVisible = overlayController?.isVisible ?? false }
    func showOverlay() { overlayController?.show(); overlayVisible = true }
    func hideOverlay() { overlayController?.hide(); overlayVisible = false }
    func moveOverlayToCurrentScreen() { overlayController?.moveToCurrentScreen() }

    func enableTranslationHistory() {
        guard !terminationRequested else { return }
        history.enable()
        if running { beginHistorySession() }
    }

    private func beginHistorySession() {
        let source = settings.sourceSelection
        let target = settings.targetSelection
        history.beginSession(
            source: source.language == .chinese ? source.chineseScript.translationIdentifier : source.language.languageCode,
            target: target.language == .chinese ? target.chineseScript.translationIdentifier : target.language.languageCode,
            generation: pipeline.generation,
            titleLanguage: settings.appLanguage.rawValue,
            summaryLevel: settings.historySummaryLevel
        )
    }

    func toggleAutomaticTranslationSpeech() {
        if !settings.automaticallySpeakTranslations {
            refreshTranslationVoices()
            guard !translationVoiceOptions.isEmpty else {
                notice = "No installed system voice is available for the target language."
                return
            }
        }
        settings.automaticallySpeakTranslations.toggle()
        if !settings.automaticallySpeakTranslations {
            translationSpeechService.stop()
        }
    }

    func refreshTranslationVoices() {
        let options = TranslationSpeechVoiceCatalog.highestQualityOptions(
            for: settings.targetSelection.speechSynthesisLocaleIdentifier
        )
        translationVoiceOptions = options
        let fallbackOrder = options.sorted {
            if $0.qualityRawValue != $1.qualityRawValue { return $0.qualityRawValue > $1.qualityRawValue }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        settings.resolveTranslationVoice(availableIdentifiers: fallbackOrder.map(\.id))
    }

    var usingFallbackTranslationVoice: Bool {
        guard let preferred = settings.preferredTranslationVoiceIdentifier,
              !translationVoiceOptions.isEmpty else { return false }
        return preferred != settings.translationVoiceIdentifier
    }

    /// Cancels model preparation synchronously so AppKit never waits for a system asset
    /// download to acknowledge cancellation before it can terminate the process.
    func beginTermination() -> Bool {
        terminationRequested = true
        activeModelPreparationGeneration = nil
        modelPreparationGeneration &+= 1
        modelPreparationTask?.cancel()
        modelPreparationTask = nil
        modelPreparationActive = false
        translationPreparationActive = false
        translationConfiguration = nil
        translationService.cancel()
        translationSpeechService.stop()
        history.prepareForTermination()
        return running || starting
    }

    func openScreenPermissionSettings() {
        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    func openSpeechPermissionSettings() {
        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
    }

    func openMicrophonePermissionSettings() {
        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func handleSystemSleep() {
        guard running else { return }
        resumeAfterWake = true
        Task { await stopCaptions() }
    }

    func handleSystemWake() {
        Task {
            await refreshEnvironment()
            if resumeAfterWake {
                resumeAfterWake = false
                await startCaptions()
            }
        }
    }

    private func receiveSpeechEvent(_ event: RecognitionEvent, generation: Int) {
        guard running, generation == pipeline.generation else { return }
        let sourceSelection = activeSourceSelection ?? settings.sourceSelection
        let normalizedText = CaptionTextNormalizer.normalizeSource(event.text, selection: sourceSelection)
        let normalizedEvent = RecognitionEvent(id: event.id, text: normalizedText, isFinal: event.isFinal)
        let work = pipeline.ingest(normalizedEvent)
        publishPipeline()
        status = event.isFinal ? .translating : .recognizing
        guard var work else { return }
        if translationService.usesContextualMode {
            work.context = translationContext.snapshotAndAppend(work, now: ProcessInfo.processInfo.systemUptime)
        }
        history.record(work)
        guard translationQueue.enqueue(work) else {
            runtimeFailed("The complete translation backlog reached its safety limit before any sentence was discarded.")
            return
        }
        startTranslationWorkerIfNeeded()
    }

    private func startTranslationWorkerIfNeeded() {
        guard translationWorker == nil else { return }
        let workerGeneration = pipeline.generation
        translationWorker = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let work = self.translationQueue.popFirst() {
                if !Self.endsWithSentencePunctuation(work.text) {
                    try? await Task.sleep(for: .seconds(OverlaySettings.translationPause))
                }
                guard !Task.isCancelled, work.generation == self.pipeline.generation else { continue }
                do {
                    let translation = try await self.translationService.translate(work, rules: self.activeTranslationTermRules,
                                                                                queuedCount: self.translationQueue.items.count)
                    guard !Task.isCancelled, work.generation == self.pipeline.generation else { break }
                    self.contextualTranslationStatusKey = self.translationService.contextualStatusKey
                    self.history.complete(work, translation: translation)
                    _ = self.pipeline.applyTranslation(
                        translation,
                        to: work.segmentID,
                        generation: work.generation
                    )
                    self.publishPipeline()
                    if work.generation == self.pipeline.generation,
                       self.settings.automaticallySpeakTranslations {
                        let result = self.translationSpeechService.enqueue(
                            segmentID: work.segmentID,
                            sequence: work.sequence,
                            text: translation,
                            voiceIdentifier: self.settings.translationVoiceIdentifier,
                            generation: work.generation
                        )
                        switch result {
                        case .enqueued:
                            break
                        case .voiceUnavailable:
                            self.settings.automaticallySpeakTranslations = false
                            self.notice = "No installed system voice is available for the target language."
                        case .backlogLimitReached:
                            self.settings.automaticallySpeakTranslations = false
                            self.notice = "The complete-reading backlog reached its safety limit before any queued sentence was discarded."
                        }
                    }
                    self.status = .listening
                } catch is CancellationError {
                    break
                } catch {
                    guard !Task.isCancelled, work.generation == self.pipeline.generation else { break }
                    self.contextualTranslationStatusKey = self.translationService.contextualStatusKey
                    self.history.complete(work, translation: nil)
                    self.notice = "Translation unavailable: \(error.localizedDescription)"
                    self.status = .listening
                }
            }
            guard workerGeneration == self.pipeline.generation else { return }
            self.translationWorker = nil
            if !self.translationQueue.items.isEmpty { self.startTranslationWorkerIfNeeded() }
        }
    }

    private func publishPipeline() {
        segments = pipeline.segments
        interimSourceText = pipeline.interimSourceText
    }

    private func runtimeFailed(_ message: String) {
        guard running else { return }
        Task { await stopCaptions(finalStatus: .error(message)) }
    }

    private func openSettingsURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private func isCurrentModelPreparation(_ generation: UInt64) -> Bool {
        activeModelPreparationGeneration == generation && !terminationRequested
    }

    private func finishModelPreparation(generation: UInt64) {
        guard activeModelPreparationGeneration == generation else { return }
        activeModelPreparationGeneration = nil
        modelPreparationTask = nil
        modelPreparationActive = false
    }

    /// Speech explicitly documents: “The system does not guarantee the execution of
    /// this block on your app's main dispatch queue.”
    /// Keeping the continuation bridge nonisolated prevents Swift 6 from attaching the
    /// AppModel's MainActor precondition to the framework-owned callback.
    private nonisolated static func requestSpeechAuthorization() async
        -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authorization in
                continuation.resume(returning: authorization)
            }
        }
    }

    private static func mapSpeechPermission(_ value: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch value {
        case .notDetermined: .notDetermined
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    private static func mapMicrophonePermission(
        _ value: AVAudioApplication.recordPermission
    ) -> PermissionState {
        switch value {
        case .undetermined: .notDetermined
        case .granted: .granted
        case .denied: .denied
        @unknown default: .restricted
        }
    }

    private static func endsWithSentencePunctuation(_ text: String) -> Bool {
        [".", "?", "!", "。", "？", "！", "…"].contains { text.hasSuffix($0) }
    }
}

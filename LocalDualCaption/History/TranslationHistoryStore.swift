import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class TranslationHistoryStore: ObservableObject {
    static let maximumQueuedWrites = 256
    @Published private(set) var enabled = false
    @Published private(set) var activeSessionID: String?
    @Published private(set) var sessions: [HistorySession] = []
    @Published private(set) var revision = 0
    @Published private(set) var messageKey: String?
    @Published private(set) var exporting = false
    @Published private(set) var managing = false
    private let maximumTextBytes: Int
    private let database: HistoryDatabase
    private var activeSession: HistorySession?
    private var generation: Int?
    private var pendingSequences: Set<Int> = []
    private var writes: [HistoryMutation] = []
    private var worker: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private let digestGenerator: (any HistoryDigestGenerating)?
    private var digestTask: Task<Void, Never>?
    private var availabilityRetryTask: Task<Void, Never>?
    private var digestEpoch = 0
    private var attemptedDigests: Set<String> = [] // At most four keys per retained session (legacy + three levels).
    private var lastAvailability: HistoryDigestState?
    private var recovered = false
    private var recoveryTask: Task<Void, Error>?
    private var captionsActive = false
    private var terminating = false
    var interfaceLanguage = "en"

    init(url: URL? = nil, limits: HistoryDatabase.Limits = .init(), digestGenerator: (any HistoryDigestGenerating)? = AppleHistoryDigestGenerator()) {
        self.digestGenerator = digestGenerator
        maximumTextBytes = limits.maximumTextBytes
        let location = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "HoverCue/History/history.sqlite")
        database = HistoryDatabase(url: location, limits: limits)
    }

    var hasPendingWrites: Bool { worker != nil || !writes.isEmpty || exportTask != nil }

    func enable() {
        guard !managing else { return }
        enabled = true
        messageKey = nil
    }

    func disable() {
        enabled = false
        finishSession()
    }

    func beginSession(source: String, target: String, generation: Int, titleLanguage: String = "en", summaryLevel: HistorySummaryLevel = .standard) {
        finishSession()
        guard enabled else { return }
        let session = HistorySession(id: UUID().uuidString, startedAt: Date(), sourceLanguage: source, targetLanguage: target, titleLanguage: titleLanguage, summaryLevel: summaryLevel, initialSummaryLevel: summaryLevel)
        cancelDigests()
        activeSession = session
        activeSessionID = session.id
        self.generation = generation
    }

    func record(_ work: TranslationWorkItem) {
        guard enabled, generation == work.generation, let activeSession, !pendingSequences.contains(work.sequence) else { return }
        guard pendingSequences.count < BoundedTranslationSpeechQueue.completeModeCapacity else { fail(HistoryFailure.limit); return }
        guard work.text.utf8.count <= maximumTextBytes else { fail(HistoryFailure.invalidContent); return }
        pendingSequences.insert(work.sequence)
        enqueue(.append(activeSession, HistoryEntry(sequence: work.sequence, timestamp: Date(), source: work.text)))
    }

    func complete(_ work: TranslationWorkItem, translation: String?) {
        guard enabled, generation == work.generation, let activeSessionID,
              pendingSequences.remove(work.sequence) != nil else { return }
        guard translation == nil || translation!.utf8.count <= maximumTextBytes else { fail(HistoryFailure.invalidContent); return }
        enqueue(.translate(sessionID: activeSessionID, sequence: work.sequence, text: translation))
    }

    func finishSession() {
        let id = activeSessionID
        activeSession = nil
        activeSessionID = nil
        generation = nil
        pendingSequences.removeAll(keepingCapacity: false)
        if let id { enqueue(.finish(sessionID: id, date: Date())) }
    }

    func reload() async {
        do {
            if !recovered {
                if recoveryTask == nil {
                    let database = database
                    let activeID = activeSessionID
                    let language = interfaceLanguage
                    recoveryTask = Task { try await database.recover(excluding: activeID, titleLanguage: language) }
                }
                try await recoveryTask?.value
                recovered = true
                recoveryTask = nil
            }
            updateSessions(try await database.sessions())
            scheduleDigests()
        }
        catch is CancellationError { return }
        catch { recoveryTask = nil; messageKey = "History could not be opened. Existing files have been kept." }
    }

    func page(sessionID: String, offset: Int) async throws -> HistoryPage {
        try await database.page(sessionID: sessionID, offset: offset)
    }

    func selectSummaryLevel(_ level: HistorySummaryLevel?, sessionID: String) async {
        guard !managing, !terminating, !exporting,
              let session = sessions.first(where: { $0.id == sessionID }), session.summaryLevel != level,
              level != nil || session.legacyDigest.state == .ready else { return }
        cancelDigests()
        do {
            try await database.selectSummaryLevel(sessionID: sessionID, level: level)
            attemptedDigests.remove(sessionID + ":" + (level?.rawValue ?? "legacy"))
            revision &+= 1
            await reload()
        } catch { messageKey = "The summary level could not be changed. Existing summaries have been kept." }
    }

    func delete(sessionID: String) async {
        guard !managing, !exporting else { return }
        managing = true
        cancelDigests()
        defer { managing = false; scheduleDigests() }
        // Finish first, then drain accepted writes: deletion can never resurrect rows.
        if activeSessionID == sessionID { disable() }
        await flush()
        do { try await database.apply(.delete(sessionID: sessionID)); revision &+= 1; await reload() }
        catch { messageKey = "History could not be deleted. Please try again." }
    }

    func clear() async {
        guard !managing, !exporting else { return }
        managing = true
        cancelDigests()
        defer { managing = false; scheduleDigests() }
        disable()
        await flush()
        do { try await database.apply(.clear); revision &+= 1; await reload() }
        catch { messageKey = "History could not be deleted. Please try again." }
    }

    func flush() async {
        while let worker { await worker.value }
    }

    func waitForPendingOperations() async {
        await flush()
        if let exportTask { await exportTask.value }
    }

    func dismissMessage() { messageKey = nil }

    func setCaptionsActive(_ active: Bool) {
        captionsActive = active
        if active { cancelDigests() } else { scheduleDigests() }
    }

    func prepareForTermination() {
        terminating = true
        cancelDigests()
        disable()
    }

    /// Called when the app becomes active; recheck unavailable models without
    /// repeatedly retrying a failed request while the app remains open.
    func refreshDigestAvailability() async {
        guard let digestGenerator else { return }
        let waiting = sessions.first { $0.digest.state == .modelNotReady || $0.digest.state == .intelligenceDisabled }
        guard let session = waiting ?? sessions.first(where: { $0.digest.state != .ready && $0.digest.state != .insufficient }) else { return }
        let state = await digestGenerator.availability(for: session)
        let availableStates: Set<HistoryDigestState> = [.pending, .unsupportedLanguage]
        if availableStates.contains(state), lastAvailability.map({ !availableStates.contains($0) }) ?? true {
            attemptedDigests = Set(sessions.filter { ($0.digest.state == .failed || $0.digest.state == .languageMismatch) }.map(\.digestJobKey))
        }
        lastAvailability = state
        scheduleDigests()
    }

    func waitForSummaries() async {
        await flush()
        scheduleDigests()
        while let digestTask { await digestTask.value }
    }

    private func updateSessions(_ catalog: [HistorySession]) {
        sessions = catalog
        let retained = Set(catalog.flatMap { session in [session.id + ":legacy"] + HistorySummaryLevel.allCases.map { session.id + ":" + $0.rawValue } })
        attemptedDigests.formIntersection(retained)
    }

    private func cancelDigests() {
        digestEpoch &+= 1
        digestTask?.cancel()
        availabilityRetryTask?.cancel()
        availabilityRetryTask = nil
    }

    private func scheduleAvailabilityRetry() {
        guard availabilityRetryTask == nil, !terminating, !captionsActive,
              sessions.contains(where: { $0.digest.state == .modelNotReady || $0.digest.state == .intelligenceDisabled }) else { return }
        availabilityRetryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            guard let self else { return }
            self.availabilityRetryTask = nil
            await self.refreshDigestAvailability()
        }
    }

    private func scheduleDigests() {
        guard digestGenerator != nil, digestTask == nil, !captionsActive, activeSessionID == nil,
              !managing, !terminating else { return }
        guard sessions.contains(where: { $0.endedAt != nil && $0.digest.state != .ready && $0.digest.state != .insufficient && !attemptedDigests.contains($0.digestJobKey) }) else {
            scheduleAvailabilityRetry()
            return
        }
        digestTask = Task { @MainActor [weak self] in
            guard let self, let generator = self.digestGenerator else { return }
            while !Task.isCancelled, !self.captionsActive, !self.terminating, !self.managing,
                  self.activeSessionID == nil,
                  let session = self.sessions.first(where: { $0.endedAt != nil && $0.digest.state != .ready && $0.digest.state != .insufficient && !self.attemptedDigests.contains($0.digestJobKey) }) {
                let epoch = self.digestEpoch
                self.attemptedDigests.insert(session.digestJobKey)
                do {
                    let availability = await generator.availability(for: session)
                    try Task.checkCancellation()
                    self.lastAvailability = availability
                    if availability != .pending {
                        try await self.database.setDigestState(sessionID: session.id, state: availability, level: session.summaryLevel)
                    } else {
                        try await self.database.setDigestState(sessionID: session.id, state: .generating, level: session.summaryLevel)
                        await self.reload()
                        let database = self.database
                        let result = try await generator.generate(for: session) { offset in
                            try Task.checkCancellation()
                            return try await database.page(sessionID: session.id, offset: offset)
                        }
                        try Task.checkCancellation()
                        guard epoch == self.digestEpoch else { throw CancellationError() }
                        try await self.database.saveDigest(sessionID: session.id, result: result, level: session.summaryLevel)
                    }
                } catch {
                    let cancelled = Task.isCancelled || epoch != self.digestEpoch || error is CancellationError
                    let state: HistoryDigestState = cancelled ? .pending : ((error as? HistoryDigestError).map {
                        switch $0 { case .state(let state): return state }
                    } ?? .failed)
                    try? await self.database.setDigestState(sessionID: session.id, state: state, level: session.summaryLevel)
                    if cancelled { self.attemptedDigests.remove(session.digestJobKey) }
                }
                self.revision &+= 1
                // The task may be cancelled; this catalog refresh must still clear
                // the visible generating state, without logging model errors/text.
                if let sessions = try? await self.database.catalogAfterDigest() { self.updateSessions(sessions) }
            }
            self.digestTask = nil
            self.scheduleDigests()
        }
    }

    func export(_ session: HistorySession, language: AppLanguage) {
        guard !exporting, !managing else { return }
        exporting = true
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = HistoryDigestText.exportFilename(session)
        panel.message = language.localized("Before recording or exporting, make sure everyone involved knows and agrees. History is saved on this Mac.")
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { self.exporting = false; return }
            self.exportTask = Task { @MainActor in
                defer { self.exporting = false; self.exportTask = nil }
                await self.flush()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    try await self.database.export(session: session, to: url, labels: ["Translation history", "Original", "Translation", "Translation failed", "Translation incomplete", "AI summary", "Some entries are incomplete. The summary uses only available text.", "The selected summary is not ready. The full transcript follows.", "Full transcript", "Summary detail", session.summaryLevel?.titleKey ?? "Legacy summary"].map { language.localized($0) })
                    self.messageKey = "History exported. Files saved to a synced folder may be synced by your system."
                } catch {
                    self.messageKey = "History could not be exported. Your existing file has not been replaced."
                }
            }
        }
        if let window = NSApplication.shared.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }

    private func enqueue(_ mutation: HistoryMutation) {
        guard writes.count < Self.maximumQueuedWrites else { fail(HistoryFailure.limit); return }
        writes.append(mutation)
        guard worker == nil else { return }
        worker = Task { @MainActor [weak self] in
            guard let self else { return }
            while !self.writes.isEmpty {
                let next = self.writes.removeFirst()
                do {
                    try await self.database.apply(next)
                    self.revision &+= 1
                } catch {
                    self.fail(error)
                    await self.reload()
                    break
                }
                // Refresh a batch rather than publishing a list for each sentence.
                if self.writes.isEmpty { await self.reload() }
            }
            self.worker = nil
        }
    }

    private func fail(_ error: Error) {
        // Never interpolate framework errors: they could contain private text.
        messageKey = (error as? HistoryFailure ?? .storage).messageKey
        enabled = false
        activeSession = nil
        activeSessionID = nil
        generation = nil
        pendingSequences.removeAll(keepingCapacity: false)
        writes.removeAll(keepingCapacity: false)
    }
}

import Foundation

/// A deadline returns promptly even if a framework request ignores cancellation.
/// A timed-out request retains its single slot until it really finishes: no orphan fan-out.
@MainActor
final class TimedContextualRequest {
    private let generator: any ContextualTextGenerating
    private var task: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var waiter: CheckedContinuation<String, Error>?
    private var requestID: UUID?
    var isBusy: Bool { task != nil }

    init(generator: any ContextualTextGenerating = AppleContextualTranslator()) { self.generator = generator }

    func run(text: String, context: [String], source: CaptionLanguageSelection, target: CaptionLanguageSelection,
             rules: [TranslationTermRule], timeout: TimeInterval) async throws -> String {
        try Task.checkCancellation()
        guard task == nil else { throw ContextualTranslationError.busy }
        let id = UUID()
        requestID = id
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter = continuation
                task = Task { [generator] in
                    let result: Result<String, Error>
                    do { result = .success(try await generator.translate(text, context: context, source: source, target: target, rules: rules)) }
                    catch { result = .failure(error) }
                    guard self.requestID == id else { return }
                    self.deadline?.cancel(); self.deadline = nil
                    self.task = nil; self.requestID = nil
                    let pending = self.waiter; self.waiter = nil
                    pending?.resume(with: result)
                }
                deadline = Task {
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    guard self.requestID == id else { return }
                    self.resolve(.failure(ContextualTranslationError.timeout))
                    self.task?.cancel()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.requestID == id else { return }
                self?.cancel()
            }
        }
    }

    func cancel() {
        deadline?.cancel(); deadline = nil
        resolve(.failure(CancellationError()))
        task?.cancel()
    }

    private func resolve(_ result: Result<String, Error>) {
        let pending = waiter; waiter = nil
        pending?.resume(with: result)
    }
}

@MainActor
final class ContextualTranslationCoordinator {
    static let maximumQueuedBeforeFallback = 6
    static let maximumQueueAge: TimeInterval = 12
    private let request: TimedContextualRequest
    private let timeout: TimeInterval
    private let now: () -> TimeInterval
    private var source: CaptionLanguageSelection?
    private var target: CaptionLanguageSelection?
    private var epoch = 0
    private var consecutiveFailures = 0
    private var fallbackForSession = false
    private(set) var statusKey: String?
    var active: Bool { source != nil && target != nil }
    var localRequestInFlight: Bool { request.isBusy }

    init(generator: any ContextualTextGenerating = AppleContextualTranslator(), timeout: TimeInterval = 8,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        request = TimedContextualRequest(generator: generator)
        self.timeout = timeout
        self.now = now
    }

    func activate(source: CaptionLanguageSelection, target: CaptionLanguageSelection, availability: ContextualModelAvailability) {
        cancel()
        self.source = source; self.target = target
        consecutiveFailures = 0
        fallbackForSession = availability != .available
        statusKey = availability == .available ? "Contextual enhancement · On-device"
            : "Contextual enhancement unavailable; using system translation."
    }

    func cancel() {
        epoch &+= 1
        source = nil; target = nil
        request.cancel()
        consecutiveFailures = 0; fallbackForSession = false; statusKey = nil
    }

    func translate(_ work: TranslationWorkItem, rules: [TranslationTermRule], queuedCount: Int,
                   fallback: @MainActor () async throws -> String) async throws -> String {
        try Task.checkCancellation()
        guard let source, let target else { throw CancellationError() }
        let expectedEpoch = epoch
        let snapshot = work.context ?? TranslationContextSnapshot()
        if !fallbackForSession,
           queuedCount >= Self.maximumQueuedBeforeFallback ||
           (snapshot.enqueuedAt > 0 && now() - snapshot.enqueuedAt > Self.maximumQueueAge) {
            fallbackForSession = true
            statusKey = "Contextual enhancement paused for this session; using system translation."
        }
        if !fallbackForSession {
            do {
                let translated = try await request.run(text: work.text, context: snapshot.precedingSources,
                                                       source: source, target: target, rules: rules, timeout: timeout)
                try Task.checkCancellation()
                guard epoch == expectedEpoch else { throw CancellationError() }
                consecutiveFailures = 0
                statusKey = "Contextual enhancement · On-device"
                return translated
            } catch {
                try Task.checkCancellation()
                guard epoch == expectedEpoch else { throw CancellationError() }
                // A cancelled earlier request still occupying its slot is not a
                // second failed generation. Retry naturally once that slot clears.
                if (error as? ContextualTranslationError) != .busy { consecutiveFailures += 1 }
                if consecutiveFailures >= 2 {
                    fallbackForSession = true
                    statusKey = "Contextual enhancement paused for this session; using system translation."
                } else {
                    statusKey = "Using system translation for this sentence."
                }
            }
        }
        try Task.checkCancellation()
        guard epoch == expectedEpoch else { throw CancellationError() }
        let translated = try await fallback()
        try Task.checkCancellation()
        guard epoch == expectedEpoch else { throw CancellationError() }
        return translated
    }
}

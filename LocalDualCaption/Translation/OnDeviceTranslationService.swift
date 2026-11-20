import Foundation
import Translation

@MainActor
final class OnDeviceTranslationService {
    private var sessionBox: TranslationSessionBox?
    private var preparingSessionBox: TranslationSessionBox?
    private var fastFallbackBox: TranslationSessionBox?
    private var sessionGeneration = 0
    private let contextual = ContextualTranslationCoordinator()
    var usesContextualMode: Bool { contextual.active }
    var contextualStatusKey: String? { contextual.statusKey }

    func prepareAndUse(
        _ session: TranslationSession,
        expectedTarget: CaptionLanguageSelection
    ) async throws {
        let box = TranslationSessionBox(session, expectedTarget: expectedTarget)
        preparingSessionBox = box
        defer {
            if preparingSessionBox === box {
                preparingSessionBox = nil
            }
        }
        do {
            try await box.prepare()
        } catch {
            box.cancel()
            throw error
        }
        try Task.checkCancellation()
        sessionBox = box
    }

    func activateInstalledSession(
        source: CaptionLanguageSelection,
        target: CaptionLanguageSelection,
        preference: TranslationModelPreference
    ) throws {
        sessionGeneration &+= 1
        contextual.cancel()
        fastFallbackBox?.cancel(); fastFallbackBox = nil
        sessionBox?.cancel()
        sessionBox = nil
        if preference == .contextual {
            contextual.activate(source: source, target: target,
                                availability: ContextualModelAvailability.current(source: source, target: target))
            if #available(macOS 26.4, *) {
                fastFallbackBox = TranslationSessionBox(TranslationSession(installedSource: source.translationLanguage,
                                                                          target: target.translationLanguage,
                                                                          preferredStrategy: .lowLatency), expectedTarget: target)
            }
        }
        if #available(macOS 26.4, *) {
            sessionBox = TranslationSessionBox(TranslationSession(
                installedSource: source.translationLanguage,
                target: target.translationLanguage,
                preferredStrategy: preference.strategy
            ), expectedTarget: target)
        } else {
            sessionBox = TranslationSessionBox(TranslationSession(
                installedSource: source.translationLanguage,
                target: target.translationLanguage
            ), expectedTarget: target)
        }
    }

    func translate(_ text: String, rules: [TranslationTermRule] = []) async throws -> String {
        guard let sessionBox else { throw TranslationServiceError.notPrepared }
        try Task.checkCancellation()
        let translated = try await sessionBox.translate(text, rules: rules)
        try Task.checkCancellation()
        return translated
    }

    func translate(_ work: TranslationWorkItem, rules: [TranslationTermRule], queuedCount: Int) async throws -> String {
        guard contextual.active else { return try await translate(work.text, rules: rules) }
        let fallback = sessionBox
        let fast = fastFallbackBox
        let expectedGeneration = sessionGeneration
        // Give native translation the intact sentence. Automatically replacing
        // dates and times with markers can break grammar, especially negation.
        // Only explicit user terminology is protected, as in the existing modes.
        return try await contextual.translate(work, rules: rules, queuedCount: queuedCount) {
            if let fast {
                do { return try await fast.translate(work.text, rules: rules) }
                catch { try Task.checkCancellation() }
            }
            guard self.sessionGeneration == expectedGeneration else { throw CancellationError() }
            guard let fallback else { throw TranslationServiceError.notPrepared }
            return try await fallback.translate(work.text, rules: rules)
        }
    }

    func cancel() {
        sessionGeneration &+= 1
        contextual.cancel()
        fastFallbackBox?.cancel(); fastFallbackBox = nil
        preparingSessionBox?.cancel()
        preparingSessionBox = nil
        sessionBox?.cancel()
        sessionBox = nil
    }
}

private final class TranslationSessionBox: @unchecked Sendable {
    private let session: TranslationSession
    private let expectedTarget: CaptionLanguageSelection

    init(_ session: TranslationSession, expectedTarget: CaptionLanguageSelection) {
        self.session = session
        self.expectedTarget = expectedTarget
    }

    func translate(_ text: String, rules: [TranslationTermRule]) async throws -> String {
        if !rules.isEmpty {
            guard #available(macOS 26.4, *) else { throw TranslationServiceError.terminologyRequiresNewerSystem }
            let protected = try ProtectedTermTranslation(text: text, rules: rules)
            if !protected.terms.isEmpty {
                let response = try await session.translate(protected.input)
                try Task.checkCancellation()
                guard expectedTarget.matches(response.targetLanguage) else {
                    throw TranslationServiceError.unexpectedTargetLanguage
                }
                return try protected.restore(response.targetText) { fragment in
                    try CaptionTextNormalizer.normalizeTranslation(
                        fragment, expectedTarget: expectedTarget, actualTargetLanguage: response.targetLanguage
                    )
                }
            }
        }
        let response = try await session.translate(text)
        return try CaptionTextNormalizer.normalizeTranslation(
            response.targetText,
            expectedTarget: expectedTarget,
            actualTargetLanguage: response.targetLanguage
        )
    }

    func prepare() async throws {
        try await session.prepareTranslation()
    }

    func cancel() {
        session.cancel()
    }
}

enum TranslationServiceError: LocalizedError {
    case notPrepared
    case unexpectedTargetLanguage
    case chineseNormalizationFailed
    case terminologyNotPreserved
    case terminologyRequiresNewerSystem
    case terminologySafetyLimit

    var errorDescription: String? {
        switch self {
        case .notPrepared:
            "The selected offline translation model is not prepared."
        case .unexpectedTargetLanguage:
            "The system translation returned an unexpected target language."
        case .chineseNormalizationFailed:
            "The system could not normalize the Chinese translation."
        case .terminologyNotPreserved:
            "The translation model did not preserve a terminology rule. This translation was not displayed."
        case .terminologyRequiresNewerSystem:
            "Translation terminology requires macOS 26.4 or later."
        case .terminologySafetyLimit:
            "This sentence exceeded the terminology safety limit. This translation was not displayed."
        }
    }
}

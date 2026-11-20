import Foundation
import Translation

enum TranslationModelPreference: String, CaseIterable, Identifiable {
    case lowLatency
    case contextual

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .lowLatency: "Low latency"
        case .contextual: "Contextual enhancement"
        }
    }

    var descriptionKey: String {
        switch self {
        case .lowLatency: "Uses Apple system translation, prioritizing response speed."
        case .contextual: "Uses Apple Intelligence on this Mac to translate with recent source context."
        }
    }

    @available(macOS 26.4, *)
    var strategy: TranslationSession.Strategy {
        switch self {
        case .lowLatency: .lowLatency
        // For contextual mode this configures ONLY its installed system fallback.
        case .contextual: .highFidelity
        }
    }
}

enum TranslationModelManager {
    static func state(
        source: CaptionLanguageSelection,
        target: CaptionLanguageSelection,
        preference: TranslationModelPreference
    ) async -> ModelState {
        guard source.language != target.language else { return .unsupported }
        if preference == .contextual,
           ContextualModelAvailability.current(source: source, target: target) == .available {
            return .installed
        }
        let status: LanguageAvailability.Status
        if #available(macOS 26.4, *) {
            status = await LanguageAvailability(preferredStrategy: preference.strategy)
                .status(from: source.translationLanguage, to: target.translationLanguage)
        } else {
            status = await LanguageAvailability()
                .status(from: source.translationLanguage, to: target.translationLanguage)
        }

        return switch status {
        case .installed: .installed
        case .supported: .downloadable
        case .unsupported: .unsupported
        @unknown default: .error
        }
    }
}

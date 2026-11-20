import Foundation
import NaturalLanguage

/// Validates generated text against the immutable languages on its history row.
/// It never consults the current app language, locale, or system preferences.
enum HistoryDigestLanguagePolicy {
    static let version = 1
    static let identifiers = ["en", "zh-Hans", "zh-Hant", "de", "es", "fr", "it", "ja", "ko", "pt"]

    static func name(for identifier: String) throws -> String {
        switch identifier {
        case "en": return "English (en)"
        case "zh-Hans": return "Simplified Chinese (zh-Hans); use 简体中文 only, never 繁體中文"
        case "zh-Hant": return "Traditional Chinese (zh-Hant); use 繁體中文 only, never 简体中文"
        case "de": return "German / Deutsch (de)"
        case "es": return "Spanish / español (es)"
        case "fr": return "French / français (fr)"
        case "it": return "Italian / italiano (it)"
        case "ja": return "Japanese / 日本語 (ja)"
        case "ko": return "Korean / 한국어 (ko)"
        case "pt": return "Portuguese / português (pt)"
        default: throw HistoryDigestError.state(.unsupportedLanguage)
        }
    }

    static func normalized(_ result: HistoryDigestResult, for session: HistorySession) throws -> HistoryDigestResult {
        // Check size before invoking text processing, as well as after conversion.
        try result.validate()
        let normalized = HistoryDigestResult(
            title: try normalize(result.title, language: session.titleLanguage),
            sourceSummary: try normalize(result.sourceSummary, language: session.sourceLanguage),
            targetSummary: try normalize(result.targetSummary, language: session.targetLanguage),
            incomplete: result.incomplete
        )
        try normalized.validate()
        try validateLanguage(normalized.title, expected: session.titleLanguage, isTitle: true)
        try validateLanguage(normalized.sourceSummary, expected: session.sourceLanguage)
        try validateLanguage(normalized.targetSummary, expected: session.targetLanguage)
        return normalized
    }

    static func normalize(_ text: String, language: String) throws -> String {
        _ = try name(for: language)
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard language == "zh-Hans" || language == "zh-Hant" else { return clean }
        guard let result = CaptionTextNormalizer.normalizeChinese(clean, script: language == "zh-Hans" ? .simplified : .traditional) else {
            throw HistoryDigestError.state(.failed)
        }
        return result
    }

    static func validateLanguage(_ text: String, expected: String, isTitle: Bool = false) throws {
        _ = try name(for: expected)
        // Dominant-language recognition alone can miss an East Asian phrase
        // embedded in an otherwise Latin-language paragraph. A substantial span
        // must be rewritten too; short names/acronyms remain language-neutral.
        if ["en", "de", "es", "fr", "it", "pt"].contains(expected) {
            let unexpected = text.unicodeScalars.filter {
                (0x3400...0x9FFF).contains($0.value) || (0x3040...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value)
            }.count
            if unexpected >= 5 { throw HistoryDigestError.state(.languageMismatch) }
        }
        // Very short titles and proper names cannot reliably identify a language.
        // Preserve names, acronyms, punctuation, diacritics and mixed-script names.
        let letterCount = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letterCount >= (isTitle ? 6 : 12) else { return }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 10)
        guard let dominant = recognizer.dominantLanguage, let confidence = hypotheses[dominant], confidence >= 0.65 else { return }
        func base(_ code: String) -> String { Locale.Language(identifier: code).languageCode?.identifier ?? code }
        let expectedBase = base(expected)
        if base(dominant.rawValue) == expectedBase { return }
        // Short Spanish titles such as "Visitar la biblioteca" are also valid
        // Catalan. Galician shares short phrases with Spanish and Portuguese.
        // The recognizer can assign the entire probability to that unsupported
        // neighbour; this is ambiguity, not evidence of a wrong-language title.
        if isTitle {
            let shared = expectedBase == "es" ? ["ca", "gl"] : (expectedBase == "pt" ? ["gl"] : [])
            if shared.contains(base(dominant.rawValue)) { return }
        }
        let expectedConfidence = hypotheses.filter { base($0.key.rawValue) == expectedBase }.values.reduce(0, +)
        // A short title can be valid in two related languages (for example,
        // Spanish and Catalan share "Visita a la biblioteca"). Keep a plausible
        // requested-language candidate; require stronger evidence for summaries.
        // Never force recognition to the requested language with constraints/hints.
        guard expectedConfidence >= (isTitle ? 0.05 : 0.15) else { throw HistoryDigestError.state(.languageMismatch) }
    }
}

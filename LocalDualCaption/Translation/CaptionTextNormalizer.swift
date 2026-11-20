import Foundation

enum CaptionTextNormalizer {
    static func normalizeSource(_ text: String, selection: CaptionLanguageSelection) -> String {
        guard selection.language == .chinese else { return text }
        return normalizeChinese(text, script: selection.chineseScript) ?? text
    }

    static func normalizeTranslation(
        _ text: String,
        expectedTarget: CaptionLanguageSelection,
        actualTargetLanguage: Locale.Language
    ) throws -> String {
        guard expectedTarget.matches(actualTargetLanguage) else {
            throw TranslationServiceError.unexpectedTargetLanguage
        }
        guard expectedTarget.language == .chinese else { return text }
        guard let normalized = normalizeChinese(text, script: expectedTarget.chineseScript) else {
            throw TranslationServiceError.chineseNormalizationFailed
        }
        return normalized
    }

    static func normalizeChinese(_ text: String, script: ChineseScript) -> String? {
        let transform = script == .simplified ? "Traditional-Simplified" : "Simplified-Traditional"
        return text.applyingTransform(StringTransform(transform), reverse: false)
    }
}

import Foundation
import Translation

/// A separate, short-lived session cannot cancel or reconfigure live translation.
/// Only already-installed Apple resources are used. No prepare/download is invoked.
enum HistoryDigestTranslator {
    @MainActor
    static func installedTranslation(_ text: String, source: String, target: String) async throws -> String? {
        let sourceSelection = try selection(source)
        let targetSelection = try selection(target)
        if sourceSelection.language == targetSelection.language {
            return try HistoryDigestLanguagePolicy.normalize(text, language: target)
        }
        let status: LanguageAvailability.Status
        if #available(macOS 26.4, *) {
            status = await LanguageAvailability(preferredStrategy: .lowLatency).status(from: sourceSelection.translationLanguage, to: targetSelection.translationLanguage)
        } else {
            status = await LanguageAvailability().status(from: sourceSelection.translationLanguage, to: targetSelection.translationLanguage)
        }
        try Task.checkCancellation()
        guard status == .installed else { return nil }
        let service = OnDeviceTranslationService()
        defer { service.cancel() }
        do {
            try service.activateInstalledSession(source: sourceSelection, target: targetSelection, preference: .lowLatency)
            let translated = try await service.translate(text)
            try Task.checkCancellation()
            return translated
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }

    static func selection(_ code: String) throws -> CaptionLanguageSelection {
        _ = try HistoryDigestLanguagePolicy.name(for: code)
        let script: ChineseScript = code == "zh-Hant" ? .traditional : .simplified
        let base = Locale.Language(identifier: code).languageCode?.identifier
        guard let language = CaptionLanguage.allCases.first(where: { $0.languageCode == base }) else { throw HistoryDigestError.state(.unsupportedLanguage) }
        return CaptionLanguageSelection(language: language, chineseScript: script)
    }
}

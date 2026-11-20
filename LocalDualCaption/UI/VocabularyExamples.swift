import Foundation

/// Display-only examples. They never become saved vocabulary or recognition hints.
enum VocabularyExamples {
    static func terms(for selection: CaptionLanguageSelection) -> [String] {
        switch selection.language {
        case .english: ["Apple Watch", "SCADA", "renewable energy"]
        case .chinese:
            selection.chineseScript == .simplified
                ? ["苹果手表", "SCADA", "可再生能源"]
                : ["蘋果手錶", "SCADA", "再生能源"]
        case .german: ["Apple Watch", "SCADA", "erneuerbare Energien"]
        case .spanish: ["Apple Watch", "SCADA", "energías renovables"]
        case .french: ["Apple Watch", "SCADA", "énergies renouvelables"]
        case .italian: ["Apple Watch", "SCADA", "energie rinnovabili"]
        case .japanese: ["Apple Watch", "SCADA", "再生可能エネルギー"]
        case .korean: ["Apple Watch", "SCADA", "재생 에너지"]
        case .portuguese: ["Apple Watch", "SCADA", "energias renováveis"]
        }
    }

    static func title(for selection: CaptionLanguageSelection, in appLanguage: AppLanguage) -> String {
        var languageName = selection.language.displayName(in: appLanguage)
        if selection.language == .chinese {
            languageName += " (\(appLanguage.localized(selection.chineseScript.localizationKey)))"
        }
        return String(format: appLanguage.localized("Examples for %@ — one term per line"), languageName)
    }
    static func fixedTranslations(source: CaptionLanguageSelection, target: CaptionLanguageSelection) -> String {
        let sources = [terms(for: source)[2], storageTerm(for: source)]
        let targets = [terms(for: target)[2], storageTerm(for: target)]
        return zip(sources, targets).map { "\($0) -> \($1)" }.joined(separator: "\n")
    }

    private static func storageTerm(for selection: CaptionLanguageSelection) -> String {
        switch selection.language {
        case .english: "energy storage"
        case .chinese: selection.chineseScript == .simplified ? "储能" : "儲能"
        case .german: "Energiespeicherung"
        case .spanish: "almacenamiento de energía"
        case .french: "stockage d’énergie"
        case .italian: "accumulo di energia"
        case .japanese: "エネルギー貯蔵"
        case .korean: "에너지 저장"
        case .portuguese: "armazenamento de energia"
        }
    }

}

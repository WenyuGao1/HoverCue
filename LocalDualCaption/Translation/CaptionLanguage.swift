import Foundation

enum CaptionLanguage: String, CaseIterable, Identifiable, Sendable {
    case english
    case chinese
    case german
    case spanish
    case french
    case italian
    case japanese
    case korean
    case portuguese

    var id: String { rawValue }

    var languageCode: String {
        switch self {
        case .english: "en"
        case .chinese: "zh"
        case .german: "de"
        case .spanish: "es"
        case .french: "fr"
        case .italian: "it"
        case .japanese: "ja"
        case .korean: "ko"
        case .portuguese: "pt"
        }
    }

    func displayName(in appLanguage: AppLanguage) -> String {
        appLanguage.locale.localizedString(forLanguageCode: languageCode) ?? rawValue.capitalized
    }

    func speechVariants(chineseScript: ChineseScript) -> [SpeechVariant] {
        switch self {
        case .english:
            ["en-GB", "en-US", "en-AU", "en-CA", "en-IE", "en-IN", "en-NZ", "en-SG", "en-ZA"]
                .map { SpeechVariant(localeIdentifier: $0) }
        case .chinese:
            switch chineseScript {
            case .simplified:
                ["zh-CN", "yue-CN"].map { SpeechVariant(localeIdentifier: $0) }
            case .traditional:
                ["zh-TW", "zh-HK"].map { SpeechVariant(localeIdentifier: $0) }
            }
        case .german:
            ["de-DE", "de-AT", "de-CH"].map { SpeechVariant(localeIdentifier: $0) }
        case .spanish:
            ["es-ES", "es-MX", "es-CL", "es-US"].map { SpeechVariant(localeIdentifier: $0) }
        case .french:
            ["fr-FR", "fr-CA", "fr-BE", "fr-CH"].map { SpeechVariant(localeIdentifier: $0) }
        case .italian:
            ["it-IT", "it-CH"].map { SpeechVariant(localeIdentifier: $0) }
        case .japanese:
            [SpeechVariant(localeIdentifier: "ja-JP")]
        case .korean:
            [SpeechVariant(localeIdentifier: "ko-KR")]
        case .portuguese:
            ["pt-PT", "pt-BR"].map { SpeechVariant(localeIdentifier: $0) }
        }
    }

    func previewText(chineseScript: ChineseScript) -> String {
        switch self {
        case .english:
            "Could you tell us about your experience with renewable energy?"
        case .chinese:
            chineseScript == .simplified
                ? "您能介绍一下您在可再生能源方面的经验吗？"
                : "您能介紹一下您在可再生能源方面的經驗嗎？"
        case .german:
            "Könnten Sie uns von Ihrer Erfahrung mit erneuerbaren Energien erzählen?"
        case .spanish:
            "¿Podría hablarnos de su experiencia con las energías renovables?"
        case .french:
            "Pourriez-vous nous parler de votre expérience dans les énergies renouvelables ?"
        case .italian:
            "Può parlarci della sua esperienza nel settore delle energie rinnovabili?"
        case .japanese:
            "再生可能エネルギーに関するご経験について教えていただけますか？"
        case .korean:
            "재생 에너지 분야의 경험에 대해 말씀해 주시겠어요?"
        case .portuguese:
            "Poderia falar-nos da sua experiência com energias renováveis?"
        }
    }
}

enum ChineseScript: String, CaseIterable, Identifiable, Sendable {
    case simplified
    case traditional

    var id: String { rawValue }
    var localizationKey: String { self == .simplified ? "Simplified" : "Traditional" }
    var translationIdentifier: String { self == .simplified ? "zh-Hans" : "zh-Hant" }
}

struct SpeechVariant: Identifiable, Hashable, Sendable {
    let localeIdentifier: String

    var id: String { localeIdentifier }

    func displayName(in appLanguage: AppLanguage) -> String {
        let identifier = localeIdentifier.replacingOccurrences(of: "-", with: "_")
        return appLanguage.locale.localizedString(forIdentifier: identifier) ?? localeIdentifier
    }
}

struct CaptionLanguageSelection: Equatable, Sendable {
    let language: CaptionLanguage
    let chineseScript: ChineseScript

    var translationLanguage: Locale.Language {
        let identifier = language == .chinese ? chineseScript.translationIdentifier : language.languageCode
        return Locale.Language(identifier: identifier)
    }

    func matches(_ actualLanguage: Locale.Language) -> Bool {
        actualLanguage.languageCode?.identifier == language.languageCode
    }

    var previewText: String {
        language.previewText(chineseScript: chineseScript)
    }

    var speechSynthesisLocaleIdentifier: String {
        language.speechVariants(chineseScript: chineseScript).first?.localeIdentifier
            ?? language.languageCode
    }
}

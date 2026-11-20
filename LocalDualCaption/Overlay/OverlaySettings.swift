import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case portuguese = "pt"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    func displayName(in interfaceLanguage: AppLanguage) -> String {
        interfaceLanguage.locale.localizedString(forIdentifier: rawValue)
            ?? locale.localizedString(forIdentifier: rawValue)
            ?? rawValue
    }

    func localized(_ key: String) -> String {
        guard self != .english,
              let localizationPath = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let localizationBundle = Bundle(path: localizationPath) else {
            return key
        }
        return localizationBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    func localizedMessage(_ message: String) -> String {
        switch message {
        case "Speech Recognition permission is required before the local model can be prepared.":
            return localized("Speech Recognition permission is required before the local model can be prepared.")
        case "Speech Recognition permission is not granted.":
            return localized("Speech Recognition permission is not granted.")
        case "Screen & System Audio Recording permission is not granted.":
            return localized("Screen & System Audio Recording permission is not granted.")
        case "Microphone permission is not granted.":
            return localized("Microphone permission is not granted.")
        case "The selected audio source is no longer available.":
            return localized("The selected audio source is no longer available.")
        case "The selected microphone is no longer available.":
            return localized("The selected microphone is no longer available.")
        case "No microphone input is available.":
            return localized("No microphone input is available.")
        case "Unable to read available microphones.":
            return localized("Unable to read available microphones.")
        case "No installed system voice is available for the target language.":
            return localized("No installed system voice is available for the target language.")
        case "The system audio input changed. Stop and restart captions to use the current microphone.":
            return localized("The system audio input changed. Stop and restart captions to use the current microphone.")
        case "No system-default microphone is available.":
            return localized("No system-default microphone is available.")
        case "Prepare the selected source-language speech model first.":
            return localized("Prepare the selected source-language speech model first.")
        case "Prepare the selected translation model first.":
            return localized("Prepare the selected translation model first.")
        case "The selected offline translation model is not prepared.":
            return localized("The selected offline translation model is not prepared.")
        case "The system translation returned an unexpected target language.":
            return localized("The system translation returned an unexpected target language.")
        case "The system could not normalize the Chinese translation.":
            return localized("The system could not normalize the Chinese translation.")
        case "The selected language pair is not supported by the on-device translation model.":
            return localized("The selected language pair is not supported by the on-device translation model.")
        case "Source and target languages must be different.":
            return localized("Source and target languages must be different.")
        case "If macOS asks you to restart after a permission change, quit and reopen HoverCue.":
            return localized("If macOS asks you to restart after a permission change, quit and reopen HoverCue.")
        case "The translation model did not preserve a terminology rule. This translation was not displayed.",
             "Translation terminology requires macOS 26.4 or later.",
             "This sentence exceeded the terminology safety limit. This translation was not displayed.":
            return localized(message)
        default:
            if message.hasPrefix("Translation unavailable: ") {
                return "\(localized("Translation unavailable")): \(localizedMessage(String(message.dropFirst("Translation unavailable: ".count))))"
            }
            return message
        }
    }
}

enum OverlayGlassMetrics {
    static let fixedAdditionalOpacity = 0.0
    static let lightGlassTintOpacity: CGFloat = 0.12
    static let darkGlassTintOpacity: CGFloat = 0.22
    static let highTransparencyGlassOpacity: CGFloat = 0.04
    static let highTransparencyBorderWidth: CGFloat = 1
    static let highTransparencyBorderOpacity: CGFloat = 0.34
    static let overlayCornerRadius: CGFloat = 28
    static let previewCornerRadius = overlayCornerRadius
    static let captionGroupSpacing: CGFloat = 10
    static let captionPairSpacing: CGFloat = 3
    static let captionHorizontalPadding: CGFloat = 22
    static let captionVerticalPadding: CGFloat = 16
    static let captionOuterPadding: CGFloat = 8
    static let previewMinimumHeight: CGFloat = 132
    static let previewWindowShadowOpacity = 0.18
    static let previewWindowShadowRadius: CGFloat = 14
    static let previewWindowShadowYOffset: CGFloat = 7
}

enum OverlayGlassAppearance: String, CaseIterable, Identifiable {
    case light
    case dark
    case highTransparency

    var id: String { rawValue }
}

enum CaptionDisplayMode: String, CaseIterable, Identifiable {
    case transcriptionAndTranslation
    case transcriptionOnly
    case translationOnly

    var id: String { rawValue }

    var showsTranscription: Bool {
        self != .translationOnly
    }

    var showsTranslation: Bool {
        self != .transcriptionOnly
    }
}

@MainActor
final class OverlaySettings: ObservableObject {
    enum Key {
        static let englishFontSize = "settings.englishFontSize"
        static let chineseFontSize = "settings.chineseFontSize"
        static let englishColor = "settings.englishColor"
        static let chineseColor = "settings.chineseColor"
        static let backgroundColor = "settings.backgroundColor"
        static let glassAppearance = "settings.glassAppearance"
        static let overlayWidth = "settings.overlayWidth"
        static let overlayHeight = "settings.overlayHeight"
        static let captionDisplayMode = "settings.captionDisplayMode"
        static let appLanguage = "settings.appLanguage"
        static let historySummaryLevel = "settings.historySummaryLevel"
        static let sourceLanguage = "settings.sourceLanguage"
        static let targetLanguage = "settings.targetLanguage"
        static let sourceChineseScript = "settings.sourceChineseScript"
        static let targetChineseScript = "settings.targetChineseScript"
        static let localeIdentifier = "settings.localeIdentifier"
        static let translationModelPreference = "settings.translationModelPreference"
        static let automaticallySpeakTranslations = "settings.automaticallySpeakTranslations"
        static let translationVoiceIdentifier = "settings.translationVoiceIdentifier"
        static let translationVoicePreferences = "settings.translationVoicePreferences"
        static let selectedAudioSourceID = "settings.selectedAudioSourceID"
        static let vocabulary = "settings.vocabulary"
        static let translationTermDrafts = "settings.translationTermDrafts"
        static let overlayX = "settings.overlayX"
        static let overlayY = "settings.overlayY"
    }

    static let defaultVocabulary: [String] = []
    private static let legacyVocabularyCount = 24
    private static let legacyVocabularyFingerprint: UInt64 = 0x1beea9d269011b89
    static let overlayWidthRange = 420.0...1400.0
    static let overlayHeightRange = 100.0...620.0
    static let defaultOverlayWidth = 820.0
    static let defaultOverlayHeight = 260.0
    static let translationPause = 0.75

    private let defaults: UserDefaults
    private var resolvingTranslationVoice = false
    private var translationVoicePreferences: [String: String]

    @Published var englishFontSize: Double { didSet { defaults.set(englishFontSize, forKey: Key.englishFontSize) } }
    @Published var chineseFontSize: Double { didSet { defaults.set(chineseFontSize, forKey: Key.chineseFontSize) } }
    @Published var englishColorHex: String { didSet { defaults.set(englishColorHex, forKey: Key.englishColor) } }
    @Published var chineseColorHex: String { didSet { defaults.set(chineseColorHex, forKey: Key.chineseColor) } }
    @Published var backgroundColorHex: String { didSet { defaults.set(backgroundColorHex, forKey: Key.backgroundColor) } }
    @Published var glassAppearance: OverlayGlassAppearance {
        didSet { defaults.set(glassAppearance.rawValue, forKey: Key.glassAppearance) }
    }
    @Published var overlayWidth: Double { didSet { defaults.set(overlayWidth, forKey: Key.overlayWidth) } }
    @Published var overlayHeight: Double { didSet { defaults.set(overlayHeight, forKey: Key.overlayHeight) } }
    @Published var captionDisplayMode: CaptionDisplayMode {
        didSet { defaults.set(captionDisplayMode.rawValue, forKey: Key.captionDisplayMode) }
    }
    @Published var historySummaryLevel: HistorySummaryLevel {
        didSet { defaults.set(historySummaryLevel.rawValue, forKey: Key.historySummaryLevel) }
    }
    @Published var appLanguage: AppLanguage { didSet { defaults.set(appLanguage.rawValue, forKey: Key.appLanguage) } }
    @Published var sourceLanguage: CaptionLanguage {
        didSet { defaults.set(sourceLanguage.rawValue, forKey: Key.sourceLanguage) }
    }
    @Published var targetLanguage: CaptionLanguage {
        didSet { defaults.set(targetLanguage.rawValue, forKey: Key.targetLanguage) }
    }
    @Published var sourceChineseScript: ChineseScript {
        didSet { defaults.set(sourceChineseScript.rawValue, forKey: Key.sourceChineseScript) }
    }
    @Published var targetChineseScript: ChineseScript {
        didSet { defaults.set(targetChineseScript.rawValue, forKey: Key.targetChineseScript) }
    }
    @Published var localeIdentifier: String { didSet { defaults.set(localeIdentifier, forKey: Key.localeIdentifier) } }
    @Published var translationModelPreference: TranslationModelPreference {
        didSet { defaults.set(translationModelPreference.rawValue, forKey: Key.translationModelPreference) }
    }
    @Published var automaticallySpeakTranslations: Bool {
        didSet { defaults.set(automaticallySpeakTranslations, forKey: Key.automaticallySpeakTranslations) }
    }
    @Published var translationVoiceIdentifier: String {
        didSet {
            defaults.set(translationVoiceIdentifier, forKey: Key.translationVoiceIdentifier)
            if !resolvingTranslationVoice, !translationVoiceIdentifier.isEmpty {
                translationVoicePreferences[targetSelection.speechSynthesisLocaleIdentifier] = translationVoiceIdentifier
                defaults.set(translationVoicePreferences, forKey: Key.translationVoicePreferences)
            }
        }
    }
    @Published var selectedAudioSourceID: String {
        didSet { defaults.set(selectedAudioSourceID, forKey: Key.selectedAudioSourceID) }
    }
    @Published var vocabulary: [String] { didSet { defaults.set(vocabulary, forKey: Key.vocabulary) } }
    @Published private(set) var translationTermDrafts: [String: TranslationTermDraft] {
        didSet {
            if let data = try? JSONEncoder().encode(translationTermDrafts) {
                defaults.set(data, forKey: Key.translationTermDrafts)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let supportedVoiceLocales = Set(CaptionLanguage.allCases.flatMap { language in
            ChineseScript.allCases.map {
                CaptionLanguageSelection(language: language, chineseScript: $0).speechSynthesisLocaleIdentifier
            }
        })
        translationVoicePreferences = (defaults.dictionary(forKey: Key.translationVoicePreferences) as? [String: String] ?? [:])
            .filter { supportedVoiceLocales.contains($0.key) && !$0.value.isEmpty }
        englishFontSize = defaults.object(forKey: Key.englishFontSize) as? Double ?? 22
        chineseFontSize = defaults.object(forKey: Key.chineseFontSize) as? Double ?? 26
        englishColorHex = defaults.string(forKey: Key.englishColor) ?? "FFFFFF"
        chineseColorHex = defaults.string(forKey: Key.chineseColor) ?? "FFE58F"
        backgroundColorHex = defaults.string(forKey: Key.backgroundColor) ?? "111318"
        glassAppearance = OverlayGlassAppearance(
            rawValue: defaults.string(forKey: Key.glassAppearance) ?? ""
        ) ?? .dark
        overlayWidth = Self.clamp(
            defaults.object(forKey: Key.overlayWidth) as? Double ?? Self.defaultOverlayWidth,
            to: Self.overlayWidthRange
        )
        overlayHeight = Self.clamp(
            defaults.object(forKey: Key.overlayHeight) as? Double ?? Self.defaultOverlayHeight,
            to: Self.overlayHeightRange
        )
        captionDisplayMode = CaptionDisplayMode(
            rawValue: defaults.string(forKey: Key.captionDisplayMode) ?? ""
        ) ?? .transcriptionAndTranslation
        historySummaryLevel = HistorySummaryLevel(rawValue: defaults.string(forKey: Key.historySummaryLevel) ?? "") ?? .standard
        appLanguage = AppLanguage(rawValue: defaults.string(forKey: Key.appLanguage) ?? "") ?? .english
        let loadedSourceLanguage = CaptionLanguage(
            rawValue: defaults.string(forKey: Key.sourceLanguage) ?? ""
        ) ?? .english
        var loadedTargetLanguage = CaptionLanguage(
            rawValue: defaults.string(forKey: Key.targetLanguage) ?? ""
        ) ?? .chinese
        let loadedSourceChineseScript = ChineseScript(
            rawValue: defaults.string(forKey: Key.sourceChineseScript) ?? ""
        ) ?? .simplified
        let loadedTargetChineseScript = ChineseScript(
            rawValue: defaults.string(forKey: Key.targetChineseScript) ?? ""
        ) ?? .simplified
        if loadedSourceLanguage == loadedTargetLanguage {
            loadedTargetLanguage = loadedSourceLanguage == .english ? .chinese : .english
        }
        let savedLocale = defaults.string(forKey: Key.localeIdentifier)
        let availableLocales = loadedSourceLanguage.speechVariants(chineseScript: loadedSourceChineseScript)
        let loadedLocaleIdentifier = savedLocale.flatMap { saved in
            availableLocales.contains(where: { $0.localeIdentifier == saved }) ? saved : nil
        } ?? availableLocales[0].localeIdentifier
        sourceLanguage = loadedSourceLanguage
        targetLanguage = loadedTargetLanguage
        sourceChineseScript = loadedSourceChineseScript
        targetChineseScript = loadedTargetChineseScript
        localeIdentifier = loadedLocaleIdentifier
        let savedTranslationMode = defaults.string(forKey: Key.translationModelPreference)
        translationModelPreference = savedTranslationMode == "highQuality" ? .contextual
            : (TranslationModelPreference(rawValue: savedTranslationMode ?? "") ?? .lowLatency)
        if savedTranslationMode == "highQuality" {
            defaults.set(TranslationModelPreference.contextual.rawValue, forKey: Key.translationModelPreference)
        }
        automaticallySpeakTranslations = defaults.object(
            forKey: Key.automaticallySpeakTranslations
        ) as? Bool ?? false
        translationVoiceIdentifier = defaults.string(forKey: Key.translationVoiceIdentifier) ?? ""
        selectedAudioSourceID = defaults.string(forKey: Key.selectedAudioSourceID)
            ?? AudioSource.allSystemAudio.id
        if let data = defaults.data(forKey: Key.translationTermDrafts),
           data.count <= 128_000_000,
           let drafts = try? JSONDecoder().decode([String: TranslationTermDraft].self, from: data) {
            translationTermDrafts = Dictionary(uniqueKeysWithValues: drafts.sorted { $0.key < $1.key }
                .prefix(100).map { ($0.key, $0.value.bounded) })
        } else {
            translationTermDrafts = [:]
        }
        let storedVocabulary = defaults.stringArray(forKey: Key.vocabulary)
        if let storedVocabulary,
           storedVocabulary.count == Self.legacyVocabularyCount,
           Self.vocabularyFingerprint(storedVocabulary) == Self.legacyVocabularyFingerprint {
            vocabulary = Self.defaultVocabulary
            defaults.set(Self.defaultVocabulary, forKey: Key.vocabulary)
        } else {
            vocabulary = storedVocabulary ?? Self.defaultVocabulary
        }
        if defaults.object(forKey: Key.translationVoicePreferences) == nil {
            if !translationVoiceIdentifier.isEmpty {
                translationVoicePreferences[targetSelection.speechSynthesisLocaleIdentifier] = translationVoiceIdentifier
            }
            defaults.set(translationVoicePreferences, forKey: Key.translationVoicePreferences)
        }
    }

    var preferredTranslationVoiceIdentifier: String? {
        translationVoicePreferences[targetSelection.speechSynthesisLocaleIdentifier]
    }

    /// Automatic fallback changes the effective voice, never the user's preference.
    /// The preference can therefore recover after a voice is installed again.
    func resolveTranslationVoice(availableIdentifiers: [String]) {
        let preferred = preferredTranslationVoiceIdentifier
        let resolved = preferred.flatMap { availableIdentifiers.contains($0) ? $0 : nil }
            ?? availableIdentifiers.first ?? ""
        resolvingTranslationVoice = true
        defer { resolvingTranslationVoice = false }
        if translationVoiceIdentifier != resolved { translationVoiceIdentifier = resolved }
    }

    var englishColor: Color { Color(hex: englishColorHex) }
    var chineseColor: Color { Color(hex: chineseColorHex) }
    var backgroundColor: Color { Color(hex: backgroundColorHex) }
    var sourceSelection: CaptionLanguageSelection {
        CaptionLanguageSelection(language: sourceLanguage, chineseScript: sourceChineseScript)
    }
    var targetSelection: CaptionLanguageSelection {
        CaptionLanguageSelection(language: targetLanguage, chineseScript: targetChineseScript)
    }
    var availableSpeechVariants: [SpeechVariant] {
        sourceLanguage.speechVariants(chineseScript: sourceChineseScript)
    }

    var terminologyPairID: String {
        sourceSelection.terminologyIdentifier + ">" + targetSelection.terminologyIdentifier
    }

    var currentTermDraft: TranslationTermDraft {
        translationTermDrafts[terminologyPairID] ?? TranslationTermDraft()
    }

    func updateCurrentTermDraft(_ draft: TranslationTermDraft) {
        let draft = draft.bounded
        if draft.keptTerms.isEmpty && draft.fixedTranslations.isEmpty {
            translationTermDrafts.removeValue(forKey: terminologyPairID)
        } else {
            translationTermDrafts[terminologyPairID] = draft
        }
    }

    private static func vocabularyFingerprint(_ vocabulary: [String]) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in vocabulary.joined(separator: "\n").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }

    func setSourceLanguage(_ language: CaptionLanguage) {
        let previousSource = sourceLanguage
        sourceLanguage = language
        if targetLanguage == language {
            targetLanguage = previousSource
        }
        resetSpeechVariantIfNeeded(forceDefault: true)
    }

    func setTargetLanguage(_ language: CaptionLanguage) {
        guard language != sourceLanguage else { return }
        targetLanguage = language
    }

    func setSourceChineseScript(_ script: ChineseScript) {
        sourceChineseScript = script
        resetSpeechVariantIfNeeded(forceDefault: true)
    }

    func setTargetChineseScript(_ script: ChineseScript) {
        targetChineseScript = script
    }

    func swapLanguages() {
        let oldSource = sourceLanguage
        let oldTarget = targetLanguage
        let oldSourceScript = sourceChineseScript
        let oldTargetScript = targetChineseScript
        sourceLanguage = oldTarget
        targetLanguage = oldSource
        sourceChineseScript = oldTargetScript
        targetChineseScript = oldSourceScript
        resetSpeechVariantIfNeeded(forceDefault: true)
    }

    func savedOrigin() -> CGPoint? {
        guard defaults.object(forKey: Key.overlayX) != nil,
              defaults.object(forKey: Key.overlayY) != nil else { return nil }
        return CGPoint(x: defaults.double(forKey: Key.overlayX), y: defaults.double(forKey: Key.overlayY))
    }

    func saveOrigin(_ origin: CGPoint) {
        defaults.set(origin.x, forKey: Key.overlayX)
        defaults.set(origin.y, forKey: Key.overlayY)
    }

    private func resetSpeechVariantIfNeeded(forceDefault: Bool) {
        let variants = availableSpeechVariants
        guard let first = variants.first else { return }
        if forceDefault || !variants.contains(where: { $0.localeIdentifier == localeIdentifier }) {
            localeIdentifier = first.localeIdentifier
        }
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(cleaned, radix: 16) ?? 0xFFFFFF
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

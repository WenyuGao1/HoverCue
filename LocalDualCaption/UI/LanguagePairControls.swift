import SwiftUI

struct LanguagePairControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings

    var body: some View {
        Picker("Source language", selection: sourceLanguageBinding) {
            ForEach(CaptionLanguage.allCases) { language in
                Text(language.displayName(in: settings.appLanguage)).tag(language)
            }
        }
        .disabled(model.controlsLocked)

        if settings.sourceLanguage == .chinese {
            LabeledContent("Source Chinese script") {
                Picker("Source Chinese script", selection: sourceScriptBinding) {
                    ForEach(ChineseScript.allCases) { script in
                        Text(LocalizedStringKey(script.localizationKey)).tag(script)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .disabled(model.controlsLocked)
        }

        Picker("Speech variety", selection: localeBinding) {
            ForEach(settings.availableSpeechVariants) { variant in
                Text(variant.displayName(in: settings.appLanguage)).tag(variant.localeIdentifier)
            }
        }
        .disabled(model.controlsLocked)

        Picker("Target language", selection: targetLanguageBinding) {
            ForEach(CaptionLanguage.allCases.filter { $0 != settings.sourceLanguage }) { language in
                Text(language.displayName(in: settings.appLanguage)).tag(language)
            }
        }
        .disabled(model.controlsLocked)

        if settings.targetLanguage == .chinese {
            LabeledContent("Target Chinese script") {
                Picker("Target Chinese script", selection: targetScriptBinding) {
                    ForEach(ChineseScript.allCases) { script in
                        Text(LocalizedStringKey(script.localizationKey)).tag(script)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .disabled(model.controlsLocked)
        }

        LabeledContent {
            Button("Swap languages", systemImage: "arrow.up.arrow.down") {
                settings.swapLanguages()
                refreshModelStates()
            }
        } label: {
            EmptyView()
        }
        .disabled(model.controlsLocked)
    }

    private var sourceLanguageBinding: Binding<CaptionLanguage> {
        Binding(
            get: { settings.sourceLanguage },
            set: { language in
                settings.setSourceLanguage(language)
                refreshModelStates()
            }
        )
    }

    private var targetLanguageBinding: Binding<CaptionLanguage> {
        Binding(
            get: { settings.targetLanguage },
            set: { language in
                settings.setTargetLanguage(language)
                refreshModelStates()
            }
        )
    }

    private var sourceScriptBinding: Binding<ChineseScript> {
        Binding(
            get: { settings.sourceChineseScript },
            set: { script in
                settings.setSourceChineseScript(script)
                refreshModelStates()
            }
        )
    }

    private var targetScriptBinding: Binding<ChineseScript> {
        Binding(
            get: { settings.targetChineseScript },
            set: { script in
                settings.setTargetChineseScript(script)
                refreshModelStates()
            }
        )
    }

    private var localeBinding: Binding<String> {
        Binding(
            get: { settings.localeIdentifier },
            set: { identifier in
                settings.localeIdentifier = identifier
                refreshModelStates()
            }
        )
    }

    private func refreshModelStates() {
        Task { await model.refreshSelectedModelStates() }
    }
}

struct CaptionLanguagePairControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                sourcePicker
                swapButton
                targetPicker
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 10) {
                sourcePicker
                swapButton
                targetPicker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(model.controlsLocked)
    }

    private var sourcePicker: some View {
        Picker("Source language", selection: sourceSelectionBinding) {
            ForEach(allLanguageOptions) { option in
                Text(option.displayName(in: settings.appLanguage)).tag(option.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var swapButton: some View {
        Button {
            settings.swapLanguages()
            refreshModelStates()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
        }
        .accessibilityLabel("Swap languages")
        .help("Swap languages")
    }

    private var targetPicker: some View {
        Picker("Target language", selection: targetSelectionBinding) {
            ForEach(targetLanguageOptions) { option in
                Text(option.displayName(in: settings.appLanguage)).tag(option.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var allLanguageOptions: [CaptionLanguageOption] {
        CaptionLanguage.allCases.flatMap { language in
            if language == .chinese {
                return ChineseScript.allCases.map {
                    CaptionLanguageOption(language: language, chineseScript: $0)
                }
            }
            return [CaptionLanguageOption(language: language, chineseScript: .simplified)]
        }
    }

    private var targetLanguageOptions: [CaptionLanguageOption] {
        allLanguageOptions.filter { $0.language != settings.sourceLanguage }
    }

    private var sourceSelectionBinding: Binding<String> {
        Binding(
            get: {
                CaptionLanguageOption.id(
                    language: settings.sourceLanguage,
                    chineseScript: settings.sourceChineseScript
                )
            },
            set: { identifier in
                guard let option = allLanguageOptions.first(where: { $0.id == identifier }) else {
                    return
                }
                settings.setSourceLanguage(option.language)
                if option.language == .chinese {
                    settings.setSourceChineseScript(option.chineseScript)
                }
                refreshModelStates()
            }
        )
    }

    private var targetSelectionBinding: Binding<String> {
        Binding(
            get: {
                CaptionLanguageOption.id(
                    language: settings.targetLanguage,
                    chineseScript: settings.targetChineseScript
                )
            },
            set: { identifier in
                guard let option = targetLanguageOptions.first(where: { $0.id == identifier }) else {
                    return
                }
                settings.setTargetLanguage(option.language)
                if option.language == .chinese {
                    settings.setTargetChineseScript(option.chineseScript)
                }
                refreshModelStates()
            }
        )
    }

    private func refreshModelStates() {
        Task { await model.refreshSelectedModelStates() }
    }
}

struct CaptionSpeechRegionPicker: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings

    var body: some View {
        Picker("Speech region", selection: localeBinding) {
            ForEach(settings.availableSpeechVariants) { variant in
                Text(variant.displayName(in: settings.appLanguage))
                    .tag(variant.localeIdentifier)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(model.controlsLocked)
    }

    private var localeBinding: Binding<String> {
        Binding(
            get: { settings.localeIdentifier },
            set: { identifier in
                settings.localeIdentifier = identifier
                Task { await model.refreshSelectedModelStates() }
            }
        )
    }
}

private struct CaptionLanguageOption: Identifiable {
    let language: CaptionLanguage
    let chineseScript: ChineseScript

    var id: String {
        Self.id(language: language, chineseScript: chineseScript)
    }

    static func id(language: CaptionLanguage, chineseScript: ChineseScript) -> String {
        language == .chinese
            ? "\(language.rawValue)-\(chineseScript.rawValue)"
            : language.rawValue
    }

    func displayName(in appLanguage: AppLanguage) -> String {
        let languageName = language.displayName(in: appLanguage)
        guard language == .chinese else { return languageName }
        return "\(languageName) (\(appLanguage.localized(chineseScript.localizationKey)))"
    }
}

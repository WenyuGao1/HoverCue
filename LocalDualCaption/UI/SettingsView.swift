import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings
    var page: ControlPage = .settings
    var onOpenSettings: (() -> Void)? = nil
    @State private var privacyPolicyPresented = false

    var body: some View {
        ControlPageScrollView(model: model, settings: settings, page: page, onOpenSettings: onOpenSettings) {
            switch page {
            case .appearance:
                appearanceSection
            case .voice:
                readingSection
            case .vocabulary:
                vocabularySection
            case .history, .captions, .settings:
                generalSection
                recognitionSection
                permissionsSection
            }
        }
        .controlSize(.regular)
        .task {
            if page == .settings { await refreshSettingsStatus() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { if page == .settings { await refreshSettingsStatus() } }
        }
        .onChange(of: settings.translationModelPreference) { _, _ in
            Task { await model.refreshTranslationModelState() }
        }
        .sheet(isPresented: $privacyPolicyPresented) {
            PrivacyPolicyView()
                .environment(\.locale, settings.appLanguage.locale)
        }
        .environment(\.locale, settings.appLanguage.locale)
    }

    private var generalSection: some View {
        InterfaceSettingsSection {
            LabeledContent("App language") {
                Picker("App language", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName(in: settings.appLanguage)).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 280, alignment: .trailing)
            }
            MenuThemePicker()
            Button {
                privacyPolicyPresented = true
            } label: {
                HStack {
                    Label("Privacy Policy", systemImage: "hand.raised")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            HStack {
                InterfaceSectionTitle(title: "General", symbol: "gearshape")
                Spacer(minLength: 12)
                InterfaceHelpButton(title: "General", identifier: "help.general") {
                    Text("Applies to menus and controls. Caption colors stay unchanged.")
                    Text("Audio, recognition, and translation stay on this Mac. Text history is off by default and can be saved and exported only when you enable it.")
                }
            }
        }
    }

    private var recognitionSection: some View {
        InterfaceSettingsSection {
            if #available(macOS 26.4, *) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Translation model")
                    TranslationModelPicker(selection: $settings.translationModelPreference)
                        .disabled(model.controlsLocked)
                    Text(LocalizedStringKey(settings.translationModelPreference.descriptionKey))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("translation.modeDescription")
                    if settings.translationModelPreference == .contextual, !model.running,
                       let message = ContextualModelAvailability.current(source: settings.sourceSelection,
                                                                       target: settings.targetSelection).messageKey {
                        Label(LocalizedStringKey(message), systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                LabeledContent("Translation model", value: "Low latency")
            }
        } header: {
            HStack {
                InterfaceSectionTitle(title: "Recognition and translation", symbol: "character.bubble")
                Spacer(minLength: 12)
                InterfaceHelpButton(title: "Translation model", identifier: "help.translationModel") {
                    Text("Model changes apply when captions next start.")
                    Text("Contextual enhancement uses Apple Intelligence on this Mac to translate each sentence with up to four recent source sentences. It may be slower; system translation is used if it is unavailable, times out, or falls behind.")
                    Text("Context is held only in bounded memory and cleared when captions stop. It does not enable history or save audio. Only the final translation is displayed, read aloud, and saved when history is enabled.")
                }
            }
        }
    }

    private var readingSection: some View {
        InterfaceSettingsSection {
            TranslationPlaybackControls(model: model, settings: settings)
                .padding(.vertical, 4)
        } header: {
            HStack {
                InterfaceSectionTitle(title: "Reading and voice", symbol: "speaker.wave.2")
                Spacer(minLength: 12)
                InterfaceHelpButton(title: "Reading and voice", identifier: "help.playback") {
                    Text("Reads every stable translation in order and gradually speeds up when playback falls behind.")
                    Text("Each timbre uses its highest-quality installed version for the target language.")
                    Text("Complete reading never silently skips queued translations. Playback may remain behind the original audio.")
                    Text("Bluetooth or wired headphones are recommended when using microphone input and automatic reading.")
                }
            }
        }
    }

    private var appearanceSection: some View {
        InterfaceSettingsSection {
            GlassAppearancePicker(selection: $settings.glassAppearance)
            LabeledContent("Caption display") {
                Picker("Caption display", selection: $settings.captionDisplayMode) {
                    Text("Transcription and translation").tag(CaptionDisplayMode.transcriptionAndTranslation)
                    Text("Transcription only").tag(CaptionDisplayMode.transcriptionOnly)
                    Text("Translation only").tag(CaptionDisplayMode.translationOnly)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 340, alignment: .trailing)
            }
            LabeledContent("Original caption font size") {
                Slider(value: $settings.englishFontSize, in: 14...42)
                    .accessibilityLabel("Original caption font size")
                measurement(settings.englishFontSize)
            }
            LabeledContent("Translated caption font size") {
                Slider(value: $settings.chineseFontSize, in: 16...48)
                    .accessibilityLabel("Translated caption font size")
                measurement(settings.chineseFontSize)
            }
            ColorPicker("Original caption color", selection: colorBinding(hex: $settings.englishColorHex), supportsOpacity: false)
            ColorPicker("Translated caption color", selection: colorBinding(hex: $settings.chineseColorHex), supportsOpacity: false)
            LabeledContent("Window width") {
                Slider(value: $settings.overlayWidth, in: OverlaySettings.overlayWidthRange)
                    .accessibilityLabel("Window width")
                measurement(settings.overlayWidth)
            }
            LabeledContent("Window height") {
                Slider(value: $settings.overlayHeight, in: OverlaySettings.overlayHeightRange)
                    .accessibilityLabel("Window height")
                measurement(settings.overlayHeight)
            }
            Button("Move to Current Screen", systemImage: "rectangle.on.rectangle") {
                model.moveOverlayToCurrentScreen()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Overlay Preview")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                CaptionInterfacePreview(model: model, settings: settings)
            }
            .padding(.vertical, 8)
        } header: {
            InterfaceSectionTitle(title: "Overlay appearance", symbol: "captions.bubble")
        }
    }

    private var vocabularySection: some View {
        TranslationTerminologyView(model: model, settings: settings)
    }

    private var permissionsSection: some View {
        InterfaceSettingsSection {
            Text("Permissions").font(.subheadline.weight(.semibold))
            PermissionsView(model: model)
            Text("Offline models").font(.subheadline.weight(.semibold))
            OfflineModelsView(model: model, settings: settings)
        } header: {
            HStack {
                InterfaceSectionTitle(title: "Permissions and offline models", symbol: "lock.shield")
                Spacer(minLength: 12)
                InterfaceHelpButton(title: "Permissions and offline models", identifier: "help.permissions") {
                    Text("macOS groups system-audio access under “Screen & System Audio Recording”. HoverCue registers audio only.")
                    Text("Microphone access is requested only after you select a microphone source or explicitly allow it.")
                    Text("If macOS asks you to restart after a permission change, quit and reopen HoverCue.")
                    Text("Model downloads are managed by macOS and may require internet the first time. HoverCue itself has no network-client permission.")
                }
            }
        }
    }

    private func measurement(_ value: Double) -> some View {
        Text("\(Int(value)) pt")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 60, alignment: .trailing)
    }

    private func colorBinding(hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: hex.wrappedValue) },
            set: { color in
                guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return }
                hex.wrappedValue = String(
                    format: "%02X%02X%02X",
                    Int(converted.redComponent * 255),
                    Int(converted.greenComponent * 255),
                    Int(converted.blueComponent * 255)
                )
            }
        )
    }

    private func refreshSettingsStatus() async {
        guard !model.modelPreparationActive else { return }
        await model.refreshEnvironment()
    }
}

struct TranslationModelPicker: View {
    @Binding var selection: TranslationModelPreference

    var body: some View {
        ViewThatFits(in: .horizontal) {
            picker.pickerStyle(.segmented).fixedSize(horizontal: true, vertical: false)
            picker.pickerStyle(.menu).frame(maxWidth: 360, alignment: .leading)
        }
        .accessibilityIdentifier("translation.mode")
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var picker: some View {
        Picker("Translation model", selection: $selection) {
            ForEach(TranslationModelPreference.allCases) { mode in
                Text(LocalizedStringKey(mode.titleKey)).tag(mode)
            }
        }
        .labelsHidden()
    }
}

struct GlassAppearancePicker: View {
    @Binding var selection: OverlayGlassAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Glass appearance")
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                // Native segments can exceed an imposed width. Measure their
                // full size before choosing the layout for localized titles.
                picker
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                picker
                    .pickerStyle(.menu)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var picker: some View {
        Picker("Glass appearance", selection: $selection) {
            Text("Light").tag(OverlayGlassAppearance.light)
            Text("Dark").tag(OverlayGlassAppearance.dark)
            Text("High Transparency").tag(OverlayGlassAppearance.highTransparency)
        }
        .labelsHidden()
    }
}

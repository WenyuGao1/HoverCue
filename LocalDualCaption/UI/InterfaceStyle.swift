import AppKit
import SwiftUI

/// Styling for the controls window only. Caption-panel appearance is independent.
enum InterfaceStyle {
    static var accent: Color {
        InterfaceTheme.resolved(UserDefaults.standard.string(forKey: InterfaceTheme.storageKey) ?? "system").color
    }
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let contentWidth: CGFloat = 900
}

struct InterfaceCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(InterfaceStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

struct InterfaceSectionTitle: View {
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .labelStyle(.titleAndIcon)
    }
}

struct OnDeviceBadge: View {
    var body: some View {
        Label("On-device only", systemImage: "lock.shield")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.045), in: Capsule())
            .fixedSize()
    }
}

/// Supplemental explanations open on demand; operational notices stay in the page.
struct InterfaceHelpButton<Content: View>: View {
    let title: LocalizedStringKey
    let identifier: String
    private let content: Content
    @Environment(\.locale) private var locale
    @State private var presented = false

    init(title: LocalizedStringKey, identifier: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.identifier = identifier
        self.content = content()
    }

    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 17))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
        .help(title)
        .popover(isPresented: $presented) {
            ViewThatFits(in: .vertical) {
                helpContent
                ScrollView { helpContent }
            }
            .frame(width: 360)
            .frame(maxHeight: 480)
            .padding(20)
            .environment(\.locale, locale)
            .onExitCommand { presented = false }
        }
    }

    private var helpContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct InterfaceNote: View {
    let text: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InterfaceNotice: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
    }
}

struct TranslationPlaybackControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Text("Read Translation Automatically")
                Spacer(minLength: 12)
                Toggle("Read Translation Automatically", isOn: Binding(
                get: { settings.automaticallySpeakTranslations },
                set: { enabled in
                    // Preserve voice validation and immediate playback cleanup.
                    if enabled != settings.automaticallySpeakTranslations {
                        model.toggleAutomaticTranslationSpeech()
                    }
                }
            ))
                .labelsHidden()
                .toggleStyle(.switch)
                .help("Reads every stable translation in order and gradually speeds up when playback falls behind.")
            }

            HStack(spacing: 16) {
                Text("Playback voice")
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                if model.translationVoiceOptions.isEmpty {
                    Text("No installed voice")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Playback voice", selection: $settings.translationVoiceIdentifier) {
                        ForEach(model.translationVoiceOptions) { option in
                            Text(verbatim: option.displayName(in: settings.appLanguage))
                                .tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 360, alignment: .trailing)
                    .disabled(model.controlsLocked)
                    .help("Each timbre uses its highest-quality installed version for the target language.")
                }
            }
            if model.usingFallbackTranslationVoice {
                InterfaceNote(text: "Your preferred voice is unavailable. Another installed voice is being used.",
                              symbol: "info.circle")
            }
        }
    }
}

struct InterfacePageIntroduction: View {
    let page: ControlPage

    var body: some View {
        Text(page.subtitle)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Scrollable settings groups share the same sizing behavior as the captions page.
struct InterfaceSettingsSection<Content: View, Header: View, Footer: View>: View {
    private let content: Content
    private let header: Header
    private let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header,
         @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            InterfaceCard {
                VStack(alignment: .leading, spacing: 20) { content }
            }
            footer
        }
    }
}

extension InterfaceSettingsSection where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
}

import SwiftUI

/// Main-window accent only; never changes caption-panel settings.
enum InterfaceTheme: String, CaseIterable, Identifiable {
    static let storageKey = "interface.menuTheme"

    case system, blue, purple, red, lightPink, orange, yellow, green, graphite

    var id: String { rawValue }

    static func resolved(_ value: String) -> Self {
        // Preserve older selections when consolidating the similar red shades.
        if value == "pink" { return .red }
        return Self(rawValue: value) ?? .system
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Follow System"
        case .blue: "Blue"
        case .purple: "Purple"
        case .red: "Red"
        case .lightPink: "Light Pink"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .graphite: "Graphite"
        }
    }

    var color: Color {
        switch self {
        case .system: Color(nsColor: .controlAccentColor)
        case .blue: .blue
        case .purple: .purple
        case .red: .red
        case .lightPink: Color(red: 244.0 / 255, green: 174.0 / 255, blue: 205.0 / 255)
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .graphite: .gray
        }
    }
}

enum ControlPage: String, CaseIterable, Identifiable {
    case captions, appearance, voice, vocabulary, history, settings

    var id: String { rawValue }

    var title: LocalizedStringKey { LocalizedStringKey(titleKey) }

    var titleKey: String {
        switch self {
        case .captions: "Live captions"
        case .appearance: "Caption appearance"
        case .voice: "Reading and voice"
        case .vocabulary: "Terminology"
        case .history: "Translation history"
        case .settings: "Settings"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .captions: "Choose your audio and languages, then start captions."
        case .appearance: "Adjust the look of your floating captions."
        case .voice: "Choose how translated captions are read aloud."
        case .vocabulary: "Keep terms unchanged or choose their translations."
        case .history: "Review, export, or delete text saved with permission."
        case .settings: "Personalize HoverCue and manage on-device resources."
        }
    }

    var symbol: String {
        switch self {
        case .captions: "captions.bubble"
        case .appearance: "rectangle.on.rectangle"
        case .voice: "speaker.wave.2"
        case .vocabulary: "text.book.closed"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

struct MenuThemePicker: View {
    @AppStorage(InterfaceTheme.storageKey) private var themeValue = InterfaceTheme.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Menu theme color")
                Spacer()
                Text(InterfaceTheme.resolved(themeValue).title)
                    .foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { choices }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 38))], alignment: .leading, spacing: 12) {
                    choices
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var choices: some View {
        // Capture the value so nested layouts can detect a changed selection
        // instead of reusing labels that only capture the AppStorage wrapper.
        let selectedTheme = InterfaceTheme.resolved(themeValue)
        return ForEach(InterfaceTheme.allCases) { theme in
            Button {
                themeValue = theme.rawValue
            } label: {
                ZStack {
                    if theme == .system {
                        Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
                    } else {
                        Circle().fill(theme.color.gradient)
                    }
                    if selectedTheme == theme {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(theme == .yellow || theme == .lightPink ? .black : .white)
                            .shadow(color: .black.opacity(0.25), radius: 2)
                    }
                }
                .frame(width: 26, height: 26)
                .padding(5)
                .overlay(Circle().strokeBorder(selectedTheme == theme ? Color.primary.opacity(0.45) : .clear, lineWidth: 1.5))
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(theme.title)
            .accessibilityAddTraits(selectedTheme == theme ? .isSelected : [])
            .help(theme.title)
        }
    }
}

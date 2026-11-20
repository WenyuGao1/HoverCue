import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    policySection(
                        icon: "memorychip",
                        title: "On-device processing",
                        text: "HoverCue processes audio, recognition, translation, and optional spoken translation on this Mac. Audio is never saved or uploaded."
                    )
                    policySection(
                        icon: "speaker.wave.2.fill",
                        title: "User-selected audio source",
                        text: "HoverCue processes system audio or a selected microphone only when you select that source. It does not capture screen pixels, screenshots, or video."
                    )
                    policySection(
                        icon: "tray",
                        title: "Optional local text history",
                        text: "Text history is off at every app launch. After you confirm everyone is informed and agrees, new stable original text and translations can be saved locally and exported manually. You can delete saved history at any time."
                    )
                    policySection(
                        icon: "sparkles",
                        title: "AI summary",
                        text: "When history is enabled, titles and bilingual summaries are created automatically on this Mac after captions stop, when Apple Intelligence is available."
                    )
                    policySection(
                        icon: "person.crop.circle.badge.xmark",
                        title: "No accounts or tracking",
                        text: "HoverCue has no accounts, analytics, advertising, or tracking."
                    )
                    policySection(
                        icon: "internaldrive",
                        title: "Settings stored locally",
                        text: "App settings and terminology are saved in UserDefaults. Optional text history is stored separately in the app's local container, excluded from automatic backup. Exports go only to the location you choose; synced folders may sync them."
                    )
                    policySection(
                        icon: "character.book.closed",
                        title: "Apple-managed language resources",
                        text: "Speech and translation resources are managed by Apple and may be downloaded by macOS on demand. HoverCue has no network-client permission."
                    )
                }
                .padding(20)
            }
            .navigationTitle("Privacy Policy")
            .background(InterfaceStyle.background)
            .tint(InterfaceStyle.accent)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 540, idealWidth: 600, minHeight: 520, idealHeight: 600)
    }

    private func policySection(icon: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                    .foregroundStyle(InterfaceStyle.accent)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(InterfaceStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

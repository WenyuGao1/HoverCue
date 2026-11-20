import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Private by design", systemImage: "lock.shield.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.green)
                    Text("Audio, recognition, and translation stay on this Mac. Text history is off by default and can be saved and exported only when you enable it.")
                        .font(.body)
                    Text("No screen images are captured.")
                        .font(.body)
                    Text("macOS groups system-audio access under “Screen & System Audio Recording”. HoverCue registers audio only.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Microphone access is requested only after you select a microphone source or explicitly allow it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("On-device only")
                        .font(.headline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.green.opacity(0.15), in: Capsule())
                }

                GroupBox("Permissions and offline models") {
                    PermissionsView(model: model)
                        .padding(8)
                }

                HStack {
                    Button("Prepare offline models") {
                        model.prepareOfflineModels()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.controlsLocked)
                    Button("Refresh status") {
                        Task { await model.refreshEnvironment() }
                    }
                }

                GroupBox("Offline test") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model downloads are managed by macOS and may require internet the first time. HoverCue itself has no network-client permission.")
                        Text("After both selected models show “installed”, quit and reopen the app if macOS asks, turn off Wi‑Fi, play a video in the selected source language, select that application, and start captions.")
                        Text("Live captions and translations may contain errors. For important content, verify against the original audio.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                if let notice = model.notice {
                    InterfaceNotice(text: model.settings.appLanguage.localizedMessage(notice))
                }
            }
            .padding(24)
        }
        .background(InterfaceStyle.background)
        .tint(InterfaceStyle.accent)
        .environment(\.locale, model.settings.appLanguage.locale)
    }
}

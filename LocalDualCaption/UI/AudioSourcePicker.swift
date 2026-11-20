import SwiftUI

struct AudioSourcePicker: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: OverlaySettings

    init(model: AppModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Section("Microphones") {
                    ForEach(model.audioSources.filter(\.isMicrophone)) { source in
                        sourceItem(source)
                    }
                }
                Section("System Audio") {
                    ForEach(model.audioSources.filter { !$0.isMicrophone && !$0.isAuxiliary }) { source in
                        sourceItem(source)
                    }
                }
                if model.audioSources.contains(where: \.isAuxiliary) {
                    Menu("Other audio sources") {
                        ForEach(model.audioSources.filter(\.isAuxiliary)) { source in sourceItem(source) }
                    }
                }
            } label: {
                Text(verbatim: selectedTitle)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderedButton)
            .accessibilityLabel("Audio source")
            .accessibilityValue(Text(verbatim: selectedTitle))
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(model.controlsLocked)

            Button {
                Task { await model.refreshAudioSources() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh audio sources")
            .accessibilityLabel("Refresh audio sources")
        }
    }

    private var selectedTitle: String {
        guard let source = model.audioSources.first(where: { $0.id == model.selectedSourceID }) else {
            return settings.appLanguage.localized("Selected Application (Unavailable)")
        }
        return title(for: source)
    }

    private func title(for source: AudioSource) -> String {
        if source.isSystemDefaultMicrophone { return settings.appLanguage.localized("System Default Microphone") }
        if source.id == AudioSource.allSystemAudio.id { return settings.appLanguage.localized("All System Audio") }
        if !source.isAvailable {
            if source.isMicrophone { return settings.appLanguage.localized("Selected Microphone (Unavailable)") }
            if source.title == "Selected Application" {
                return settings.appLanguage.localized("Selected Application (Unavailable)")
            }
            return String(format: settings.appLanguage.localized("%@ (Unavailable)"), source.title)
        }
        return source.title
    }

    private func sourceItem(_ source: AudioSource) -> some View {
        Toggle(isOn: Binding(
            get: { model.selectedSourceID == source.id },
            set: { if $0 { model.selectedSourceID = source.id } }
        )) {
            Text(verbatim: title(for: source))
        }
        .disabled(!source.isAvailable)
    }
}

import SwiftUI

struct PermissionsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PermissionRow(
                title: "Screen & System Audio Recording",
                systemImage: "display",
                state: model.screenPermission,
                request: { Task { await model.requestScreenPermission() } },
                openSettings: model.openScreenPermissionSettings
            )

            Divider()
                .padding(.leading, 34)

            PermissionRow(
                title: "Speech Recognition",
                systemImage: "waveform",
                state: model.speechPermission,
                request: { Task { await model.requestSpeechPermission() } },
                openSettings: model.openSpeechPermissionSettings
            )

            Divider()
                .padding(.leading, 34)

            PermissionRow(
                title: "Microphone",
                systemImage: "mic.fill",
                state: model.microphonePermission,
                request: { Task { await model.requestMicrophonePermission() } },
                openSettings: model.openMicrophonePermissionSettings
            )
        }
    }
}

struct OfflineModelsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings
    @State private var offlineTestExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelStatusRow(
                title: speechModelTitle,
                subtitle: "Speech model",
                systemImage: "waveform",
                state: model.speechModelState,
                activelyPreparing: model.speechModelState == .downloading
            )

            Divider()
                .padding(.leading, 34)

            ModelStatusRow(
                title: translationModelTitle,
                subtitle: "Translation model",
                systemImage: "character.book.closed",
                state: model.translationModelState,
                activelyPreparing: model.translationPreparationActive
            )

            if modelsReady {
                Divider()
                Label("Ready for offline captions", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.vertical, 10)
            } else if shouldShowPreparationButton {
                Divider()
                Button(preparationButtonTitle) {
                    model.prepareOfflineModels()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.controlsLocked)
                .padding(.vertical, 10)
            }

            Divider()

            DisclosureGroup("How to test offline", isExpanded: $offlineTestExpanded) {
                Text("After both selected models show “installed”, quit and reopen the app if macOS asks, turn off Wi‑Fi, play a video in the selected source language, select that application, and start captions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(.vertical, 10)

            if let notice = model.notice {
                Divider()
                InterfaceNotice(text: settings.appLanguage.localizedMessage(notice))
                    .padding(.vertical, 10)
            }
        }
    }

    private var modelsReady: Bool {
        model.speechModelState == .installed
            && model.translationModelState == .installed
            && !model.modelPreparationActive
    }

    private var shouldShowPreparationButton: Bool {
        guard model.speechPermission == .granted,
              !model.modelPreparationActive,
              model.speechModelState != .checking,
              model.translationModelState != .checking,
              model.translationModelState != .unsupported else {
            return false
        }
        return !modelsReady
    }

    private var preparationButtonTitle: LocalizedStringKey {
        if model.speechModelState == .error || model.translationModelState == .error {
            return "Try Again"
        }
        return "Download required models"
    }

    private var speechModelTitle: String {
        settings.availableSpeechVariants
            .first(where: { $0.localeIdentifier == settings.localeIdentifier })?
            .displayName(in: settings.appLanguage)
            ?? settings.localeIdentifier
    }

    private var translationModelTitle: String {
        "\(languageName(settings.sourceLanguage, script: settings.sourceChineseScript)) → "
            + languageName(settings.targetLanguage, script: settings.targetChineseScript)
    }

    private func languageName(_ language: CaptionLanguage, script: ChineseScript) -> String {
        let name = language.displayName(in: settings.appLanguage)
        guard language == .chinese else { return name }
        return "\(name) (\(settings.appLanguage.localized(script.localizationKey)))"
    }
}

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let state: PermissionState
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer(minLength: 16)
            statusControl
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusControl: some View {
        switch state {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
        case .notDetermined:
            Button("Allow", action: request)
        case .denied, .restricted:
            HStack(spacing: 10) {
                Label("Permission Required", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                Button("Open Settings", action: openSettings)
            }
        }
    }
}

private struct ModelStatusRow: View {
    let title: String
    let subtitle: LocalizedStringKey
    let systemImage: String
    let state: ModelState
    let activelyPreparing: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            status
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var status: some View {
        if activelyPreparing || state == .downloading {
            ActivityStatus(title: "Downloading")
        } else {
            switch state {
            case .checking:
                ActivityStatus(title: "Checking")
            case .installed:
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .downloadable:
                Label("Not installed", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            case .unsupported:
                Label("Unsupported", systemImage: "xmark.circle")
                    .foregroundStyle(.secondary)
            case .error:
                Label("Download failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .downloading:
                ActivityStatus(title: "Downloading")
            }
        }
    }
}

private struct ActivityStatus: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 7) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text(title)
        }
        .foregroundStyle(.secondary)
    }
}

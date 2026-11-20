import SwiftUI

struct MainControlView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings

    var onOpenSettings: (() -> Void)? = nil

    var body: some View {
        ControlPageScrollView(model: model, settings: settings, page: .captions, onOpenSettings: onOpenSettings) {

            VStack(alignment: .leading, spacing: 12) {
                InterfaceSectionTitle(title: "Audio and languages", symbol: "waveform")
                InterfaceCard {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                captureLabel("Audio source")
                                Spacer(minLength: 12)
                                InterfaceHelpButton(title: "Audio source", identifier: "help.audioSource") {
                                    Text("Microphone: Picks up speech and surrounding sounds through the selected microphone.")
                                    Text("System audio: Captures sound directly from apps on your Mac, without using the microphone.")
                                    Text("Application filters operate at the application-process level.")
                                    Divider()
                                    Text("⌥⌘C Start/Stop  ·  ⌥⌘O Overlay")
                                }
                            }
                            AudioSourcePicker(model: model)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 10) {
                            captureLabel("Languages")
                            CaptionLanguagePairControls(model: model, settings: settings)
                        }
                        if settings.availableSpeechVariants.count > 1 {
                            VStack(alignment: .leading, spacing: 10) {
                                captureLabel("Speech region")
                                CaptionSpeechRegionPicker(model: model, settings: settings)
                                    .frame(maxWidth: 300, alignment: .leading)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    InterfaceSectionTitle(title: "Overlay Preview", symbol: "rectangle.on.rectangle")
                    Spacer(minLength: 12)
                    InterfaceHelpButton(title: "Overlay Preview", identifier: "help.captionAccuracy") {
                        Text("Live captions and translations may contain errors. For important content, verify against the original audio.")
                    }
                }
                CaptionInterfacePreview(model: model, settings: settings)
                    .accessibilityLabel("Overlay Preview")
            }
        }
    }

    private func captureLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
    }
}

/// Available from every navigation page without creating another caption session.
struct CaptionControlBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings

    @Environment(\.captionFeedbackFixture) private var fixture

    private var feedback: CaptionFeedback {
        fixture ?? CaptionFeedback(status: model.status, notice: model.notice)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HistoryRecordingStatus(history: model.history)
            if let message = model.contextualTranslationStatusKey {
                Label(LocalizedStringKey(message), systemImage: "sparkles")
                    .font(.caption.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("translation.contextualStatus")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    startButton.fixedSize(horizontal: true, vertical: false)
                    statusLabel.frame(width: 140, alignment: .leading)
                    Spacer(minLength: 8)
                    moveButton.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        startButton.fixedSize(horizontal: true, vertical: false)
                        statusLabel.frame(width: 140, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    moveButton
                }
            }
        }
        .frame(maxWidth: InterfaceStyle.contentWidth)
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .padding(.top, 8)
    }

    private var startButton: some View {
        Button {
            Task {
                if model.running {
                    await model.stopCaptions()
                } else {
                    await model.startCaptions()
                }
            }
        } label: {
            Label(model.running ? "Stop Captions" : "Start Captions",
                  systemImage: model.running ? "stop.fill" : "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!model.running && model.controlsLocked)
        .help("⌥⌘C Start/Stop  ·  ⌥⌘O Overlay")
    }

    private var moveButton: some View {
        Button {
            model.moveOverlayToCurrentScreen()
        } label: {
            Text("Move Overlay to Current Screen")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .help("Move Overlay to Current Screen")
        .accessibilityLabel("Move Overlay to Current Screen")
        .buttonStyle(.glass)
        .tint(.secondary)
        .controlSize(.regular)
        .layoutPriority(1)
    }

    private var statusLabel: some View {
        Label(feedback.compactStatus(in: settings.appLanguage), systemImage: statusSymbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(statusColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityLabel(Text(verbatim: settings.appLanguage.localized("Status:") + " " + feedback.status.label(language: settings.appLanguage)))
    }

    private var statusSymbol: String {
        if case .error = feedback.status { return "exclamationmark.circle.fill" }
        return model.running ? "waveform" : "circle.dotted"
    }

    private var statusColor: Color {
        if case .error = feedback.status { return .red }
        return model.running ? .green : .secondary
    }

}

/// Uses the original preview content and caption metrics without changing the overlay.
struct CaptionInterfacePreview: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            OverlayGlassPreviewSurface(
                appearance: settings.glassAppearance,
                cornerRadius: OverlayGlassMetrics.overlayCornerRadius
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(
                alignment: .leading,
                spacing: OverlayGlassMetrics.captionPairSpacing
            ) {
                if settings.captionDisplayMode.showsTranscription {
                    CaptionText(
                        text: Text(previewSourceText),
                        font: .system(
                            size: settings.englishFontSize,
                            weight: .medium
                        ),
                        foregroundColor: settings.englishColor
                    )
                }
                if settings.captionDisplayMode.showsTranslation {
                    CaptionText(
                        text: Text(previewTranslationText),
                        font: .system(
                            size: settings.chineseFontSize,
                            weight: .semibold
                        ),
                        foregroundColor: settings.chineseColor
                    )
                }
            }
            .padding(
                .horizontal,
                OverlayGlassMetrics.captionHorizontalPadding
            )
            .padding(
                .vertical,
                OverlayGlassMetrics.captionVerticalPadding
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottomLeading
            )
            .padding(OverlayGlassMetrics.captionOuterPadding)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: OverlayGlassMetrics.previewMinimumHeight,
            alignment: .bottomLeading
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: OverlayGlassMetrics.overlayCornerRadius,
                style: .continuous
            )
        )
        .shadow(
            color: Color.black.opacity(
                OverlayGlassMetrics.previewWindowShadowOpacity
            ),
            radius: OverlayGlassMetrics.previewWindowShadowRadius,
            y: OverlayGlassMetrics.previewWindowShadowYOffset
        )
        .padding(OverlayGlassMetrics.captionOuterPadding)
    }

    private var previewSourceText: String {
        if !model.interimSourceText.isEmpty {
            return model.interimSourceText
        }
        return model.segments.last?.sourceText
            ?? settings.sourceSelection.previewText
    }

    private var previewTranslationText: String {
        model.segments.reversed().compactMap(\.translatedText).first
            ?? settings.targetSelection.previewText
    }
}

private struct HistoryRecordingStatus: View {
    @ObservedObject var history: TranslationHistoryStore
    var body: some View {
        if history.enabled {
            Label(history.activeSessionID == nil ? "History ready for new captions" : "Saving text history", systemImage: "record.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let message = history.messageKey, !history.enabled {
            Text(LocalizedStringKey(message))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

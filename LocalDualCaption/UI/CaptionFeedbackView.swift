import SwiftUI

/// Presentation data only. Error details never participate in toolbar sizing.
struct CaptionFeedback: Equatable {
    var status: CaptionStatus
    var notice: String?

    var errorMessage: String? {
        if case .error(let message) = status { return message }
        return nil
    }

    var needsPermission: Bool {
        guard let errorMessage else { return false }
        return [
            "Speech Recognition permission is not granted.",
            "Microphone permission is not granted.",
            "Screen & System Audio Recording permission is not granted."
        ].contains(errorMessage)
    }

    var visibleNotice: String? {
        notice == errorMessage ? nil : notice
    }

    func compactStatus(in language: AppLanguage) -> String {
        guard errorMessage != nil else { return status.label(language: language) }
        return language.localized(needsPermission ? "Permission required" : "Error")
    }
}

// Optional presentation injection for isolated UI fixtures, without running audio
// or modifying AppModel's private state. Normal app windows use live model state.
private struct CaptionFeedbackFixtureKey: EnvironmentKey {
    static let defaultValue: CaptionFeedback? = nil
}

private struct CaptionControlBarHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var captionFeedbackFixture: CaptionFeedback? {
        get { self[CaptionFeedbackFixtureKey.self] }
        set { self[CaptionFeedbackFixtureKey.self] = newValue }
    }

    var captionControlBarHeight: CGFloat {
        get { self[CaptionControlBarHeightKey.self] }
        set { self[CaptionControlBarHeightKey.self] = newValue }
    }
}

struct ControlPageScrollView<Content: View>: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings
    @Environment(\.captionFeedbackFixture) private var fixture
    @Environment(\.captionControlBarHeight) private var controlBarHeight
    let page: ControlPage
    var onOpenSettings: (() -> Void)? = nil
    var scrollResetToken: String? = nil
    var scrollResetAnchor = "page-top"
    @ViewBuilder var content: () -> Content

    private var feedback: CaptionFeedback {
        fixture ?? CaptionFeedback(status: model.status, notice: model.notice)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    InterfacePageIntroduction(page: page)
                        .id("page-top")
                    if feedback.errorMessage != nil || feedback.visibleNotice != nil {
                        CaptionFeedbackView(feedback: feedback, language: settings.appLanguage,
                                            onOpenSettings: onOpenSettings)
                    }
                    content()
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 16)
                // Measured per window, including the bar's outer spacing, so
                // the final control can scroll fully above it in every locale.
                .padding(.bottom, 28 + controlBarHeight)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: scrollResetToken) { _, _ in
                proxy.scrollTo(scrollResetAnchor, anchor: .top)
            }
            .onChange(of: feedback.errorMessage) { _, message in
                if message != nil { proxy.scrollTo("page-top", anchor: .top) }
            }
            .onChange(of: feedback.visibleNotice) { _, notice in
                if notice != nil { proxy.scrollTo("page-top", anchor: .top) }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}

private struct CaptionFeedbackView: View {
    let feedback: CaptionFeedback
    let language: AppLanguage
    let onOpenSettings: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = feedback.errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Label(LocalizedStringKey(feedback.needsPermission ? "Permission required" : "Error"),
                          systemImage: "exclamationmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(verbatim: language.localizedMessage(message))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if let onOpenSettings {
                        Button("Go to Settings", systemImage: "gearshape", action: onOpenSettings)
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("caption-error-details")
            }
            if let notice = feedback.visibleNotice {
                InterfaceNotice(text: language.localizedMessage(notice))
            }
        }
    }
}

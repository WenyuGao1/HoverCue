import AppKit
import SwiftUI

@main
struct LocalDualCaptionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @AppStorage(OverlaySettings.Key.appLanguage) private var appLanguageValue = AppLanguage.english.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageValue) ?? .english
    }

    var body: some Scene {
        WindowGroup {
            MainView(model: model, settings: model.settings)
                .environment(\.locale, appLanguage.locale)
                .onAppear {
                    appDelegate.model = model
                    model.attachUIHelpers()
                    Task { await model.refreshEnvironment() }
                }
        }
        .defaultSize(width: 1040, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu(appLanguage.localized("Live captions")) {
                Button(model.running ? appLanguage.localized("Stop Captions") : appLanguage.localized("Start Captions")) {
                    Task { model.running ? await model.stopCaptions() : await model.startCaptions() }
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                Button(model.overlayVisible ? appLanguage.localized("Hide Overlay") : appLanguage.localized("Show Overlay")) { model.toggleOverlay() }
                    .keyboardShortcut("o", modifiers: [.command, .option])
            }
        }

        MenuBarExtra("HoverCue", systemImage: "captions.bubble.fill") {
            Button(model.running ? appLanguage.localized("Stop Captions") : appLanguage.localized("Start Captions")) {
                Task { model.running ? await model.stopCaptions() : await model.startCaptions() }
            }
            Button(model.overlayVisible ? appLanguage.localized("Hide Overlay") : appLanguage.localized("Show Overlay")) { model.toggleOverlay() }
            Button(appLanguage.localized("Move Overlay to Current Screen")) { model.moveOverlayToCurrentScreen() }
            Divider()
            SettingsLink {
                Text(appLanguage.localized("Settings"))
            }
            Button(appLanguage.localized("Quit")) { NSApplication.shared.terminate(nil) }
        }

        Settings {
            ControlWindowView(model: model, settings: model.settings, initialPage: .settings)
                .frame(minWidth: 900, idealWidth: 1040, minHeight: 620, idealHeight: 780)
                .environment(\.locale, appLanguage.locale)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var terminationReplyPending = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        let needsCaptionCleanup = model.beginTermination()
        guard needsCaptionCleanup || model.historyHasPendingCleanup else { return .terminateNow }
        guard !terminationReplyPending else { return .terminateLater }
        terminationReplyPending = true
        Task {
            await model.stopCaptions()
            await model.history.waitForPendingOperations()
            replyToTerminationOnce(sender)
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await model.history.waitForPendingOperations()
            replyToTerminationOnce(sender)
        }
        return .terminateLater
    }

    private func replyToTerminationOnce(_ sender: NSApplication) {
        guard terminationReplyPending else { return }
        terminationReplyPending = false
        sender.reply(toApplicationShouldTerminate: true)
    }
}

import AppKit
import SwiftUI
import Translation

struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings
    var initialPage: ControlPage = .captions

    var body: some View {
        ControlWindowView(model: model, settings: settings, initialPage: initialPage)
            .translationTask(model.translationConfiguration) { session in
                await model.handleTranslationSession(session)
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                model.handleSystemSleep()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                model.handleSystemWake()
            }
    }
}

/// Native split-view navigation lets macOS supply the Liquid Glass sidebar and toolbar.
/// Both windows share the same model; only MainView owns the translation session.
struct ControlWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings
    @AppStorage(InterfaceTheme.storageKey) private var themeValue = InterfaceTheme.system.rawValue
    @State private var selectedPage: ControlPage?
    @State private var controlBarHeight: CGFloat = 0

    init(model: AppModel, settings: OverlaySettings, initialPage: ControlPage = .captions) {
        self.model = model
        self.settings = settings
        _selectedPage = State(initialValue: initialPage)
    }

    private var page: ControlPage { selectedPage ?? .captions }
    private var accent: Color { InterfaceTheme.resolved(themeValue).color }

    var body: some View {
        GeometryReader { geometry in
            NavigationSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(nsImage: NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 38, height: 38)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("HoverCue").font(.system(size: 17, weight: .semibold))
                            Text("Live bilingual captions")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 24)

                    List {
                        ForEach(ControlPage.allCases) { item in
                            Button {
                                selectedPage = item
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: item.symbol)
                                        .font(.system(size: 16))
                                        .foregroundStyle(page == item ? accent : .secondary)
                                        .frame(width: 22)
                                    Text(item.title)
                                        .font(.system(size: 13, weight: page == item ? .semibold : .regular))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 11)
                                .background(page == item ? accent.opacity(0.13) : .clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(page == item ? .isSelected : [])
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("Navigation")
                    .onMoveCommand { direction in
                        let pages = ControlPage.allCases
                        guard let index = pages.firstIndex(of: page) else { return }
                        if direction == .down { selectedPage = pages[min(index + 1, pages.count - 1)] }
                        if direction == .up { selectedPage = pages[max(index - 1, 0)] }
                    }

                    Label("On-device only", systemImage: "lock.shield")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(20)
                }
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
            } detail: {
                Group {
                    if page == .captions {
                        MainControlView(model: model, settings: settings, onOpenSettings: { selectedPage = .settings })
                    } else if page == .history {
                        TranslationHistoryView(model: model, settings: settings, history: model.history,
                                               onOpenSettings: { selectedPage = .settings })
                    } else {
                        SettingsView(model: model, settings: settings, page: page,
                                     onOpenSettings: page == .settings ? nil : { selectedPage = .settings })
                    }
                }
                .id(page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.captionControlBarHeight, controlBarHeight)
                .background(InterfaceStyle.background)
                .overlay(alignment: .bottom) {
                    // Keep the scroll viewport behind the native glass. Only the
                    // scroll content gets extra space to clear the floating bar.
                    CaptionControlBar(model: model, settings: settings)
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            geometry.size.height
                        } action: { height in
                            controlBarHeight = height
                        }
                }
                .navigationTitle(Text(verbatim: settings.appLanguage.localized(page.titleKey)))
            }
            .navigationSplitViewStyle(.balanced)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(minWidth: 900, minHeight: 620)
        .tint(accent)
        .environment(\.locale, settings.appLanguage.locale)
    }
}

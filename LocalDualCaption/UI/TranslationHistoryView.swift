import SwiftUI

struct HistoryRecordingControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var history: TranslationHistoryStore
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Save translation history", isOn: Binding(
                get: { history.enabled },
                set: { enabled in
                    if enabled { confirming = true } else { history.disable() }
                }
            ))
            .toggleStyle(.switch)
            .disabled(history.managing)
            .accessibilityIdentifier("history.recording")
            HistoryRecordingInformation()
            if history.enabled {
                Label(history.activeSessionID == nil ? "History ready for new captions" : "Saving text history", systemImage: "record.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .alert("Enable translation history?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) { }
            Button("Everyone informed and agreed — enable") { model.enableTranslationHistory() }
        } message: {
            Text("Confirm that everyone involved knows and agrees to local text recording, AI summaries and export. Only new stable sentences will be saved. Audio is never saved.")
        }
    }
}

struct HistoryRecordingInformation: View {
    @State private var privacyExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Before enabling history, make sure everyone involved knows and agrees.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Learn about history and privacy", isExpanded: $privacyExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("History is saved on this Mac. Exports go only to the location you choose.")
                    Text("Off by default on every app launch. Turning it off keeps existing history; audio is never saved.")
                    Text("When history is enabled, titles and bilingual summaries are created automatically on this Mac after captions stop, when Apple Intelligence is available.")
                    Text("Deleting history does not remove files you already exported. Storage is limited to 100 MB and 1,000 sessions.")
                }
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            .font(.callout)
            .accessibilityIdentifier("history.privacyDetails")
        }
    }
}

struct TranslationHistoryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings
    @ObservedObject var history: TranslationHistoryStore
    var onOpenSettings: (() -> Void)?
    @State private var selection: String?
    @State private var offset = 0
    @State private var scrollRequest = 0
    @State private var pendingPageScroll = false
    @State private var loaded = HistoryPage()
    @State private var pageMessage: String?
    @State private var confirmingClear = false
    @State private var confirmingDelete = false

    private var selected: HistorySession? { history.sessions.first { $0.id == selection } }
    private var loadKey: String { "\(selection ?? ""):\(offset):\(history.revision)" }

    var body: some View {
        ControlPageScrollView(model: model, settings: settings, page: .history, onOpenSettings: onOpenSettings,
                              scrollResetToken: String(scrollRequest),
                              scrollResetAnchor: "history-details") {
            historySection
            if let message = history.messageKey {
                VStack(alignment: .leading, spacing: 8) {
                    InterfaceNotice(text: settings.appLanguage.localized(message))
                    Button("Dismiss") { history.dismissMessage() }
                }
            }
            if history.sessions.isEmpty {
                ContentUnavailableView("No translation history", systemImage: "clock", description: Text("Enable history after obtaining permission, then start captions. Existing history remains available after recording is turned off."))
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                InterfaceSettingsSection {
                    Picker("Session", selection: $selection) {
                        Text("Choose a session").tag(Optional<String>.none)
                        ForEach(history.sessions) { session in
                            Text(verbatim: sessionTitle(session)).tag(Optional(session.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selection) { _, _ in offset = 0; pendingPageScroll = false; loaded = HistoryPage(); pageMessage = nil }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { actions }
                        VStack(alignment: .leading, spacing: 12) { actions }
                    }
                } header: {
                    InterfaceSectionTitle(title: "Saved sessions", symbol: "tray")
                }
                if let selected {
                    VStack(alignment: .leading, spacing: 16) {
                        if !selected.stableTitle.isEmpty {
                            Text(verbatim: selected.stableTitle).font(.title2.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        Text(verbatim: languagePair(selected)).font(.headline)
                        Text(selected.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                            .font(.caption).foregroundStyle(.secondary)
                        HistorySummaryCard(session: selected, language: settings.appLanguage) { level in
                            Task { await history.selectSummaryLevel(level, sessionID: selected.id) }
                        }
                        .disabled(history.managing || history.exporting)
                        Text("Full transcript").font(.headline)
                        if let pageMessage { InterfaceNotice(text: settings.appLanguage.localized(pageMessage)) }
                        ForEach(loaded.entries) { row in
                            InterfaceCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(row.timestamp, format: .dateTime.hour().minute().second())
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    Text(verbatim: row.source).textSelection(.enabled)
                                    Divider()
                                    if let translation = row.translation {
                                        Text(verbatim: translation).textSelection(.enabled)
                                    } else {
                                        Text(row.state == .failed ? "Translation failed" : "Translation incomplete")
                                            .font(.callout).foregroundStyle(.secondary)
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        HStack {
                            Button("Previous page") { pendingPageScroll = true; offset = max(0, offset - HistoryDatabase.pageSize) }
                                .accessibilityLabel("Previous page")
                                .disabled(offset == 0)
                            Spacer(minLength: 8)
                            Text(verbatim: "\(offset / HistoryDatabase.pageSize + 1)")
                                .font(.caption.monospacedDigit())
                            Spacer(minLength: 8)
                            Button("Next page") { pendingPageScroll = true; offset += HistoryDatabase.pageSize }
                                .accessibilityLabel("Next page")
                                .disabled(!loaded.hasMore)
                        }
                    }
                    .id("history-details")
                }
            }
        }
        .task {
            await history.reload()
            if selection == nil { selection = history.sessions.first?.id }
        }
        .task(id: loadKey) {
            guard let selection else { loaded = HistoryPage(); return }
            let requestedKey = loadKey
            do {
                let result = try await history.page(sessionID: selection, offset: offset)
                guard !Task.isCancelled, requestedKey == loadKey else { return }
                loaded = result
                pageMessage = nil
                if pendingPageScroll { pendingPageScroll = false; scrollRequest &+= 1 }
            } catch {
                guard !Task.isCancelled, requestedKey == loadKey else { return }
                loaded = HistoryPage()
                pendingPageScroll = false
                pageMessage = "History could not be opened. Existing files have been kept."
            }
        }
        .onChange(of: history.sessions) { _, sessions in
            if !sessions.contains(where: { $0.id == selection }) { selection = sessions.first?.id; offset = 0 }
        }
        .alert("Delete this history?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let selection { Task { await history.delete(sessionID: selection) } }
            }
        } message: { Text("This cannot be undone. Exported files are not deleted.") }
        .alert("Clear all history?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) { }
            Button("Clear all", role: .destructive) { Task { await history.clear() } }
        } message: { Text("Recording will stop and all saved sessions will be deleted. Exported files are not deleted.") }
    }

    private var historySection: some View {
        InterfaceSettingsSection {
            HistoryRecordingControls(model: model, history: history)
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Picker("Default summary detail", selection: $settings.historySummaryLevel) {
                    ForEach(HistorySummaryLevel.allCases) { level in
                        Text(LocalizedStringKey(level.titleKey)).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("history.defaultSummaryLevel")
                HistorySummaryInformationButton(language: settings.appLanguage, showsDefaultScope: true)
            }
        } header: {
            InterfaceSectionTitle(title: "Translation history", symbol: "clock.arrow.circlepath")
        }
    }

    @ViewBuilder private var actions: some View {
        Button("Export TXT", systemImage: "square.and.arrow.up") {
            if let selected { history.export(selected, language: settings.appLanguage) }
        }
        .disabled(selected == nil || history.exporting || history.managing)
        Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            .disabled(selected == nil || history.exporting || history.managing)
        Button("Clear all", role: .destructive) { confirmingClear = true }
            .disabled(history.exporting || history.managing)
    }

    private func languagePair(_ session: HistorySession) -> String {
        let locale = settings.appLanguage.locale
        return "\(locale.localizedString(forIdentifier: session.sourceLanguage) ?? session.sourceLanguage) → \(locale.localizedString(forIdentifier: session.targetLanguage) ?? session.targetLanguage)"
    }

    private func sessionTitle(_ session: HistorySession) -> String {
        let formatter = DateFormatter()
        formatter.locale = settings.appLanguage.locale
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        let title = session.stableTitle.isEmpty ? "" : session.stableTitle + " · "
        return "\(title)\(formatter.string(from: session.startedAt)) · \(languagePair(session)) · \(session.entryCount)"
    }
}


struct HistorySummaryCard: View {
    let session: HistorySession
    let language: AppLanguage
    var onSelectLevel: ((HistorySummaryLevel?) -> Void)? = nil

    var body: some View {
        InterfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label("AI summary", systemImage: "sparkles").font(.headline)
                    Spacer(minLength: 0)
                    HistorySummaryInformationButton(language: language,
                                                    showsLegacySummary: session.summaryLevel == nil)
                }
                Text("Generated with Apple Intelligence · On-device")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("history.summaryProvenance")
                Picker("Summary detail", selection: Binding(
                    get: { session.summaryLevel },
                    set: { onSelectLevel?($0) }
                )) {
                    if session.summaryLevel == nil || session.legacyDigest.state == .ready {
                        Text("Legacy summary").tag(Optional<HistorySummaryLevel>.none)
                    }
                    ForEach(HistorySummaryLevel.allCases) { level in
                        Text(LocalizedStringKey(level.titleKey)).tag(Optional(level))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("history.summaryLevel")
                if session.digest.state != .ready {
                    Text(verbatim: language.localized(session.digest.state.messageKey))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if session.digest.state == .generating {
                    ProgressView().controlSize(.small).accessibilityLabel("AI summary")
                }
                if let displayed = session.displayedSummary {
                    if session.digest.state != .ready {
                        Text(verbatim: language.localized("Showing saved summary:") + " " + language.localized(displayed.level?.titleKey ?? "Legacy summary"))
                            .font(.caption.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    summary(displayed.digest.sourceSummary, code: session.sourceLanguage)
                    Divider()
                    summary(displayed.digest.targetSummary, code: session.targetLanguage)
                    if displayed.digest.incomplete {
                        Text("Some entries are incomplete. The summary uses only available text.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summary(_ text: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: language.locale.localizedString(forIdentifier: code) ?? code)
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text(verbatim: text).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HistorySummaryInformationButton: View {
    let language: AppLanguage
    var showsDefaultScope = false
    var showsLegacySummary = false
    @State private var presented = false

    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 17))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("About AI summaries")
        .accessibilityLabel("About AI summaries")
        .accessibilityIdentifier("history.summaryInformation")
        .popover(isPresented: $presented) {
            VStack(alignment: .leading, spacing: 14) {
                Text("About AI summaries").font(.headline)
                Text("Summaries are generated on this Mac using Apple Intelligence. Bilingual content is processed locally. Check important details against the full transcript.")
                Divider()
                ForEach(HistorySummaryLevel.allCases) { level in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(level.titleKey)).fontWeight(.semibold)
                        Text(verbatim: language.localized(level.descriptionKey))
                    }
                }
                if showsDefaultScope {
                    Divider()
                    Text("Applies to new sessions. Each saved session can use a different summary detail.")
                }
                if showsLegacySummary {
                    Divider()
                    Text("This summary was created by an earlier version. Choose a detail level to create a new one from the full transcript.")
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 360, alignment: .leading)
            .padding(20)
            .environment(\.locale, language.locale)
        }
    }
}

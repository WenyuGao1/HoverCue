import Foundation
import SQLite3
import XCTest
@testable import LocalDualCaption

private actor LevelDigestGenerator: HistoryDigestGenerating {
    private var requested: [HistorySummaryLevel?] = []
    private var blocked: CheckedContinuation<Void, Never>?
    var blockDetailed = false
    func availability(for session: HistorySession) -> HistoryDigestState { .pending }
    func setBlocking() { blockDetailed = true }
    func release() { blocked?.resume(); blocked = nil }
    func count() -> Int { requested.count }
    func levels() -> [HistorySummaryLevel?] { requested }
    func generate(for session: HistorySession, loadPage: HistoryPageLoader) async throws -> HistoryDigestResult {
        requested.append(session.summaryLevel)
        if blockDetailed, session.summaryLevel == .detailed { await withCheckedContinuation { blocked = $0 } }
        // Deliberately ignore cancellation here: the store/database must reject stale results.
        let name = session.summaryLevel?.rawValue ?? "legacy"
        return .init(title: "Library planning \(name)", sourceSummary: "The library discussion has a \(name) summary. Friday was proposed and the time remains unconfirmed.", targetSummary: "图书馆讨论采用\(name)总结，提议周五前往，具体时间尚未确认。")
    }
}

private actor SectionTrace {
    var inputs: [String] = []
    func summarize(_ text: String) -> String { inputs.append(text); return "The discussion contains proposals and unresolved questions." }
    func joined() -> String { inputs.joined(separator: "\n") }
}

final class HistorySummaryLevelTests: XCTestCase {
    private func location() -> URL { FileManager.default.temporaryDirectory.appending(path: "HoverCue-Level-Tests-\(UUID().uuidString)/history.sqlite") }
    private func saved(level: HistorySummaryLevel? = nil) -> HistorySession {
        .init(id: "public-session", startedAt: Date(timeIntervalSince1970: 1_700_000_000), sourceLanguage: "en", targetLanguage: "zh-Hans", summaryLevel: level)
    }
    private var result: HistoryDigestResult { .init(title: "Library planning", sourceSummary: "A library visit was proposed for Friday. The time remains unconfirmed.", targetSummary: "有人提议周五去图书馆，具体时间尚未确认。") }
    private var exportLabels: [String] { ["History", "Original", "Translation", "Failed", "Incomplete", "Summary", "Entries incomplete", "Selected summary not ready", "Full transcript", "Summary detail", "Detailed"] }

    @MainActor func testDefaultIsStandardAndPreferenceSurvivesWithoutEnablingHistory() async {
        let name = "HoverCue-Level-Settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(OverlaySettings(defaults: defaults).historySummaryLevel, .standard)
        let settings = OverlaySettings(defaults: defaults)
        settings.historySummaryLevel = .detailed
        XCTAssertEqual(OverlaySettings(defaults: defaults).historySummaryLevel, .detailed)
        defaults.set("unknown-future-level", forKey: OverlaySettings.Key.historySummaryLevel)
        XCTAssertEqual(OverlaySettings(defaults: defaults).historySummaryLevel, .standard)
        let url = location()
        let store = TranslationHistoryStore(url: url, digestGenerator: nil)
        await store.reload()
        XCTAssertFalse(store.enabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor private func record(_ url: URL, engine: LevelDigestGenerator) async -> TranslationHistoryStore {
        let store = TranslationHistoryStore(url: url, digestGenerator: engine)
        store.enable()
        store.beginSession(source: "en", target: "zh-Hans", generation: 1)
        let work = TranslationWorkItem(segmentID: "public", sequence: 0, text: "The library visit was proposed for Friday, but the time is unconfirmed.", generation: 1)
        store.record(work); store.complete(work, translation: "提议周五参观图书馆，时间尚未确认。")
        store.disable(); await store.waitForSummaries()
        return store
    }

    @MainActor func testThreeVariantsAreCachedAndTitleAndInitialLevelStayStable() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let engine = LevelDigestGenerator()
        let store = await record(url, engine: engine)
        let first = try XCTUnwrap(store.sessions.first)
        XCTAssertEqual(first.summaryLevel, .standard)
        XCTAssertEqual(first.initialSummaryLevel, .standard)
        for level in [HistorySummaryLevel.detailed, .concise, .standard, .detailed] {
            await store.selectSummaryLevel(level, sessionID: first.id)
            await store.waitForSummaries()
            XCTAssertEqual(store.sessions.first?.summaryLevel, level)
            XCTAssertEqual(store.sessions.first?.digest.state, .ready)
            XCTAssertEqual(store.sessions.first?.stableTitle, first.stableTitle)
        }
        let requests = await engine.levels()
        XCTAssertEqual(requests, [.standard, .detailed, .concise])
        XCTAssertEqual(store.sessions.first?.variants.count, 3)
        XCTAssertEqual(store.sessions.first?.initialSummaryLevel, .standard)
        let restarted = TranslationHistoryStore(url: url, digestGenerator: nil)
        await restarted.reload()
        XCTAssertFalse(restarted.enabled)
        XCTAssertEqual(restarted.sessions, store.sessions)
    }

    @MainActor func testChangingLevelRetainsVisibleSavedSummaryAndRejectsLateResponse() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let engine = LevelDigestGenerator()
        let store = await record(url, engine: engine)
        let id = try XCTUnwrap(store.sessions.first?.id)
        await engine.setBlocking()
        await store.selectSummaryLevel(.detailed, sessionID: id)
        // Database work may still be pending after any fixed number of yields.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await engine.count() < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let startedRequests = await engine.count()
        XCTAssertEqual(startedRequests, 2, "The blocked detailed request must start before changing levels.")
        XCTAssertEqual(store.sessions.first?.digest.state, .generating)
        XCTAssertEqual(store.sessions.first?.displayedSummary?.level, .standard)
        await store.selectSummaryLevel(.concise, sessionID: id)
        await engine.release()
        await store.waitForSummaries()
        XCTAssertEqual(store.sessions.first?.summaryLevel, .concise)
        XCTAssertEqual(store.sessions.first?.digest.state, .ready)
        XCTAssertEqual(store.sessions.first?.variants[.detailed]?.state, .pending)
        XCTAssertTrue(store.sessions.first?.variants[.detailed]?.sourceSummary.isEmpty == true)
        XCTAssertTrue(store.sessions.first?.digest.sourceSummary.contains("concise") == true)
    }

    @MainActor func testLegacyReadySummaryIsKeptAndNotAutomaticallyRegenerated() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = HistoryDatabase(url: url)
        let old = saved()
        try await database.apply(.append(old, .init(sequence: 0, timestamp: old.startedAt, source: "A library visit was proposed.")))
        try await database.apply(.finish(sessionID: old.id, date: old.startedAt))
        try await database.setDigestState(sessionID: old.id, state: .generating)
        try await database.saveDigest(sessionID: old.id, result: result)
        let engine = LevelDigestGenerator()
        let store = TranslationHistoryStore(url: url, digestGenerator: engine)
        await store.reload(); await store.waitForSummaries()
        let count = await engine.count()
        XCTAssertEqual(count, 0)
        XCTAssertNil(store.sessions.first?.summaryLevel)
        XCTAssertEqual(store.sessions.first?.digest.sourceSummary, result.sourceSummary)
        await store.selectSummaryLevel(.detailed, sessionID: old.id)
        await store.waitForSummaries()
        XCTAssertEqual(store.sessions.first?.legacyDigest.sourceSummary, result.sourceSummary)
        XCTAssertEqual(store.sessions.first?.stableTitle, result.title)
        XCTAssertEqual(store.sessions.first?.summaryLevel, .detailed)
        await store.selectSummaryLevel(nil, sessionID: old.id)
        await store.waitForSummaries()
        XCTAssertNil(store.sessions.first?.summaryLevel)
        XCTAssertEqual(store.sessions.first?.digest.sourceSummary, result.sourceSummary)
        await store.selectSummaryLevel(.detailed, sessionID: old.id)
        await store.waitForSummaries()
        let afterSwitch = await engine.count()
        XCTAssertEqual(afterSwitch, 1)
    }

    func testExportUsesRequestedVariantAndNeverSubstitutesSavedDifferentLevel() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = HistoryDatabase(url: url)
        var session = saved(level: .standard)
        try await database.apply(.append(session, .init(sequence: 0, timestamp: session.startedAt, source: "PUBLIC TRANSCRIPT MARKER")))
        try await database.setDigestState(sessionID: session.id, state: .generating, level: .standard)
        try await database.saveDigest(sessionID: session.id, result: result, level: .standard)
        try await database.selectSummaryLevel(sessionID: session.id, level: .detailed)
        let catalog = try await database.sessions()
        session = try XCTUnwrap(catalog.first)
        let output = url.deletingLastPathComponent().appending(path: "public.txt")
        try await database.export(session: session, to: output, labels: exportLabels)
        var text = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(text.contains("Summary detail: Detailed"))
        XCTAssertTrue(text.contains(result.title))
        XCTAssertTrue(text.contains("Selected summary not ready"))
        XCTAssertTrue(text.contains("PUBLIC TRANSCRIPT MARKER"))
        XCTAssertFalse(text.contains(result.sourceSummary))
        try await database.setDigestState(sessionID: session.id, state: .generating, level: .detailed)
        try await database.saveDigest(sessionID: session.id, result: result, level: .detailed)
        try await database.export(session: session, to: output, labels: exportLabels)
        text = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(text.contains(result.sourceSummary))
        XCTAssertTrue(text.contains(result.targetSummary))
        XCTAssertFalse(text.contains("Selected summary not ready"))
    }

    func testVariantSaveIsAtomicRejectsWrongLanguagesAndDoesNotResurrectDeletedHistory() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = HistoryDatabase(url: url)
        let session = saved(level: .standard)
        try await database.apply(.append(session, .init(sequence: 0, timestamp: session.startedAt, source: "A library visit was proposed.")))
        try await database.setDigestState(sessionID: session.id, state: .generating, level: .standard)
        do {
            try await database.saveDigest(sessionID: session.id, result: .init(title: result.title, sourceSummary: "这不是英文，这份总结不能保存。", targetSummary: result.targetSummary), level: .standard)
            XCTFail("Wrong language must fail atomically")
        } catch {}
        var catalog = try await database.sessions()
        XCTAssertTrue(catalog.first?.digest.sourceSummary.isEmpty == true)
        XCTAssertTrue(catalog.first?.digest.targetSummary.isEmpty == true)
        try await database.selectSummaryLevel(sessionID: session.id, level: .concise)
        try await database.saveDigest(sessionID: session.id, result: result, level: .standard)
        catalog = try await database.sessions()
        XCTAssertTrue(catalog.first?.variants[.standard]?.sourceSummary.isEmpty == true)
        try await database.apply(.delete(sessionID: session.id))
        try await database.saveDigest(sessionID: session.id, result: result, level: .standard)
        catalog = try await database.sessions()
        XCTAssertTrue(catalog.isEmpty)
    }

    func testEachProfileVisitsAllLongTranscriptTextWithinBoundsAndRetainsMoreSections() async throws {
        let rows = (0..<250).map { HistoryEntry(sequence: $0, timestamp: Date(), source: "PUBLIC_MARKER_\($0) " + String(repeating: "discussion ", count: 12), state: .translated) }
        for level in HistorySummaryLevel.allCases {
            let trace = SectionTrace()
            let notes = try await HistoryDigestReducer.reduce(loadPage: { offset in
                .init(entries: Array(rows.dropFirst(offset).prefix(100)), hasMore: offset + 100 < rows.count)
            }, budget: 300, maximumSections: level.maximumSections, summarize: { await trace.summarize($0) })
            XCTAssertEqual(notes.sections.count, level.maximumSections)
            XCTAssertTrue(notes.sections.allSatisfy { $0.utf8.count <= 300 })
            let visited = await trace.joined()
            for index in 0..<250 { XCTAssertTrue(visited.contains("PUBLIC_MARKER_\(index) "), "\(level): \(index)") }
        }
    }

    func testShortConversationIsNotArtificiallySplitOrPadded() async throws {
        let row = HistoryEntry(sequence: 0, timestamp: Date(), source: "A Friday library visit was proposed; no time is confirmed.", state: .translated)
        for level in HistorySummaryLevel.allCases {
            let notes = try await HistoryDigestReducer.reduce(loadPage: { _ in .init(entries: [row]) }, budget: 300, maximumSections: level.maximumSections, summarize: { _ in XCTFail("Short text should remain intact"); return "" })
            XCTAssertEqual(notes.sections, [row.source])
        }
    }

    func testModelRequestChunksAreLosslessBoundedAndPreferSentenceOrWordBreaks() {
        let text = String(repeating: "A Friday library visit was proposed. 图书馆尚未预约。 ", count: 30)
        let parts = HistoryDigestText.requestChunks(text, maximumBytes: 140)
        XCTAssertEqual(parts.joined(), text)
        XCTAssertTrue(parts.allSatisfy { $0.utf8.count <= 140 })
        for part in parts.dropLast() { XCTAssertTrue(part.last!.isWhitespace || ".!?。！？".contains(part.last!)) }
    }

    func testNewSummaryControlsAndExportCopyAreLocalizedInAllNineNonEnglishLanguages() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let keys = HistorySummaryLevel.allCases.flatMap { [$0.titleKey, $0.descriptionKey] } + ["Default summary detail", "Summary detail", "Legacy summary", "Showing saved summary:", "The selected summary is not ready. The full transcript follows.", "Applies to new sessions. Each saved session can use a different summary detail.", "This summary was created by an earlier version. Choose a detail level to create a new one from the full transcript.", "The summary level could not be changed. Existing summaries have been kept."]
        for locale in HistoryDigestLanguagePolicy.identifiers where locale != "en" {
            let path = root.appending(path: "LocalDualCaption/\(locale).lproj/Localizable.strings")
            let dict = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: path), format: nil) as? [String: String])
            for key in keys { XCTAssertFalse((dict[key] ?? "").isEmpty, "\(locale): \(key)") }
        }
    }
}

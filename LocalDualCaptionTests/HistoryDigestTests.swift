import Foundation
import SQLite3
import XCTest
@testable import LocalDualCaption

private actor TestDigestGenerator: HistoryDigestGenerating {
    var state: HistoryDigestState
    var requests: [HistorySession] = []
    let delayed: Bool
    init(state: HistoryDigestState = .pending, delayed: Bool = false) { self.state = state; self.delayed = delayed }
    func availability(for session: HistorySession) -> HistoryDigestState { state }
    func setState(_ state: HistoryDigestState) { self.state = state }
    func count() -> Int { requests.count }
    func request() -> HistorySession? { requests.first }
    func generate(for session: HistorySession, loadPage: HistoryPageLoader) async throws -> HistoryDigestResult {
        requests.append(session)
        if delayed { try await Task.sleep(for: .seconds(20)) }
        let page = try await loadPage(0)
        guard !page.entries.isEmpty else { throw HistoryDigestError.state(.insufficient) }
        return HistoryDigestResult(title: "Bibliotheksbesuch", sourceSummary: "A Friday library visit was proposed. The time is unconfirmed.", targetSummary: "有人提议周五去图书馆，时间尚未确定。", incomplete: page.entries.contains { $0.state != .translated })
    }
}

private actor DigestTrace {
    var values: [String] = []
    func summarize(_ text: String) -> String { values.append(text); return "Condensed notes." }
    func inputs() -> [String] { values }
}

final class HistoryDigestTests: XCTestCase {
    private func location() -> URL { FileManager.default.temporaryDirectory.appending(path: "HoverCue-Digest-Tests-\(UUID().uuidString)/history.sqlite") }
    private func session(_ id: String = "test") -> HistorySession {
        .init(id: id, startedAt: Date(timeIntervalSince1970: 1_700_000_000), sourceLanguage: "en", targetLanguage: "zh-Hans", titleLanguage: "de")
    }
    private func work() -> TranslationWorkItem { .init(segmentID: "public", sequence: 0, text: "A Friday library visit was proposed; the time is unconfirmed.", generation: 1) }
    @MainActor private func seeded(_ url: URL, generator: TestDigestGenerator) async -> TranslationHistoryStore {
        let store = TranslationHistoryStore(url: url, digestGenerator: generator)
        store.enable()
        store.beginSession(source: "en", target: "zh-Hans", generation: 1, titleLanguage: "de")
        store.record(work())
        store.complete(work(), translation: "有人提议周五去图书馆，时间尚未确定。")
        await store.flush()
        return store
    }

    @MainActor func testAutomaticallyCreatesTitleAndBothSummariesOnlyAfterSessionEnds() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let generator = TestDigestGenerator()
        let store = await seeded(url, generator: generator)
        let requestCount = await generator.count()
        XCTAssertEqual(requestCount, 0)
        store.disable()
        await store.waitForSummaries()
        let saved = try XCTUnwrap(store.sessions.first)
        XCTAssertEqual(saved.digest.state, .ready)
        XCTAssertEqual(saved.digest.title, "Bibliotheksbesuch")
        XCTAssertFalse(saved.digest.sourceSummary.isEmpty)
        XCTAssertFalse(saved.digest.targetSummary.isEmpty)
        let request = await generator.request()
        XCTAssertEqual(request?.sourceLanguage, "en")
        XCTAssertEqual(request?.targetLanguage, "zh-Hans")
        XCTAssertEqual(request?.titleLanguage, "de")
        XCTAssertFalse(store.enabled)
        let restarted = TranslationHistoryStore(url: url, digestGenerator: nil)
        await restarted.reload()
        XCTAssertFalse(restarted.enabled)
        XCTAssertEqual(restarted.sessions.first?.digest, saved.digest)
    }

    @MainActor func testLiveCaptionsPauseSummaryEvenWhenRecordingIsDisabled() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let generator = TestDigestGenerator()
        let store = await seeded(url, generator: generator)
        store.setCaptionsActive(true)
        store.disable()
        await store.waitForSummaries()
        let requestCount = await generator.count()
        XCTAssertEqual(requestCount, 0)
        store.setCaptionsActive(false)
        await store.waitForSummaries()
        XCTAssertEqual(store.sessions.first?.digest.state, .ready)
    }

    @MainActor func testUnavailableModelRetainsTextAndAutomaticallyRetriesWhenAvailable() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let generator = TestDigestGenerator(state: .modelNotReady)
        let store = await seeded(url, generator: generator)
        store.disable(); await store.waitForSummaries()
        XCTAssertEqual(store.sessions.first?.digest.state, .modelNotReady)
        XCTAssertEqual(store.sessions.first?.entryCount, 1)
        for _ in 0..<3 { await store.reload(); await store.waitForSummaries() }
        let requestCount = await generator.count()
        XCTAssertEqual(requestCount, 0)
        await generator.setState(.pending)
        await store.refreshDigestAvailability(); await store.waitForSummaries()
        XCTAssertEqual(store.sessions.first?.digest.state, .ready)
    }

    @MainActor func testDeleteAndClearCancelPendingGenerationWithoutResurrectingRows() async throws {
        for clear in [false, true] {
            let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let generator = TestDigestGenerator(delayed: true)
            let store = await seeded(url, generator: generator)
            let id = try XCTUnwrap(store.activeSessionID)
            store.disable(); await store.flush()
            for _ in 0..<200 { if await generator.count() > 0 { break }; await Task.yield() }
            if clear { await store.clear() } else { await store.delete(sessionID: id) }
            await store.waitForSummaries(); await store.reload()
            XCTAssertTrue(store.sessions.isEmpty)
        }
    }

    @MainActor func testTerminationSavesTextButDoesNotWaitForModelAndResumesNextLaunch() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let generator = TestDigestGenerator(delayed: true)
        let store = await seeded(url, generator: generator)
        store.disable(); await store.flush()
        for _ in 0..<200 { if await generator.count() > 0 { break }; await Task.yield() }
        store.prepareForTermination()
        await store.waitForPendingOperations()
        await store.waitForSummaries()
        XCTAssertEqual(store.sessions.first?.digest.state, .pending)
        let restarted = TranslationHistoryStore(url: url, digestGenerator: TestDigestGenerator())
        await restarted.reload(); await restarted.waitForSummaries()
        XCTAssertEqual(restarted.sessions.first?.digest.state, .ready)
        XCTAssertFalse(restarted.enabled)
    }

    func testMigrationFromBuild18PreservesEntriesAndClosesAbandonedSession() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        let sql = """
        CREATE TABLE sessions(id TEXT PRIMARY KEY, started REAL NOT NULL, source TEXT NOT NULL, target TEXT NOT NULL, ended REAL);
        CREATE TABLE entries(session TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, sequence INTEGER NOT NULL, timestamp REAL NOT NULL, original TEXT NOT NULL, translation TEXT, state TEXT NOT NULL, PRIMARY KEY(session, sequence));
        INSERT INTO sessions VALUES('legacy',1700000000,'en','zh-Hant',NULL);
        INSERT INTO entries VALUES('legacy',0,1700000001,'Public library proposal',NULL,'pending');
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK); sqlite3_close(db)
        let database = HistoryDatabase(url: url)
        let legacyCatalog = try await database.sessions()
        XCTAssertEqual(legacyCatalog.first?.digest.state, .pending)
        try await database.recover(excluding: nil, titleLanguage: "ja")
        let saved = try await database.sessions()
        XCTAssertEqual(saved.first?.id, "legacy")
        XCTAssertEqual(saved.first?.endedAt, Date(timeIntervalSince1970: 1_700_000_001))
        XCTAssertEqual(saved.first?.titleLanguage, "ja")
        let page = try await database.page(sessionID: "legacy", offset: 0)
        XCTAssertEqual(page.entries.first?.source, "Public library proposal")
        XCTAssertEqual(page.entries.first?.state, .interrupted)
        try await database.recover(excluding: nil, titleLanguage: "de")
        let repeatedCatalog = try await database.sessions()
        XCTAssertEqual(repeatedCatalog.first?.titleLanguage, "ja")
    }

    func testBothSummariesAreCommittedAtomicallyAndExportReadsLatestDigest() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = HistoryDatabase(url: url)
        let saved = session()
        try await database.apply(.append(saved, .init(sequence: 0, timestamp: Date(), source: "A library visit is proposed.")))
        try await database.setDigestState(sessionID: saved.id, state: .generating)
        do {
            try await database.saveDigest(sessionID: saved.id, result: .init(title: "Title", sourceSummary: "Valid", targetSummary: ""))
            XCTFail("Incomplete bilingual result must not be saved")
        } catch {}
        let rejectedCatalog = try await database.sessions()
        XCTAssertTrue(rejectedCatalog.first?.digest.title.isEmpty == true)
        try await database.saveDigest(sessionID: saved.id, result: .init(title: "Bibliotheksbesuch", sourceSummary: "Not confirmed.", targetSummary: "尚未确认。", incomplete: true))
        let output = url.deletingLastPathComponent().appending(path: "synthetic.txt")
        try await database.export(session: saved, to: output, labels: ["History", "Original", "Translation", "Failed", "Incomplete", "AI summary", "Entries incomplete", "No summary", "Full transcript"])
        let text = try String(contentsOf: output, encoding: .utf8)
        for value in ["Bibliotheksbesuch", "Not confirmed.", "尚未确认。", "AI summary (en)", "AI summary (zh-Hans)", "Entries incomplete", "Full transcript", "A library visit is proposed."] { XCTAssertTrue(text.contains(value)) }
        try await database.apply(.delete(sessionID: saved.id))
        try await database.saveDigest(sessionID: saved.id, result: .init(title: "Late", sourceSummary: "Late", targetSummary: "迟到"))
        let deletedCatalog = try await database.sessions()
        XCTAssertTrue(deletedCatalog.isEmpty)
    }

    func testUnicodeChunkingIsLosslessAndBoundedIncludingOversizedGrapheme() {
        let text = String(repeating: "English 中文👨‍👩‍👧‍👦 e\u{301} ", count: 100) + "a" + String(repeating: "\u{301}", count: 1_000)
        let chunks = HistoryDigestText.chunks(text, maximumBytes: 100)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.utf8.count <= 100 })
    }

    func testLongConversationVisitsEveryPageAndEveryMiddleChunkWithinBudget() async throws {
        let trace = DigestTrace()
        let rows = (0..<250).map { HistoryEntry(sequence: $0, timestamp: Date(), source: "PUBLIC_MARKER_\($0) " + String(repeating: "discussion ", count: 15), state: .translated) }
        _ = try await HistoryDigestReducer.reduce(loadPage: { offset in
            .init(entries: Array(rows.dropFirst(offset).prefix(100)), hasMore: offset + 100 < rows.count)
        }, budget: 300, summarize: { await trace.summarize($0) })
        let inputs = await trace.inputs()
        XCTAssertTrue(inputs.allSatisfy { $0.utf8.count <= 300 })
        let joined = inputs.joined()
        for index in 0..<250 { XCTAssertTrue(joined.contains("PUBLIC_MARKER_\(index) ")) }
    }

    func testSummaryFilenameUsesTitleAndRemovesPathSeparators() {
        var saved = session()
        saved.digest.title = "Library / visit: ../test\nTitle"
        let filename = HistoryDigestText.exportFilename(saved)
        XCTAssertTrue(filename.contains("Library"))
        XCTAssertTrue(filename.hasSuffix(".txt"))
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains("\n"))
    }
}

import Foundation
import XCTest
@testable import LocalDualCaption

final class TranslationHistoryTests: XCTestCase {
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "HoverCue-History-Tests-\(UUID().uuidString)/history.sqlite")
    }

    private func session(_ id: String = UUID().uuidString) -> HistorySession {
        HistorySession(id: id, startedAt: Date(timeIntervalSince1970: 1_700_000_000), sourceLanguage: "en", targetLanguage: "zh-Hans")
    }

    private func work(_ sequence: Int, generation: Int = 1) -> TranslationWorkItem {
        TranslationWorkItem(segmentID: "sample-\(sequence)", sequence: sequence, text: "Public test sentence \(sequence).", generation: generation)
    }

    @MainActor
    func testDefaultOffDoesNotCreateDirectoryOrContent() async throws {
        let url = location()
        let store = TranslationHistoryStore(url: url, digestGenerator: nil)
        await store.reload()
        store.beginSession(source: "en", target: "zh-Hans", generation: 1)
        store.record(work(0))
        store.complete(work(0), translation: "测试。")
        await store.flush()
        XCTAssertFalse(store.enabled)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    @MainActor
    func testNavigatingAwayDuringReloadDoesNotShowAFalseStorageError() async {
        let store = TranslationHistoryStore(url: location(), digestGenerator: nil)
        let loading = Task { await store.reload() }
        loading.cancel()
        await loading.value
        XCTAssertNil(store.messageKey)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    @MainActor
    func testHistoryOutlivesSixVisibleSegmentsAndKeepsTranslationOrder() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TranslationHistoryStore(url: url, digestGenerator: nil)
        store.enable()
        store.beginSession(source: "en", target: "zh-Hans", generation: 1)
        let id = try XCTUnwrap(store.activeSessionID)
        for sequence in 0..<40 { store.record(work(sequence)) }
        for sequence in (0..<40).reversed() { store.complete(work(sequence), translation: "测试 \(sequence)") }
        store.finishSession()
        await store.flush()
        let page = try await store.page(sessionID: id, offset: 0)
        XCTAssertEqual(page.entries.map(\.sequence), Array(0..<40))
        XCTAssertEqual(page.entries.map(\.translation), (0..<40).map { "测试 \($0)" })
        XCTAssertEqual(store.sessions.first?.entryCount, 40)
    }

    @MainActor
    func testDisableRejectsLateTranslationsAndReenableDoesNotBackfill() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TranslationHistoryStore(url: url, digestGenerator: nil)
        store.enable()
        store.beginSession(source: "en", target: "zh-Hans", generation: 1)
        let first = try XCTUnwrap(store.activeSessionID)
        store.record(work(0))
        store.disable()
        store.record(work(1))
        store.complete(work(0), translation: "Must not be saved")
        store.enable()
        store.beginSession(source: "en", target: "zh-Hans", generation: 1)
        let second = try XCTUnwrap(store.activeSessionID)
        store.complete(work(0), translation: "Must not be backfilled")
        store.record(work(2))
        store.complete(work(2), translation: "New translation")
        await store.flush()
        let old = try await store.page(sessionID: first, offset: 0)
        let new = try await store.page(sessionID: second, offset: 0)
        XCTAssertEqual(old.entries.count, 1)
        XCTAssertNil(old.entries[0].translation)
        XCTAssertEqual(old.entries[0].state, .interrupted)
        XCTAssertEqual(new.entries.map(\.sequence), [2])
        XCTAssertEqual(new.entries.first?.translation, "New translation")
    }

    @MainActor
    func testStaleGenerationCannotWriteToNextSession() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TranslationHistoryStore(url: url, digestGenerator: nil)
        store.enable()
        store.beginSession(source: "en", target: "zh-Hans", generation: 1)
        store.record(work(0))
        store.beginSession(source: "en", target: "fr", generation: 3)
        let id = try XCTUnwrap(store.activeSessionID)
        store.record(work(1, generation: 1))
        store.record(work(0, generation: 3))
        store.complete(work(0), translation: "Stale")
        store.complete(work(0, generation: 3), translation: "Bonjour")
        await store.flush()
        let page = try await store.page(sessionID: id, offset: 0)
        XCTAssertEqual(page.entries.count, 1)
        XCTAssertEqual(page.entries.first?.translation, "Bonjour")
    }

    @MainActor
    func testRestartResetsConsentAndRetainsSavedHistory() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = TranslationHistoryStore(url: url, digestGenerator: nil)
        first.enable()
        first.beginSession(source: "en", target: "zh-Hans", generation: 1)
        first.record(work(0))
        first.finishSession()
        await first.flush()
        let next = TranslationHistoryStore(url: url, digestGenerator: nil)
        await next.reload()
        XCTAssertFalse(next.enabled)
        XCTAssertNil(next.activeSessionID)
        XCTAssertEqual(next.sessions.count, 1)
    }

    @MainActor
    func testDeletingDuringWritesCannotResurrectSession() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TranslationHistoryStore(url: url, digestGenerator: nil)
        store.enable()
        store.beginSession(source: "en", target: "zh-Hans", generation: 1)
        let id = try XCTUnwrap(store.activeSessionID)
        for sequence in 0..<30 { store.record(work(sequence)) }
        await store.delete(sessionID: id)
        store.complete(work(0), translation: "Late")
        await store.flush()
        await store.reload()
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertFalse(store.enabled)
    }

    @MainActor
    func testClearPreservesExportedFilesAndDoesNotResumeRecording() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TranslationHistoryStore(url: url, digestGenerator: nil)
        store.enable()
        store.beginSession(source: "en", target: "zh-Hans", generation: 1)
        store.record(work(0))
        await store.flush()
        let exported = url.deletingLastPathComponent().appending(path: "already-exported.txt")
        try Data("Existing user export".utf8).write(to: exported)
        await store.clear()
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertFalse(store.enabled)
        XCTAssertEqual(try String(contentsOf: exported, encoding: .utf8), "Existing user export")
    }

    func testPaginationDuplicatesUnicodeAndSQLText() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let db = HistoryDatabase(url: url)
        let session = session()
        for index in 0..<115 {
            let row = HistoryEntry(sequence: index, timestamp: session.startedAt, source: "日本語 中文 \0 '); DROP TABLE sessions; -- \nSample \(index)")
            try await db.apply(.append(session, row))
            if index == 0 { try await db.apply(.append(session, row)) }
        }
        let first = try await db.page(sessionID: session.id, offset: 0)
        let second = try await db.page(sessionID: session.id, offset: 100)
        let sessions = try await db.sessions()
        XCTAssertEqual(first.entries.count, 100)
        XCTAssertTrue(first.hasMore)
        XCTAssertEqual(second.entries.map(\.sequence), Array(100..<115))
        XCTAssertFalse(second.hasMore)
        XCTAssertEqual(sessions.first?.entryCount, 115)
        XCTAssertTrue(first.entries[0].source.contains("DROP TABLE"))
        XCTAssertTrue(first.entries[0].source.contains("\0"))
    }

    func testSessionAndEntryLimitsRollbackWithoutDeletingExistingRows() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let db = HistoryDatabase(url: url, limits: .init(maximumSessions: 1, maximumEntries: 1))
        let session = session()
        try await db.apply(.append(session, .init(sequence: 0, timestamp: session.startedAt, source: "Public test")))
        do {
            try await db.apply(.append(session, .init(sequence: 1, timestamp: session.startedAt, source: "Over limit")))
            XCTFail("Entry quota must be enforced")
        } catch HistoryFailure.limit { }
        do {
            try await db.apply(.append(self.session(), .init(sequence: 0, timestamp: session.startedAt, source: "Over session limit")))
            XCTFail("Session quota must be enforced")
        } catch HistoryFailure.limit { }
        let saved = try await db.sessions()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].entryCount, 1)
    }

    @MainActor
    func testTextAndQueueLimitsStopRecordingWithVisibleError() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TranslationHistoryStore(url: url, limits: .init(maximumTextBytes: 4))
        store.enable()
        store.beginSession(source: "en", target: "zh-Hans", generation: 1)
        store.record(work(0))
        XCTAssertFalse(store.enabled)
        XCTAssertNotNil(store.messageKey)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let queue = TranslationHistoryStore(url: url, digestGenerator: nil)
        queue.enable()
        queue.beginSession(source: "en", target: "zh-Hans", generation: 1)
        for index in 0...TranslationHistoryStore.maximumQueuedWrites { queue.record(work(index)) }
        XCTAssertFalse(queue.enabled)
        XCTAssertNotNil(queue.messageKey)
        await queue.flush()
    }

    func testExportIsUTF8OrderedAndMarksMissingTranslations() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let db = HistoryDatabase(url: url)
        let session = session()
        for index in 0..<3 { try await db.apply(.append(session, .init(sequence: index, timestamp: session.startedAt, source: "Sample \(index)"))) }
        try await db.apply(.translate(sessionID: session.id, sequence: 0, text: "你好\n世界"))
        try await db.apply(.translate(sessionID: session.id, sequence: 1, text: nil))
        let destination = url.deletingLastPathComponent().appending(path: "test.txt")
        try await db.export(session: session, to: destination, labels: ["History", "Original", "Translation", "Failed", "Incomplete"])
        let text = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(text.contains("你好\n世界"))
        XCTAssertTrue(text.contains("Failed"))
        XCTAssertTrue(text.contains("Incomplete"))
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "Sample 0")?.lowerBound), try XCTUnwrap(text.range(of: "Sample 2")?.lowerBound))
    }

    func testExportLimitDoesNotReplaceAnExistingFile() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let db = HistoryDatabase(url: url, limits: .init(maximumExportBytes: 10))
        let session = session()
        try await db.apply(.append(session, .init(sequence: 0, timestamp: session.startedAt, source: "Sample")))
        let destination = url.deletingLastPathComponent().appending(path: "existing.txt")
        try Data("Keep this".utf8).write(to: destination)
        do {
            try await db.export(session: session, to: destination, labels: ["History", "Original", "Translation", "Failed", "Incomplete"])
            XCTFail("Export limit must be enforced")
        } catch HistoryFailure.limit { }
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "Keep this")
    }

    func testDatabaseCapacityFailureRetainsCommittedHistory() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // Include the three-variant schema before filling the artificial tiny database.
        let db = HistoryDatabase(url: url, limits: .init(maximumBytes: 64 * 1_024))
        let session = session()
        var committed = 0
        var reachedLimit = false
        for index in 0..<20 {
            do {
                try await db.apply(.append(session, .init(sequence: index, timestamp: session.startedAt, source: String(repeating: "x", count: 4_096))))
                committed += 1
            } catch HistoryFailure.limit {
                reachedLimit = true
                break
            }
        }
        XCTAssertTrue(reachedLimit)
        XCTAssertGreaterThan(committed, 0)
        let saved = try await db.page(sessionID: session.id, offset: 0)
        XCTAssertEqual(saved.entries.count, committed)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        XCTAssertLessThanOrEqual(try XCTUnwrap(size), 64 * 1_024)
    }

    @MainActor
    func testStorageFailureStopsHistoryWithoutStartingCapture() async throws {
        let url = location()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("Not a database".utf8).write(to: url)
        let store = TranslationHistoryStore(url: url, digestGenerator: nil)
        store.enable()
        store.beginSession(source: "en", target: "fr", generation: 1)
        store.record(work(0))
        await store.flush()
        XCTAssertFalse(store.enabled)
        XCTAssertNotNil(store.messageKey)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Not a database")
    }
}

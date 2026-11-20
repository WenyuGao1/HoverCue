import Foundation
import NaturalLanguage
import SQLite3
import XCTest
@testable import LocalDualCaption

final class HistoryDigestLanguageTests: XCTestCase {
    static let samples: [String: String] = [
        "en": "The group discussed visiting the library on Friday afternoon. They proposed borrowing books and using the reading room, but the time has not been confirmed.",
        "zh-Hans": "大家讨论了周五下午去图书馆的安排，提议借书和使用阅览室，但具体时间尚未确定，也没有完成预约。",
        "zh-Hant": "大家討論了週五下午去圖書館的安排，提議借書和使用閱覽室，但具體時間尚未確定，也沒有完成預約。",
        "de": "Die Gruppe besprach einen Bibliotheksbesuch am Freitagnachmittag. Sie schlug vor, Bücher auszuleihen und den Lesesaal zu nutzen, aber die Uhrzeit wurde noch nicht bestätigt.",
        "es": "El grupo habló de visitar la biblioteca el viernes por la tarde. Propusieron tomar libros prestados y utilizar la sala de lectura, pero la hora todavía no se ha confirmado.",
        "fr": "Le groupe a discuté d’une visite à la bibliothèque vendredi après-midi. Il a proposé d’emprunter des livres et d’utiliser la salle de lecture, mais l’heure n’a pas encore été confirmée.",
        "it": "Il gruppo ha discusso di una visita alla biblioteca venerdì pomeriggio. Ha proposto di prendere libri in prestito e usare la sala di lettura, ma l’orario non è ancora stato confermato.",
        "ja": "金曜日の午後に図書館を訪れる案について話し合いました。本を借りたり閲覧室を利用したりすることが提案されましたが、具体的な時間はまだ決まっておらず、予約も完了していません。",
        "ko": "금요일 오후에 도서관을 방문하는 방안을 논의했습니다. 책을 빌리고 열람실을 이용하자는 제안이 있었지만 구체적인 시간은 아직 확정되지 않았고 예약도 완료되지 않았습니다.",
        "pt": "O grupo discutiu uma visita à biblioteca na sexta-feira à tarde. Foi proposto pedir livros emprestados e utilizar a sala de leitura, mas a hora ainda não foi confirmada."
    ]
    static let titles: [String: String] = ["en":"Proposed Friday library visit", "zh-Hans":"周五图书馆参观安排", "zh-Hant":"週五圖書館參觀安排", "de":"Geplanter Bibliotheksbesuch am Freitag", "es":"Propuesta de visita a la biblioteca", "fr":"Projet de visite à la bibliothèque", "it":"Proposta di visita alla biblioteca", "ja":"金曜日の図書館訪問について", "ko":"금요일 도서관 방문 계획 논의", "pt":"Proposta de visita à biblioteca"]

    private func session(source: String = "en", target: String = "zh-Hans", title: String = "en") -> HistorySession {
        .init(id: UUID().uuidString, startedAt: Date(timeIntervalSince1970: 1_700_000_000), sourceLanguage: source, targetLanguage: target, titleLanguage: title)
    }
    private func location() -> URL { FileManager.default.temporaryDirectory.appending(path: "HoverCue-Language-Tests-\(UUID().uuidString)/history.sqlite") }

    func testAllTenLanguagesKeepSourceTargetAndTitleContractsAcrossNinetyDirections() throws {
        for source in HistoryDigestLanguagePolicy.identifiers {
            for target in HistoryDigestLanguagePolicy.identifiers where target != source {
                let saved = session(source: source, target: target, title: target)
                let draft = HistoryDigestResult(title: Self.titles[target]!, sourceSummary: Self.samples[source]!, targetSummary: Self.samples[target]!, incomplete: true)
                let checked = try HistoryDigestLanguagePolicy.normalized(draft, for: saved)
                XCTAssertEqual(checked.sourceSummary, Self.samples[source]!, "\(source) → \(target)")
                XCTAssertEqual(checked.targetSummary, Self.samples[target]!, "\(source) → \(target)")
                XCTAssertEqual(checked.title, Self.titles[target]!)
                XCTAssertTrue(checked.incomplete)
            }
        }
    }

    func testSimplifiedTitleAndBothSummariesAreRepairedBeforeSaving() throws {
        let traditional = "視窗與語音輔助已從動態島移除，圖書館與閱覽室安排仍未確定。"
        let saved = session(source: "zh-Hans", target: "zh-Hans", title: "zh-Hans")
        let checked = try HistoryDigestLanguagePolicy.normalized(.init(title: "視窗與語音輔助", sourceSummary: traditional, targetSummary: traditional), for: saved)
        XCTAssertEqual(checked.title, "视窗与语音辅助")
        XCTAssertEqual(checked.sourceSummary, "视窗与语音辅助已从动态岛移除，图书馆与阅览室安排仍未确定。")
        XCTAssertEqual(checked.targetSummary, checked.sourceSummary)
    }

    func testTraditionalTitleAndBothSummariesAreRepairedWithoutChangingLatinNames() throws {
        let simplified = "MacBook 的视窗管理与语音辅助已更新，但效果尚未确定。"
        let saved = session(source: "zh-Hant", target: "zh-Hant", title: "zh-Hant")
        let checked = try HistoryDigestLanguagePolicy.normalized(.init(title: "MacBook 视窗与语音辅助", sourceSummary: simplified, targetSummary: simplified), for: saved)
        XCTAssertEqual(checked.title, "MacBook 視窗與語音輔助")
        XCTAssertEqual(checked.sourceSummary, "MacBook 的視窗管理與語音輔助已更新，但效果尚未確定。")
        XCTAssertEqual(checked.targetSummary, checked.sourceSummary)
    }

    func testClearWrongLanguageIsRejectedForEverySummaryLanguage() {
        for expected in HistoryDigestLanguagePolicy.identifiers {
            let wrong = expected == "en" ? Self.samples["de"]! : Self.samples["en"]!
            XCTAssertThrowsError(try HistoryDigestLanguagePolicy.validateLanguage(wrong, expected: expected), expected) { error in
                guard case HistoryDigestError.state(.languageMismatch) = error else { return XCTFail("Expected a sanitized language mismatch") }
            }
        }
    }

    func testMixedEastAsianPhrasesCannotHideInsideLatinLanguageSummaries() {
        for code in ["en", "de", "es", "fr", "it", "pt"] {
            XCTAssertThrowsError(try HistoryDigestLanguagePolicy.validateLanguage(Self.samples[code]! + " 星期五下午", expected: code))
        }
    }

    func testSharedSpanishAndCatalanTitleIsNotFalselyRejected() {
        XCTAssertNoThrow(try HistoryDigestLanguagePolicy.validateLanguage("Visita a la biblioteca", expected: "es", isTitle: true))
        XCTAssertNoThrow(try HistoryDigestLanguagePolicy.validateLanguage("Visitar la biblioteca", expected: "es", isTitle: true))
        XCTAssertNoThrow(try HistoryDigestLanguagePolicy.validateLanguage("Visita à biblioteca", expected: "pt", isTitle: true))
        XCTAssertThrowsError(try HistoryDigestLanguagePolicy.validateLanguage("Planning the library visit", expected: "es", isTitle: true))
    }

    func testShortTitlesInTheWrongLanguageAreRejected() {
        for (text, code) in [("周五下午去图书馆的安排", "en"), ("圖書館週五下午安排", "en"), ("図書館訪問案", "fr"), ("도서관 방문 논의", "en"), ("Library visit", "de")] {
            XCTAssertThrowsError(try HistoryDigestLanguagePolicy.validateLanguage(text, expected: code, isTitle: true))
        }
    }

    func testNamesAcronymsNumbersAndUnicodeAccentsArePreserved() throws {
        for code in HistoryDigestLanguagePolicy.identifiers {
            XCTAssertNoThrow(try HistoryDigestLanguagePolicy.validateLanguage("MacBook Pro 2026", expected: code, isTitle: true))
        }
        for code in ["de", "es", "fr", "it", "ja", "ko", "pt"] {
            XCTAssertEqual(try HistoryDigestLanguagePolicy.normalize(Self.samples[code]!, language: code), Self.samples[code]!)
        }
        XCTAssertEqual(try HistoryDigestLanguagePolicy.normalize("  Bücher, español, français, caffè, português — MacBook 42\n", language: "en"), "Bücher, español, français, caffè, português — MacBook 42")
    }

    func testEveryLanguageMapsToTheSameAppleTranslationDirectionAndChineseScript() throws {
        for code in HistoryDigestLanguagePolicy.identifiers {
            let selection = try HistoryDigestTranslator.selection(code)
            XCTAssertEqual(selection.translationLanguage.languageCode?.identifier, Locale.Language(identifier: code).languageCode?.identifier)
            if code == "zh-Hant" { XCTAssertEqual(selection.chineseScript, .traditional) }
            if code == "zh-Hans" { XCTAssertEqual(selection.chineseScript, .simplified) }
        }
    }

    @MainActor func testChineseWritingSystemsShareSummaryFactsWithoutAnotherModelRequest() async throws {
        let simplified = try await HistoryDigestTranslator.installedTranslation(Self.samples["zh-Hant"]!, source: "zh-Hant", target: "zh-Hans")
        XCTAssertEqual(simplified, try HistoryDigestLanguagePolicy.normalize(Self.samples["zh-Hant"]!, language: "zh-Hans"))
        let traditional = try await HistoryDigestTranslator.installedTranslation(Self.samples["zh-Hans"]!, source: "zh-Hans", target: "zh-Hant")
        XCTAssertEqual(traditional, try HistoryDigestLanguagePolicy.normalize(Self.samples["zh-Hans"]!, language: "zh-Hant"))
    }

    func testUnsupportedMetadataFailsWithoutGuessingOrReadingCurrentSettings() {
        XCTAssertThrowsError(try HistoryDigestLanguagePolicy.normalize("Text", language: "invalid"))
        XCTAssertThrowsError(try HistoryDigestLanguagePolicy.normalize("中文", language: "zh"))
    }

    func testDatabaseNormalizesBeforeCommittingAndExportContainsSameWritingSystem() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = HistoryDatabase(url: url)
        let saved = session(source: "en", target: "zh-Hans", title: "zh-Hant")
        let row = HistoryEntry(sequence: 0, timestamp: saved.startedAt, source: Self.samples["en"]!)
        try await database.apply(.append(saved, row))
        try await database.setDigestState(sessionID: saved.id, state: .generating)
        try await database.saveDigest(sessionID: saved.id, result: .init(title: "图书馆阅览室安排", sourceSummary: Self.samples["en"]!, targetSummary: Self.samples["zh-Hant"]!))
        let sessions = try await database.sessions()
        XCTAssertEqual(sessions.first?.digest.title, "圖書館閱覽室安排")
        XCTAssertEqual(sessions.first?.digest.targetSummary, try HistoryDigestLanguagePolicy.normalize(Self.samples["zh-Hant"]!, language: "zh-Hans"))
        XCTAssertEqual(sessions.first?.targetLanguage, "zh-Hans")
        XCTAssertEqual(sessions.first?.titleLanguage, "zh-Hant")
        let destination = url.deletingLastPathComponent().appending(path: "public-test.txt")
        try await database.export(session: saved, to: destination, labels: ["History", "Original", "Translation", "Failed", "Incomplete", "Summary", "Incomplete", "Unavailable", "Transcript"])
        let text = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(text.contains("圖書館閱覽室安排"))
        XCTAssertTrue(text.contains("具体时间尚未确定"))
        XCTAssertFalse(text.contains("具體時間尚未確定"))
    }

    func testWrongLanguageCannotBecomeReadyEvenIfGeneratorBypassesItsOwnCheck() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = HistoryDatabase(url: url)
        let saved = session(source: "de", target: "fr", title: "fr")
        try await database.apply(.append(saved, .init(sequence: 0, timestamp: Date(), source: Self.samples["de"]!)))
        try await database.setDigestState(sessionID: saved.id, state: .generating)
        do {
            try await database.saveDigest(sessionID: saved.id, result: .init(title: Self.titles["fr"]!, sourceSummary: Self.samples["en"]!, targetSummary: Self.samples["en"]!))
            XCTFail("Wrong language must never be committed")
        } catch {}
        let sessions = try await database.sessions()
        XCTAssertNotEqual(sessions.first?.digest.state, .ready)
        XCTAssertTrue(sessions.first?.digest.sourceSummary.isEmpty == true)
    }

    func testBuild19MigrationRepairsExistingSummaryAndRetainsTranscriptAndDates() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = HistoryDatabase(url: url)
        let saved = session(source: "en", target: "zh-Hans", title: "zh-Hans")
        try await database.apply(.append(saved, .init(sequence: 0, timestamp: saved.startedAt, source: Self.samples["en"]!)))
        try await database.apply(.finish(sessionID: saved.id, date: saved.startedAt.addingTimeInterval(10)))
        try overwriteLegacyDigest(url, session: saved, source: Self.samples["en"]!, target: Self.samples["zh-Hant"]!, title: "圖書館參觀安排")
        try await database.recover(excluding: nil, titleLanguage: "ja")
        let first = try await database.sessions()
        XCTAssertEqual(first.first?.digest.title, "图书馆参观安排")
        XCTAssertEqual(first.first?.digest.state, .ready)
        XCTAssertEqual(first.first?.sourceLanguage, "en")
        XCTAssertEqual(first.first?.targetLanguage, "zh-Hans")
        XCTAssertEqual(first.first?.titleLanguage, "zh-Hans")
        XCTAssertEqual(first.first?.startedAt, saved.startedAt)
        XCTAssertEqual(first.first?.endedAt, saved.startedAt.addingTimeInterval(10))
        let page = try await database.page(sessionID: saved.id, offset: 0)
        XCTAssertEqual(page.entries.first?.source, Self.samples["en"]!)
        try await database.recover(excluding: nil, titleLanguage: "pt")
        let repeated = try await database.sessions()
        XCTAssertEqual(first, repeated)
    }

    func testLegacyWrongLanguageIsQueuedForRegenerationWithoutDeletingOldText() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = HistoryDatabase(url: url)
        let saved = session(source: "de", target: "ja", title: "de")
        try await database.apply(.append(saved, .init(sequence: 0, timestamp: saved.startedAt, source: Self.samples["de"]!)))
        try overwriteLegacyDigest(url, session: saved, source: Self.samples["en"]!, target: Self.samples["en"]!, title: Self.titles["en"]!)
        try await database.recover(excluding: nil, titleLanguage: "en")
        let sessions = try await database.sessions()
        XCTAssertEqual(sessions.first?.digest.state, .pending)
        XCTAssertEqual(sessions.first?.digest.sourceSummary, Self.samples["en"]!)
        XCTAssertEqual(sessions.first?.entryCount, 1)
    }

    private func overwriteLegacyDigest(_ url: URL, session: HistorySession, source: String, target: String, title: String) throws {
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK); defer { sqlite3_close(db) }
        // Recreate the exact Build 19 table, without the new language_version column.
        XCTAssertEqual(sqlite3_exec(db, "ALTER TABLE digests DROP COLUMN language_version", nil, nil, nil), SQLITE_OK)
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "UPDATE digests SET status='ready', title=?, source_summary=?, target_summary=? WHERE session=?", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        for (index,value) in [title,source,target,session.id].enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }
}

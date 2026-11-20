import Foundation
import SQLite3

struct HistorySession: Identifiable, Equatable, Sendable {
    let id: String
    let startedAt: Date
    let sourceLanguage: String
    let targetLanguage: String
    var endedAt: Date? = nil
    var entryCount: Int = 0
    var titleLanguage: String = "en"
    var digest: HistoryDigest = .init()
    /// Nil identifies a pre-level summary; never relabel it as a new profile.
    var summaryLevel: HistorySummaryLevel? = nil
    var initialSummaryLevel: HistorySummaryLevel? = nil
    var variants: [HistorySummaryLevel: HistoryDigest] = [:]
    var legacyDigest: HistoryDigest = .init()
    var lastReadyLevel: HistorySummaryLevel? = nil

    var digestJobKey: String { id + ":" + (summaryLevel?.rawValue ?? "legacy") }
    var stableTitle: String { (digest.state == .ready || legacyDigest.state == .ready || lastReadyLevel != nil) ? digest.title : "" }
    var displayedSummary: (level: HistorySummaryLevel?, digest: HistoryDigest)? {
        if digest.state == .ready { return (summaryLevel, digest) }
        if let lastReadyLevel, let saved = variants[lastReadyLevel], saved.state == .ready { return (lastReadyLevel, saved) }
        if legacyDigest.state == .ready { return (nil, legacyDigest) }
        return nil
    }
}

struct HistoryEntry: Identifiable, Equatable, Sendable {
    enum State: String, Sendable { case pending, translated, failed, interrupted }
    var id: Int { sequence }
    let sequence: Int
    let timestamp: Date
    let source: String
    var translation: String?
    var state: State = .pending
}

struct HistoryPage: Sendable {
    var entries: [HistoryEntry] = []
    var hasMore = false
}

enum HistoryFailure: Error {
    case storage, limit, invalidContent
    var messageKey: String {
        switch self {
        case .storage: "History could not be saved. Recording has stopped; live captions continue."
        case .limit: "History reached its safety limit. Recording has stopped. Delete older history to free space."
        case .invalidContent: "A history entry exceeded its safety limit. Recording has stopped."
        }
    }
}

enum HistoryMutation: Sendable {
    case append(HistorySession, HistoryEntry)
    case translate(sessionID: String, sequence: Int, text: String?)
    case finish(sessionID: String, date: Date)
    case delete(sessionID: String)
    case clear
}

/// Apple's SQLite runs on this actor, away from capture and the main actor.
/// Readers never create the directory/database. All writes use bound parameters.
actor HistoryDatabase {
    struct Limits: Sendable {
        var maximumBytes = 100 * 1_024 * 1_024
        var maximumSessions = 1_000
        var maximumEntries = 100_000
        var maximumTextBytes = 16 * 1_024
        var maximumExportBytes = 128 * 1_024 * 1_024
    }

    static let pageSize = 100
    let url: URL
    let limits: Limits

    init(url: URL, limits: Limits = Limits()) {
        self.url = url
        self.limits = limits
    }

    func apply(_ mutation: HistoryMutation) throws {
        let createsDatabase: Bool
        if case .append = mutation { createsDatabase = true } else { createsDatabase = false }
        guard createsDatabase || FileManager.default.fileExists(atPath: url.path) else { return }
        try access(write: true) { db in
            try execute(db, "BEGIN IMMEDIATE")
            do {
                switch mutation {
                case .append(let session, let entry):
                    try validate(entry.source)
                    let exists = try scalar(db, "SELECT count(*) FROM sessions WHERE id = ?", [.text(session.id)]) > 0
                    if !exists {
                        guard try scalar(db, "SELECT count(*) FROM sessions") < limits.maximumSessions else { throw HistoryFailure.limit }
                        try execute(db, "INSERT INTO sessions(id, started, source, target) VALUES(?, ?, ?, ?)", [
                            .text(session.id), .real(session.startedAt.timeIntervalSince1970),
                            .text(session.sourceLanguage), .text(session.targetLanguage)
                        ])
                    }
                    try execute(db, "INSERT OR IGNORE INTO digests(session, title_language, status) VALUES(?, ?, 'pending')", [.text(session.id), .text(session.titleLanguage)])
                    if !exists, let level = session.summaryLevel {
                        try execute(db, "UPDATE digests SET selected_level = ?, initial_level = ? WHERE session = ?", [.text(level.rawValue), .text(level.rawValue), .text(session.id)])
                        try insertVariant(db, sessionID: session.id, level: level)
                    }
                    // Duplicate recognition callbacks cannot create duplicate rows.
                    let duplicate = try scalar(db, "SELECT count(*) FROM entries WHERE session = ? AND sequence = ?", [.text(session.id), .integer(entry.sequence)]) > 0
                    if !duplicate {
                        guard try scalar(db, "SELECT count(*) FROM entries WHERE session = ?", [.text(session.id)]) < limits.maximumEntries else { throw HistoryFailure.limit }
                        try execute(db, "INSERT INTO entries(session, sequence, timestamp, original, state) VALUES(?, ?, ?, ?, 'pending')", [
                            .text(session.id), .integer(entry.sequence), .real(entry.timestamp.timeIntervalSince1970), .text(entry.source)
                        ])
                    }
                case .translate(let id, let sequence, let text):
                    if let text { try validate(text) }
                    try execute(db, "UPDATE entries SET translation = ?, state = ? WHERE session = ? AND sequence = ? AND state = 'pending'", [
                        text.map(Value.text) ?? .null, .text(text == nil ? "failed" : "translated"), .text(id), .integer(sequence)
                    ])
                case .finish(let id, let date):
                    try execute(db, "UPDATE sessions SET ended = ? WHERE id = ?", [.real(date.timeIntervalSince1970), .text(id)])
                    try execute(db, "UPDATE entries SET state = 'interrupted' WHERE session = ? AND state = 'pending'", [.text(id)])
                case .delete(let id):
                    try execute(db, "DELETE FROM sessions WHERE id = ?", [.text(id)])
                case .clear:
                    try execute(db, "DELETE FROM sessions")
                }
                try execute(db, "COMMIT")
            } catch {
                try? execute(db, "ROLLBACK")
                throw error
            }
            if case .clear = mutation { try execute(db, "VACUUM") }
        }
    }

    func sessions() throws -> [HistorySession] {
        try Task.checkCancellation()
        return try catalogAfterDigest()
    }

    func catalogAfterDigest() throws -> [HistorySession] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try access(write: false) { db in
            let hasDigests = try scalar(db, "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'digests'") > 0
            let hasLevels = hasDigests ? try scalar(db, "SELECT count(*) FROM pragma_table_info('digests') WHERE name = 'selected_level'") > 0 : false
            let fields = hasDigests ? ", d.title_language, d.status, d.title, d.source_summary, d.target_summary, d.incomplete" + (hasLevels ? ", d.selected_level, d.initial_level, d.last_ready_level" : "") : ""
            let join = hasDigests ? " LEFT JOIN digests d ON d.session = s.id" : ""
            let statement = try prepare(db, "SELECT s.id, s.started, s.source, s.target, s.ended, count(e.sequence)\(fields) FROM sessions s LEFT JOIN entries e ON e.session = s.id\(join) GROUP BY s.id ORDER BY s.started DESC LIMIT ?", [.integer(limits.maximumSessions)])
            defer { sqlite3_finalize(statement) }
            var result: [HistorySession] = []
            while try step(statement) {
                result.append(HistorySession(
                    id: string(statement, 0), startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    sourceLanguage: string(statement, 2), targetLanguage: string(statement, 3),
                    endedAt: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                    entryCount: Int(sqlite3_column_int64(statement, 5)),
                    titleLanguage: hasDigests ? string(statement, 6) : "en",
                    digest: hasDigests ? HistoryDigest(state: HistoryDigestState(rawValue: string(statement, 7)) ?? .pending,
                        title: string(statement, 8), sourceSummary: string(statement, 9), targetSummary: string(statement, 10),
                        incomplete: sqlite3_column_int(statement, 11) != 0) : .init()
                ))
                if hasLevels {
                    let index = result.count - 1
                    result[index].summaryLevel = HistorySummaryLevel(rawValue: string(statement, 12))
                    result[index].initialSummaryLevel = HistorySummaryLevel(rawValue: string(statement, 13))
                    result[index].lastReadyLevel = HistorySummaryLevel(rawValue: string(statement, 14))
                    result[index].legacyDigest = result[index].digest
                    let variants = try prepare(db, "SELECT level, status, source_summary, target_summary, incomplete FROM digest_variants WHERE session = ? AND profile_version = ? LIMIT 3", [.text(result[index].id), .integer(HistorySummaryLevel.version)])
                    defer { sqlite3_finalize(variants) }
                    while try step(variants) {
                        guard let level = HistorySummaryLevel(rawValue: string(variants, 0)) else { continue }
                        result[index].variants[level] = .init(state: HistoryDigestState(rawValue: string(variants, 1)) ?? .pending, title: result[index].digest.title, sourceSummary: string(variants, 2), targetSummary: string(variants, 3), incomplete: sqlite3_column_int(variants, 4) != 0)
                    }
                    if let level = result[index].summaryLevel {
                        result[index].digest = result[index].variants[level] ?? .init(title: result[index].digest.title)
                    }
                }
            }
            return result
        }
    }

    /// Migrate existing text only; never create a database while history is off.
    /// A session left open by a previous process is closed at its last saved entry.
    func recover(excluding activeID: String?, titleLanguage: String) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try access(write: true) { db in
            try execute(db, "BEGIN IMMEDIATE")
            do {
                try execute(db, "INSERT OR IGNORE INTO digests(session, title_language, status) SELECT id, ?, 'pending' FROM sessions", [.text(titleLanguage)])
                try execute(db, "UPDATE sessions SET ended = COALESCE((SELECT max(timestamp) FROM entries WHERE session = sessions.id), started) WHERE ended IS NULL AND id != ?", [.text(activeID ?? "")])
                try execute(db, "UPDATE entries SET state = 'interrupted' WHERE state = 'pending' AND session IN (SELECT id FROM sessions WHERE ended IS NOT NULL)")
                try execute(db, "UPDATE digests SET status = 'pending' WHERE status = 'generating'")
                try execute(db, "UPDATE digest_variants SET status = 'pending' WHERE status = 'generating'")
                try repairDigestLanguages(db)
                try execute(db, "PRAGMA user_version = 4")
                try execute(db, "COMMIT")
            } catch { try? execute(db, "ROLLBACK"); throw error }
        }
    }

    func setDigestState(sessionID: String, state: HistoryDigestState, level: HistorySummaryLevel? = nil) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try access(write: true) { db in
            if let level {
                try execute(db, "UPDATE digest_variants SET status = ? WHERE session = ? AND level = ? AND status != 'ready'", [.text(state.rawValue), .text(sessionID), .text(level.rawValue)])
            } else {
                try execute(db, "UPDATE digests SET status = ? WHERE session = ? AND status != 'ready'", [.text(state.rawValue), .text(sessionID)])
            }
        }
    }

    /// One UPDATE commits the title and both languages together. It never inserts
    /// sessions, so a deleted row cannot be recreated by a delayed model response.
    func saveDigest(sessionID: String, result: HistoryDigestResult, level: HistorySummaryLevel? = nil) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try result.validate()
        try access(write: true) { db in
            if let level {
                try saveVariant(db, sessionID: sessionID, level: level, result: result)
                return
            }
            let metadata = try prepare(db, "SELECT s.started, s.source, s.target, d.title_language FROM sessions s JOIN digests d ON d.session = s.id WHERE s.id = ? AND d.status = 'generating'", [.text(sessionID)])
            defer { sqlite3_finalize(metadata) }
            guard try step(metadata) else { return }
            let session = HistorySession(id: sessionID, startedAt: Date(timeIntervalSince1970: sqlite3_column_double(metadata, 0)), sourceLanguage: string(metadata, 1), targetLanguage: string(metadata, 2), titleLanguage: string(metadata, 3))
            let checked = try HistoryDigestLanguagePolicy.normalized(result, for: session)
            try execute(db, "UPDATE digests SET title = ?, source_summary = ?, target_summary = ?, incomplete = ?, status = 'ready', language_version = ? WHERE session = ? AND status = 'generating'", [
                .text(checked.title), .text(checked.sourceSummary), .text(checked.targetSummary), .integer(checked.incomplete ? 1 : 0), .integer(HistoryDigestLanguagePolicy.version), .text(sessionID)
            ])
        }
    }

    func selectSummaryLevel(sessionID: String, level: HistorySummaryLevel?) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try access(write: true) { db in
            try execute(db, "BEGIN IMMEDIATE")
            do {
                guard try scalar(db, "SELECT count(*) FROM sessions WHERE id = ?", [.text(sessionID)]) == 1 else {
                    try execute(db, "COMMIT"); return
                }
                try execute(db, "UPDATE digests SET selected_level = ? WHERE session = ?", [level.map { .text($0.rawValue) } ?? .null, .text(sessionID)])
                if let level { try insertVariant(db, sessionID: sessionID, level: level) }
                try execute(db, "COMMIT")
            } catch { try? execute(db, "ROLLBACK"); throw error }
        }
    }

    private func insertVariant(_ db: OpaquePointer, sessionID: String, level: HistorySummaryLevel) throws {
        try execute(db, "INSERT INTO digest_variants(session, level, profile_version, status) VALUES(?, ?, ?, 'pending') ON CONFLICT(session, level) DO UPDATE SET profile_version = excluded.profile_version, status = 'pending', source_summary = NULL, target_summary = NULL WHERE digest_variants.profile_version != excluded.profile_version", [.text(sessionID), .text(level.rawValue), .integer(HistorySummaryLevel.version)])
    }

    private func saveVariant(_ db: OpaquePointer, sessionID: String, level: HistorySummaryLevel, result: HistoryDigestResult) throws {
        try execute(db, "BEGIN IMMEDIATE")
        do {
            let metadata = try prepare(db, "SELECT s.started, s.source, s.target, d.title_language, d.title FROM sessions s JOIN digests d ON d.session = s.id JOIN digest_variants v ON v.session = s.id WHERE s.id = ? AND d.selected_level = ? AND v.level = ? AND v.status = 'generating' AND v.profile_version = ?", [.text(sessionID), .text(level.rawValue), .text(level.rawValue), .integer(HistorySummaryLevel.version)])
            defer { sqlite3_finalize(metadata) }
            if try step(metadata) {
                let session = HistorySession(id: sessionID, startedAt: Date(timeIntervalSince1970: sqlite3_column_double(metadata, 0)), sourceLanguage: string(metadata, 1), targetLanguage: string(metadata, 2), titleLanguage: string(metadata, 3))
                let checked = try HistoryDigestLanguagePolicy.normalized(result, for: session)
                try execute(db, "UPDATE digest_variants SET source_summary = ?, target_summary = ?, incomplete = ?, status = 'ready' WHERE session = ? AND level = ?", [.text(checked.sourceSummary), .text(checked.targetSummary), .integer(checked.incomplete ? 1 : 0), .text(sessionID), .text(level.rawValue)])
                try execute(db, "UPDATE digests SET title = CASE WHEN title IS NULL OR title = '' OR (status != 'ready' AND last_ready_level IS NULL) THEN ? ELSE title END, last_ready_level = ? WHERE session = ?", [.text(checked.title), .text(level.rawValue), .text(sessionID)])
            }
            try execute(db, "COMMIT")
        } catch { try? execute(db, "ROLLBACK"); throw error }
    }

    /// Repair already-saved Build 19 summaries in the same recovery transaction.
    /// Text entries, language metadata and dates are untouched. Wrong-language
    /// summaries remain stored but hidden until the normal bounded queue replaces them.
    private func repairDigestLanguages(_ db: OpaquePointer) throws {
        let rows = try prepare(db, "SELECT s.id, s.started, s.source, s.target, d.title_language, d.title, d.source_summary, d.target_summary, d.incomplete FROM sessions s JOIN digests d ON d.session = s.id WHERE d.status = 'ready' AND d.language_version < ? LIMIT ?", [.integer(HistoryDigestLanguagePolicy.version), .integer(limits.maximumSessions)])
        defer { sqlite3_finalize(rows) }
        while try step(rows) {
            let session = HistorySession(id: string(rows, 0), startedAt: Date(timeIntervalSince1970: sqlite3_column_double(rows, 1)), sourceLanguage: string(rows, 2), targetLanguage: string(rows, 3), titleLanguage: string(rows, 4))
            let existing = HistoryDigestResult(title: string(rows, 5), sourceSummary: string(rows, 6), targetSummary: string(rows, 7), incomplete: sqlite3_column_int(rows, 8) != 0)
            let checked: HistoryDigestResult
            do { checked = try HistoryDigestLanguagePolicy.normalized(existing, for: session) }
            catch {
                try execute(db, "UPDATE digests SET status = 'pending', language_version = ? WHERE session = ?", [.integer(HistoryDigestLanguagePolicy.version), .text(session.id)])
                continue
            }
            try execute(db, "UPDATE digests SET title = ?, source_summary = ?, target_summary = ?, language_version = ? WHERE session = ?", [.text(checked.title), .text(checked.sourceSummary), .text(checked.targetSummary), .integer(HistoryDigestLanguagePolicy.version), .text(session.id)])
        }
    }

    func page(sessionID: String, offset: Int) throws -> HistoryPage {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: url.path) else { return HistoryPage() }
        return try access(write: false) { db in
            let statement = try prepare(db, "SELECT sequence, timestamp, original, translation, state FROM entries WHERE session = ? ORDER BY sequence LIMIT ? OFFSET ?", [.text(sessionID), .integer(Self.pageSize + 1), .integer(max(0, min(offset, limits.maximumEntries)))])
            defer { sqlite3_finalize(statement) }
            var result = HistoryPage()
            while try step(statement) {
                result.entries.append(entry(statement))
            }
            result.hasMore = result.entries.count > Self.pageSize
            if result.hasMore { result.entries.removeLast() }
            return result
        }
    }

    /// The serial actor and read transaction provide a consistent export snapshot.
    /// Output is bounded and is written atomically only after NSSavePanel confirms.
    func export(session: HistorySession, to destination: URL, labels: [String]) throws {
        try access(write: false) { db in
            guard [5, 9, 11].contains(labels.count) else { throw HistoryFailure.storage }
            try execute(db, "BEGIN")
            defer { try? execute(db, "ROLLBACK") }
            guard try scalar(db, "SELECT count(*) FROM sessions WHERE id = ?", [.text(session.id)]) == 1 else { throw HistoryFailure.storage }
            let formatter = ISO8601DateFormatter()
            var data = Data()
            func append(_ text: String) throws {
                let bytes = Data(text.utf8)
                guard bytes.count <= limits.maximumExportBytes - data.count else { throw HistoryFailure.limit }
                data.append(bytes)
            }
            try append("HoverCue — \(labels[0])\n\(formatter.string(from: session.startedAt))\n\(session.sourceLanguage) → \(session.targetLanguage)\n\n")
            if labels.count >= 9, try scalar(db, "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'digests'") > 0 {
                if labels.count == 11 { try append("\(labels[9]): \(labels[10])\n\n") }
                let digest: OpaquePointer
                if let level = session.summaryLevel {
                    digest = try prepare(db, "SELECT v.status, d.title, v.source_summary, v.target_summary, v.incomplete FROM digest_variants v JOIN digests d ON d.session = v.session WHERE v.session = ? AND v.level = ? AND v.profile_version = ?", [.text(session.id), .text(level.rawValue), .integer(HistorySummaryLevel.version)])
                } else {
                    digest = try prepare(db, "SELECT status, title, source_summary, target_summary, incomplete FROM digests WHERE session = ?", [.text(session.id)])
                }
                defer { sqlite3_finalize(digest) }
                let hasDigest = try step(digest)
                if hasDigest, string(digest, 0) == "ready" || !session.stableTitle.isEmpty {
                    try append("\(string(digest, 1))\n\n")
                }
                if hasDigest, string(digest, 0) == "ready" {
                    try append("\(labels[5]) (\(session.sourceLanguage)):\n\(string(digest, 2))\n\n\(labels[5]) (\(session.targetLanguage)):\n\(string(digest, 3))\n\n")
                    if sqlite3_column_int(digest, 4) != 0 { try append("\(labels[6])\n\n") }
                } else { try append("\(labels[7])\n\n") }
                try append("\(labels[8])\n\n")
            }
            let statement = try prepare(db, "SELECT sequence, timestamp, original, translation, state FROM entries WHERE session = ? ORDER BY sequence", [.text(session.id)])
            defer { sqlite3_finalize(statement) }
            while try step(statement) {
                let row = entry(statement)
                let translated = row.translation ?? (row.state == .failed ? labels[3] : labels[4])
                try append("[\(formatter.string(from: row.timestamp))]\n\(labels[1]): \(row.source)\n\(labels[2]): \(translated)\n\n")
            }
            try data.write(to: destination, options: .atomic)
        }
    }

    private enum Value { case text(String), integer(Int), real(Double), null }

    private func validate(_ text: String) throws {
        guard text.utf8.count <= limits.maximumTextBytes else { throw HistoryFailure.invalidContent }
    }

    private func access<T>(write: Bool, _ body: (OpaquePointer) throws -> T) throws -> T {
        if write {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var excludedURL = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try excludedURL.setResourceValues(values)
        }
        var handle: OpaquePointer?
        let flags = write ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            throw HistoryFailure.storage
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1_000)
        if write {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try execute(db, "PRAGMA foreign_keys = ON")
            try execute(db, "PRAGMA secure_delete = ON")
            let pageSize = try scalar(db, "PRAGMA page_size")
            try execute(db, "PRAGMA max_page_count = \(max(4, limits.maximumBytes / max(1, pageSize)))")
            try execute(db, "CREATE TABLE IF NOT EXISTS sessions(id TEXT PRIMARY KEY, started REAL NOT NULL, source TEXT NOT NULL, target TEXT NOT NULL, ended REAL)")
            try execute(db, "CREATE TABLE IF NOT EXISTS entries(session TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, sequence INTEGER NOT NULL, timestamp REAL NOT NULL, original TEXT NOT NULL, translation TEXT, state TEXT NOT NULL, PRIMARY KEY(session, sequence))")
            try execute(db, "CREATE TABLE IF NOT EXISTS digests(session TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE, title_language TEXT NOT NULL, status TEXT NOT NULL, title TEXT, source_summary TEXT, target_summary TEXT, incomplete INTEGER NOT NULL DEFAULT 0, language_version INTEGER NOT NULL DEFAULT 0)")
            if try scalar(db, "SELECT count(*) FROM pragma_table_info('digests') WHERE name = 'language_version'") == 0 {
                try execute(db, "ALTER TABLE digests ADD COLUMN language_version INTEGER NOT NULL DEFAULT 0")
            }
            for column in ["selected_level", "initial_level", "last_ready_level"] {
                if try scalar(db, "SELECT count(*) FROM pragma_table_info('digests') WHERE name = ?", [.text(column)]) == 0 {
                    try execute(db, "ALTER TABLE digests ADD COLUMN \(column) TEXT")
                }
            }
            try execute(db, "CREATE TABLE IF NOT EXISTS digest_variants(session TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, level TEXT NOT NULL CHECK(level IN ('concise','standard','detailed')), profile_version INTEGER NOT NULL, status TEXT NOT NULL, source_summary TEXT, target_summary TEXT, incomplete INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(session, level))")
        }
        return try body(db)
    }

    private func prepare(_ db: OpaquePointer, _ sql: String, _ values: [Value] = []) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw HistoryFailure.storage }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .text(let text): status = sqlite3_bind_text(statement, index, text, Int32(text.utf8.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .integer(let number): status = sqlite3_bind_int64(statement, index, Int64(number))
            case .real(let number): status = sqlite3_bind_double(statement, index, number)
            case .null: status = sqlite3_bind_null(statement, index)
            }
            if status != SQLITE_OK { sqlite3_finalize(statement); throw HistoryFailure.storage }
        }
        return statement
    }

    private func execute(_ db: OpaquePointer, _ sql: String, _ values: [Value] = []) throws {
        let statement = try prepare(db, sql, values)
        defer { sqlite3_finalize(statement) }
        while try step(statement) { }
    }

    private func scalar(_ db: OpaquePointer, _ sql: String, _ values: [Value] = []) throws -> Int {
        let statement = try prepare(db, sql, values)
        defer { sqlite3_finalize(statement) }
        return try step(statement) ? Int(sqlite3_column_int64(statement, 0)) : 0
    }

    private func step(_ statement: OpaquePointer) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        case SQLITE_FULL: throw HistoryFailure.limit
        default: throw HistoryFailure.storage
        }
    }

    private func string(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, index) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, index))), as: UTF8.self)
    }

    private func entry(_ statement: OpaquePointer) -> HistoryEntry {
        HistoryEntry(sequence: Int(sqlite3_column_int64(statement, 0)), timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)), source: string(statement, 2), translation: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : string(statement, 3), state: HistoryEntry.State(rawValue: string(statement, 4)) ?? .interrupted)
    }
}

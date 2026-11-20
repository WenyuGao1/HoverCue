import Foundation

enum HistorySummaryLevel: String, CaseIterable, Identifiable, Sendable {
    case concise, standard, detailed
    var id: String { rawValue }
    static let version = 1
    var titleKey: String {
        switch self { case .concise: "Concise"; case .standard: "Standard"; case .detailed: "Detailed" }
    }
    var descriptionKey: String {
        switch self {
        case .concise: "Main topic and core conclusions, in a short summary."
        case .standard: "Overview, key points, reasons, decisions and open questions."
        case .detailed: "More context by topic, including stated reasons, differences, figures and next steps."
        }
    }
    var maximumSections: Int {
        switch self { case .concise: 1; case .standard: 3; case .detailed: 6 }
    }
    var responseTokens: Int {
        switch self { case .concise: 500; case .standard: 1_800; case .detailed: 3_600 }
    }
    var instructions: String {
        switch self {
        case .concise:
            "Give only the main subject and core conclusions. Use one short paragraph, or at most three short points. Omit secondary discussion."
        case .standard:
            "Give a brief overview, then key points and their main reasons. Include explicitly confirmed decisions and unresolved questions when present. Use short paragraphs or clear points."
        case .detailed:
            "Organize the discussion by topic. Preserve useful context, stated reasoning, alternatives and differences of opinion, important names, figures, dates and qualifications. Distinguish proposals, confirmed decisions and open questions. Include next steps, owners and deadlines ONLY if explicitly stated. Use clear paragraphs or points with brief topic headings."
        }
    }
}

/// No private text is included in errors or diagnostic logs.
enum HistoryDigestState: String, Sendable {
    case pending, generating, ready, deviceNotEligible, intelligenceDisabled, modelNotReady, unsupportedLanguage, failed, insufficient, languageMismatch

    var messageKey: String {
        switch self {
        case .pending: "Summary queued. It will run when live captions are stopped."
        case .generating: "Creating a title and bilingual summary on this Mac…"
        case .ready: "AI-generated summary. Check important details against the full transcript."
        case .deviceNotEligible: "This Mac does not support the local Apple Intelligence model. Your full history is available."
        case .intelligenceDisabled: "Enable Apple Intelligence in System Settings to create local summaries. Your full history is available."
        case .modelNotReady: "Apple’s local model is not ready. Summaries will retry when it becomes available."
        case .unsupportedLanguage: "Apple’s local model does not support this session’s languages. Your full history is available."
        case .failed: "A summary could not be created. It will retry after the next app launch. Your full history is available."
        case .languageMismatch: "The AI summary did not match the selected languages and was not displayed. It will retry after the next app launch. Your full history is available."
        case .insufficient: "There is not enough meaningful text to summarize. Your full history is available."
        }
    }
}

struct HistoryDigest: Equatable, Sendable {
    var state: HistoryDigestState = .pending
    var title = ""
    var sourceSummary = ""
    var targetSummary = ""
    var incomplete = false
}

struct HistoryDigestResult: Sendable {
    let title: String
    let sourceSummary: String
    let targetSummary: String
    var incomplete = false

    func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 120, !title.contains(where: \.isNewline),
              !sourceSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !targetSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              sourceSummary.utf8.count <= 16_384, targetSummary.utf8.count <= 16_384 else {
            throw HistoryDigestError.state(.failed)
        }
    }
}

enum HistoryDigestError: Error { case state(HistoryDigestState) }

typealias HistoryPageLoader = @Sendable (Int) async throws -> HistoryPage
protocol HistoryDigestGenerating: Sendable {
    func availability(for session: HistorySession) async -> HistoryDigestState
    func generate(for session: HistorySession, loadPage: HistoryPageLoader) async throws -> HistoryDigestResult
}

/// Split on Character boundaries. UTF-8 bytes conservatively bound token usage,
/// including Chinese, emoji and text without whitespace; no middle text is dropped.
enum HistoryDigestText {
    /// Prefer paragraph, sentence or word boundaries for model requests. Joining
    /// the pieces is lossless, including when a single word/grapheme is oversized.
    static func requestChunks(_ text: String, maximumBytes: Int) -> [String] {
        var remaining = text[...]
        var result: [String] = []
        while remaining.utf8.count > maximumBytes {
            var bytes = 0
            var end = remaining.startIndex
            var preferred: String.Index?
            for index in remaining.indices {
                let character = remaining[index]
                let size = String(character).utf8.count
                if bytes + size > maximumBytes { break }
                bytes += size
                end = remaining.index(after: index)
                if bytes >= maximumBytes / 2, character.isWhitespace || ".!?。！？".contains(character) { preferred = end }
            }
            guard end != remaining.startIndex else { return result + chunks(String(remaining), maximumBytes: maximumBytes) }
            let split = preferred ?? end
            result.append(String(remaining[..<split]))
            remaining = remaining[split...]
        }
        if !remaining.isEmpty { result.append(String(remaining)) }
        return result
    }

    static func chunks(_ text: String, maximumBytes: Int) -> [String] {
        var result: [String] = []
        var current = ""
        var size = 0
        for character in text {
            let next = String(character)
            let count = next.utf8.count
            // A single extended grapheme can be enormous. Split its Unicode scalars
            // without replacing or losing bytes when it exceeds the chunk budget.
            if count > maximumBytes {
                if !current.isEmpty { result.append(current); current = ""; size = 0 }
                var scalars = ""
                var scalarBytes = 0
                for scalar in next.unicodeScalars {
                    let unit = String(scalar)
                    if scalarBytes + unit.utf8.count > maximumBytes, !scalars.isEmpty {
                        result.append(scalars); scalars = ""; scalarBytes = 0
                    }
                    scalars += unit; scalarBytes += unit.utf8.count
                }
                current = scalars; size = scalarBytes
            } else {
                if size + count > maximumBytes, !current.isEmpty { result.append(current); current = ""; size = 0 }
                current += next; size += count
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func exportFilename(_ session: HistorySession) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\\\:?*\"<>|\n\r\t").union(.controlCharacters)
        let clean = session.digest.title.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: " ")
        let title = String(clean.trimmingCharacters(in: .whitespacesAndNewlines).prefix(72))
        let date = session.startedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "HoverCue-\(date)-\(title.isEmpty ? String(session.id.prefix(8)) : title).txt"
    }
}

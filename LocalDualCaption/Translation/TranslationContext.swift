import Foundation
import NaturalLanguage

struct TranslationContextSnapshot: Equatable, Sendable {
    var precedingSources: [String] = []
    var enqueuedAt: TimeInterval = 0
}

/// Source text only, held in memory. Snapshots never include a later sentence.
struct TranslationContextWindow: Sendable {
    static let maximumEntries = 4
    static let maximumBytes = 1_600
    static let maximumEntryBytes = 600
    static let maximumAge: TimeInterval = 30
    private struct Entry: Sendable { let sequence: Int; let text: String; let time: TimeInterval }
    private var entries: [Entry] = []
    private var generation: Int?

    mutating func reset() { entries.removeAll(keepingCapacity: false); generation = nil }

    mutating func snapshotAndAppend(_ work: TranslationWorkItem, now: TimeInterval) -> TranslationContextSnapshot {
        if generation != work.generation { reset(); generation = work.generation }
        entries.removeAll { $0.sequence >= work.sequence || now < $0.time || now - $0.time > Self.maximumAge }
        let snapshot = TranslationContextSnapshot(precedingSources: entries.map(\.text), enqueuedAt: now)
        let text = Self.prefix(work.text, maximumBytes: Self.maximumEntryBytes)
        if !text.isEmpty { entries.append(Entry(sequence: work.sequence, text: text, time: now)) }
        while entries.count > Self.maximumEntries || entries.reduce(0, { $0 + $1.text.utf8.count }) > Self.maximumBytes {
            entries.removeFirst()
        }
        return snapshot
    }

    static func prefix(_ text: String, maximumBytes: Int) -> String {
        var bytes = 0
        return String(text.prefix { character in
            let count = String(character).utf8.count
            guard bytes + count <= maximumBytes else { return false }
            bytes += count
            return true
        })
    }
}

enum ContextualTranslationError: Error, Equatable {
    case unavailable, invalidOutput, inputLimit, timeout, busy
}

/// Conservative rejection only; it does not claim to prove semantic accuracy.
enum ContextualTranslationValidation {
    static func validate(_ text: String, source: String, target: CaptionLanguageSelection) throws -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.utf8.count <= min(16_384, max(512, source.utf8.count * 10)),
              !clean.contains("```"), !clean.contains("<current_source>"),
              numbers(in: clean) == numbers(in: source),
              ContextualTranslationFacts.detectedWeekdays(in: clean) == ContextualTranslationFacts.detectedWeekdays(in: source)
        else { throw ContextualTranslationError.invalidOutput }
        let letters = clean.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let han = clean.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) }.count
        let kana = clean.unicodeScalars.filter { (0x3040...0x30FF).contains($0.value) }.count
        let hangul = clean.unicodeScalars.filter { (0xAC00...0xD7AF).contains($0.value) }.count
        switch target.language {
        case .chinese where letters >= 12 && han == 0,
             .japanese where letters >= 12 && han + kana == 0,
             .korean where letters >= 12 && hangul == 0:
            throw ContextualTranslationError.invalidOutput
        case .english, .german, .spanish, .french, .italian, .portuguese:
            if han + kana + hangul >= 5 { throw ContextualTranslationError.invalidOutput }
        default: break
        }
        if letters >= 20 {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(clean)
            let hypotheses = recognizer.languageHypotheses(withMaximum: 10)
            let expected = target.language.languageCode
            if let language = recognizer.dominantLanguage,
               hypotheses[language, default: 0] >= 0.95,
               Locale.Language(identifier: language.rawValue).languageCode?.identifier != expected,
               hypotheses.filter({ Locale.Language(identifier: $0.key.rawValue).languageCode?.identifier == expected }).values.reduce(0, +) < 0.05 {
                throw ContextualTranslationError.invalidOutput
            }
        }
        return clean
    }

    private static func numbers(in text: String) -> [String: Int] {
        let folded = text.folding(options: .widthInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "−", with: "-")
        let expression = try! NSRegularExpression(pattern: "(?<![0-9])[+-]?[0-9]+(?:[.,][0-9]+)*")
        let range = NSRange(folded.startIndex..<folded.endIndex, in: folded)
        var result: [String: Int] = [:]
        for match in expression.matches(in: folded, range: range) {
            guard let range = Range(match.range, in: folded) else { continue }
            let raw = String(folded[range])
            let sign = raw.hasPrefix("-") ? "-" : ""
            let token = raw.hasPrefix("-") || raw.hasPrefix("+") ? String(raw.dropFirst()) : raw
            let groups = token.split(whereSeparator: { $0 == "," || $0 == "." })
            let normalized: String
            if groups.count > 1, groups.dropFirst().allSatisfy({ $0.count == 3 }) {
                normalized = groups.joined()
            } else if let last = token.lastIndex(where: { $0 == "," || $0 == "." }) {
                normalized = token[..<last].filter(\.isNumber) + "." + token[token.index(after: last)...]
            } else { normalized = token }
            let key = Decimal(string: sign + normalized, locale: Locale(identifier: "en_US_POSIX"))?.description ?? (sign + normalized)
            result[key, default: 0] += 1
        }
        return result
    }
}

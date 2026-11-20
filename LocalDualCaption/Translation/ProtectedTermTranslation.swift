import Foundation
import Translation

/// All markers and translated content are transient and bounded to one sentence.
/// Exact marker validation avoids relying on the model's approximate attribute ranges.
@available(macOS 26.4, *)
struct ProtectedTermTranslation {
    struct Term {
        let marker: String
        let output: String
        let original: String
    }
    static let maximumOccurrences = 128
    let input: AttributedString
    let terms: [Term]
    private let markerPrefix: String

    init(text: String, rules: [TranslationTermRule], compactMarkers: Bool = false) throws {
        guard text.utf16.count <= 64_000 else { throw TranslationServiceError.terminologySafetyLimit }
        if compactMarkers {
            var prefix = "[[HT:"
            for _ in 0..<8 where text.contains(prefix) { prefix += "_" }
            guard !text.contains(prefix) else { throw TranslationServiceError.terminologySafetyLimit }
            markerPrefix = prefix
        } else {
            markerPrefix = "[[HC_" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + "_"
        }
        let rules = Array(rules.prefix(ParsedTranslationTerms.maximumEntriesPerBox * 2))
        var input = AttributedString()
        var terms: [Term] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            var best: (range: Range<String.Index>, rule: TranslationTermRule)?
            for rule in rules where !rule.source.isEmpty {
                var searchStart = cursor
                while searchStart < text.endIndex,
                      let range = text.range(of: rule.source, options: [.caseInsensitive, .literal], range: searchStart..<text.endIndex) {
                    if Self.hasBoundaries(range, in: text) {
                        if best == nil || range.lowerBound < best!.range.lowerBound ||
                            (range.lowerBound == best!.range.lowerBound && range.upperBound > best!.range.upperBound) {
                            best = (range, rule)
                        }
                        break
                    }
                    searchStart = text.index(after: range.lowerBound)
                }
            }
            guard let best else {
                input.append(AttributedString(String(text[cursor...])))
                break
            }
            guard terms.count < Self.maximumOccurrences else { throw TranslationServiceError.terminologySafetyLimit }
            input.append(AttributedString(String(text[cursor..<best.range.lowerBound])))
            let original = String(text[best.range])
            let marker = markerPrefix + String(terms.count) + (compactMarkers ? "" : "|" + original) + "]]"
            var protected = AttributedString(marker)
            protected.skipsTranslation = true
            input.append(protected)
            terms.append(Term(marker: marker, output: best.rule.translation ?? original, original: original))
            cursor = best.range.upperBound
        }
        self.input = input
        self.terms = terms
    }

    /// Restore only complete, unique markers. Never publish partially restored text.
    func restore(_ translation: String, normalize: (String) throws -> String = { $0 }) throws -> String {
        var matches: [(Range<String.Index>, String)] = []
        for term in terms {
            guard let range = translation.range(of: term.marker, options: .literal),
                  translation.range(of: term.marker, options: .literal, range: range.upperBound..<translation.endIndex) == nil else {
                throw TranslationServiceError.terminologyNotPreserved
            }
            matches.append((range, term.output))
        }
        matches.sort { $0.0.lowerBound < $1.0.lowerBound }
        var result = ""
        var cursor = translation.startIndex
        for (range, output) in matches {
            guard range.lowerBound >= cursor else { throw TranslationServiceError.terminologyNotPreserved }
            let fragment = String(translation[cursor..<range.lowerBound])
            guard !fragment.contains(markerPrefix) else { throw TranslationServiceError.terminologyNotPreserved }
            result += try normalize(fragment)
            result += output
            cursor = range.upperBound
        }
        let tail = String(translation[cursor...])
        guard !tail.contains(markerPrefix) else { throw TranslationServiceError.terminologyNotPreserved }
        result += try normalize(tail)
        return result
    }

    private static func hasBoundaries(_ range: Range<String.Index>, in text: String) -> Bool {
        if range.lowerBound > text.startIndex,
           isWordCharacter(text[range.lowerBound]),
           isWordCharacter(text[text.index(before: range.lowerBound)]) { return false }
        if range.upperBound < text.endIndex,
           isWordCharacter(text[text.index(before: range.upperBound)]),
           isWordCharacter(text[range.upperBound]) { return false }
        return true
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            // Chinese, Japanese and Korean phrases don't require spaces around a term.
            switch scalar.value {
            case 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF,
                 0x20000...0x323AF, 0x1100...0x11FF,
                 0xA960...0xA97F, 0xD7B0...0xD7FF, 0xFF66...0xFF9D:
                return false
            default:
                return CharacterSet.alphanumerics.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar) || scalar == "_"
            }
        }
    }
}

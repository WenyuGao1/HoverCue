import Foundation

struct TranslationTermDraft: Codable, Equatable, Sendable {
    static let maximumTextLength = 80_000
    var keptTerms = ""
    var fixedTranslations = ""

    var bounded: Self {
        Self(keptTerms: String(keptTerms.prefix(Self.maximumTextLength)),
             fixedTranslations: String(fixedTranslations.prefix(Self.maximumTextLength)))
    }

    var parsed: ParsedTranslationTerms { ParsedTranslationTerms(draft: bounded) }
}

struct TranslationTermRule: Equatable, Sendable {
    let source: String
    /// Nil means preserve the exact spelling heard in the source.
    let translation: String?
}

struct ParsedTranslationTerms: Sendable {
    static let maximumEntriesPerBox = 200
    static let maximumSourceLength = 120
    static let maximumTranslationLength = 240
    let rules: [TranslationTermRule]
    let invalidKeptLines: [Int]
    let invalidFixedLines: [Int]

    init(draft: TranslationTermDraft) {
        var kept: [TranslationTermRule] = []
        var fixed: [TranslationTermRule] = []
        var keptErrors: [Int] = []
        var fixedErrors: [Int] = []
        var seenKept = Set<String>()
        var seenFixed = Set<String>()
        for (offset, line) in draft.keptTerms.components(separatedBy: .newlines).enumerated() {
            let term = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            guard kept.count < Self.maximumEntriesPerBox,
                  Self.valid(term, limit: Self.maximumSourceLength),
                  !term.contains("→"), !term.contains("->"),
                  seenKept.insert(Self.matchKey(term)).inserted else {
                keptErrors.append(offset + 1); continue
            }
            kept.append(.init(source: term, translation: nil))
        }
        for (offset, line) in draft.fixedTranslations.components(separatedBy: .newlines).enumerated() {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parts = line.components(separatedBy: line.contains("→") ? "→" : "->")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2,
                  fixed.count < Self.maximumEntriesPerBox,
                  Self.valid(parts[0], limit: Self.maximumSourceLength),
                  Self.valid(parts[1], limit: Self.maximumTranslationLength),
                  seenFixed.insert(Self.matchKey(parts[0])).inserted else {
                fixedErrors.append(offset + 1); continue
            }
            fixed.append(.init(source: parts[0], translation: parts[1]))
        }
        // A specified translation wins over preserving the same original term.
        rules = fixed + kept.filter { !seenFixed.contains(Self.matchKey($0.source)) }
        invalidKeptLines = keptErrors
        invalidFixedLines = fixedErrors
    }

    private static func valid(_ term: String, limit: Int) -> Bool {
        !term.isEmpty && term.count <= limit && !term.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func matchKey(_ term: String) -> String {
        term.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension CaptionLanguageSelection {
    var terminologyIdentifier: String {
        language == .chinese ? chineseScript.translationIdentifier : language.languageCode
    }

    func terminologyDisplayName(in appLanguage: AppLanguage) -> String {
        let name = language.displayName(in: appLanguage)
        return language == .chinese ? "\(name) (\(appLanguage.localized(chineseScript.localizationKey)))" : name
    }
}

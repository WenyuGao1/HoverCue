import Foundation
import Translation
import XCTest
@testable import LocalDualCaption

final class TranslationTermRulesTests: XCTestCase {
    func testParsingSupportsBothArrowsAndReportsInvalidOrDuplicateLines() {
        let parsed = TranslationTermDraft(
            keptTerms: "SCADA\nscada\n\nApple Watch\ninvalid → row",
            fixedTranslations: " Apple Watch → 苹果手表 \nenergy storage -> 储能\nbroken\nSCADA → \napple watch → 重复"
        ).parsed
        XCTAssertEqual(parsed.invalidKeptLines, [2, 5])
        XCTAssertEqual(parsed.invalidFixedLines, [3, 4, 5])
        XCTAssertEqual(parsed.rules, [
            .init(source: "Apple Watch", translation: "苹果手表"),
            .init(source: "energy storage", translation: "储能"),
            .init(source: "SCADA", translation: nil)
        ])
    }

    func testParsingBoundsEntriesAndTermLengths() {
        let draft = TranslationTermDraft(
            keptTerms: (0..<205).map { "Term\($0)" }.joined(separator: "\n"),
            fixedTranslations: String(repeating: "a", count: 121) + " → value\nterm → " + String(repeating: "b", count: 241)
        )
        XCTAssertEqual(draft.parsed.rules.count, 200)
        XCTAssertEqual(draft.parsed.invalidKeptLines, [201,202,203,204,205])
        XCTAssertEqual(draft.parsed.invalidFixedLines, [1,2])
        XCTAssertEqual(TranslationTermDraft(keptTerms: String(repeating: "a", count: 90_000)).bounded.keptTerms.count, TranslationTermDraft.maximumTextLength)
    }

    func testMatchingUsesWordBoundariesCaseAndLongestPhrase() throws {
        guard #available(macOS 26.4, *) else { throw XCTSkip("Requires attributed translation") }
        let rules = TranslationTermDraft(keptTerms: "Watch\nSCADA", fixedTranslations: "Apple Watch → 苹果手表\nart → 艺术").parsed.rules
        let plan = try ProtectedTermTranslation(text: "Cart art! APPLE WATCH, SCADA and scada. Watchmaker.", rules: rules)
        XCTAssertEqual(plan.terms.count, 4)
        XCTAssertEqual(try plan.restore(String(plan.input.characters)), "Cart 艺术! 苹果手表, SCADA and scada. Watchmaker.")
        XCTAssertTrue(plan.input.runs.filter { $0.skipsTranslation == true }.count == 4)
    }

    func testMatchingHandlesCJKWithoutSpacesAndLiteralPunctuation() throws {
        guard #available(macOS 26.4, *) else { throw XCTSkip("Requires attributed translation") }
        let rules = TranslationTermDraft(keptTerms: "C++\nSCADA", fixedTranslations: "苹果手表 → Apple Watch\n能源 → energy").parsed.rules
        let plan = try ProtectedTermTranslation(text: "使用苹果手表和SCADA系统，C++处理能源。", rules: rules)
        XCTAssertEqual(try plan.restore(String(plan.input.characters)), "使用Apple Watch和SCADA系统，C++处理energy。")
    }

    func testRestorationSupportsReorderedRepeatedTermsAndPreservesExactUserSpelling() throws {
        guard #available(macOS 26.4, *) else { throw XCTSkip("Requires attributed translation") }
        let plan = try ProtectedTermTranslation(text: "Apple Watch SCADA Apple Watch", rules: [
            .init(source: "Apple Watch", translation: "蘋果手錶"), .init(source: "SCADA", translation: nil)
        ])
        let simulatedTranslation = plan.terms[2].marker + " 與 " + plan.terms[1].marker + " 支援 " + plan.terms[0].marker
        let result = try plan.restore(simulatedTranslation) { fragment in
            try CaptionTextNormalizer.normalizeTranslation(fragment,
                expectedTarget: .init(language: .chinese, chineseScript: .simplified),
                actualTargetLanguage: Locale.Language(identifier: "zh-Hans"))
        }
        XCTAssertEqual(result, "蘋果手錶 与 SCADA 支援 蘋果手錶")
    }

    func testMissingDuplicatedOrDamagedMarkersNeverPublishPartialOutput() throws {
        guard #available(macOS 26.4, *) else { throw XCTSkip("Requires attributed translation") }
        let plan = try ProtectedTermTranslation(text: "Apple Watch and SCADA", rules: [
            .init(source: "Apple Watch", translation: "苹果手表"), .init(source: "SCADA", translation: nil)
        ])
        XCTAssertThrowsError(try plan.restore(plan.terms[0].marker))
        XCTAssertThrowsError(try plan.restore(plan.terms[0].marker + plan.terms[1].marker + plan.terms[0].marker))
        XCTAssertThrowsError(try plan.restore(String(plan.input.characters).replacingOccurrences(of: "]]", with: "]")))
    }

    func testProtectionHasOccurrenceLimitsAndNoMatchLeavesTextAlone() throws {
        guard #available(macOS 26.4, *) else { throw XCTSkip("Requires attributed translation") }
        let rule = TranslationTermRule(source: "SCADA", translation: nil)
        let noMatch = try ProtectedTermTranslation(text: "Ordinary text.", rules: [rule])
        XCTAssertTrue(noMatch.terms.isEmpty)
        XCTAssertEqual(String(noMatch.input.characters), "Ordinary text.")
        XCTAssertThrowsError(try ProtectedTermTranslation(text: String(repeating: "SCADA ", count: 129), rules: [rule]))
    }

    @MainActor func testRulesPersistSeparatelyByLanguageDirectionAndScript() throws {
        let suite = "HoverCue.TermTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = OverlaySettings(defaults: defaults)
        settings.vocabulary = ["Existing hint"]
        let first = TranslationTermDraft(keptTerms: "SCADA", fixedTranslations: "Apple Watch → 苹果手表")
        settings.updateCurrentTermDraft(first)
        settings.setTargetChineseScript(.traditional)
        XCTAssertEqual(settings.currentTermDraft, TranslationTermDraft())
        settings.updateCurrentTermDraft(.init(fixedTranslations: "Apple Watch → 蘋果手錶"))
        settings.setTargetChineseScript(.simplified)
        XCTAssertEqual(settings.currentTermDraft, first)
        settings.swapLanguages()
        XCTAssertEqual(settings.currentTermDraft, TranslationTermDraft())
        settings.swapLanguages()
        XCTAssertEqual(settings.currentTermDraft, first)
        let reloaded = OverlaySettings(defaults: defaults)
        XCTAssertEqual(reloaded.currentTermDraft, first)
        XCTAssertEqual(reloaded.vocabulary, ["Existing hint"])
    }

    func testFixedExamplesFollowBothLanguagesAndAllNewCopyIsLocalized() {
        let source = CaptionLanguageSelection(language: .english, chineseScript: .simplified)
        for target in CaptionLanguage.allCases where target != .english {
            let selection = CaptionLanguageSelection(language: target, chineseScript: .traditional)
            let lines = VocabularyExamples.fixedTranslations(source: source, target: selection).components(separatedBy: "\n")
            XCTAssertEqual(lines.count, 2)
            XCTAssertTrue(lines[0].hasPrefix("renewable energy -> "))
            XCTAssertTrue(lines[0].hasSuffix(VocabularyExamples.terms(for: selection)[2]))
            let reversed = VocabularyExamples.fixedTranslations(source: selection, target: source)
            XCTAssertTrue(reversed.components(separatedBy: "\n")[0].hasSuffix(" -> renewable energy"))
        }
        let keys = ["Keep original wording", "Specify translations", "Examples: %@ -> %@",
                    "One rule per line: original -> translation.",
                    "Invalid or duplicate entries on lines %@ are not applied.",
                    "Rules apply to this language direction when captions next start.",
                    "Rules stay on this Mac. Examples are not saved as rules."]
        for language in AppLanguage.allCases where language != .english {
            for key in keys { XCTAssertNotEqual(language.localized(key), key) }
        }
        XCTAssertTrue(AppLanguage.simplifiedChinese.localizedMessage("Translation unavailable: The translation model did not preserve a terminology rule. This translation was not displayed.").contains("本条译文未显示"))
    }

    @MainActor func testInstalledSystemStrategiesApplyBothTermModesWithoutAudioOrDownloads() async throws {
        guard #available(macOS 26.4, *) else { throw XCTSkip("Requires attributed translation") }
        let source = CaptionLanguageSelection(language: .english, chineseScript: .simplified)
        let target = CaptionLanguageSelection(language: .chinese, chineseScript: .simplified)
        let availability = await LanguageAvailability().status(from: source.translationLanguage, to: target.translationLanguage)
        guard availability == .installed else { throw XCTSkip("Offline English and Chinese resources aren't installed") }
        let rules = TranslationTermDraft(keptTerms: "SCADA", fixedTranslations: "Apple Watch → 苹果手表").parsed.rules
        // The string API exercises native translation and the contextual mode's system fallback.
        for preference in [TranslationModelPreference.lowLatency, .contextual] {
            let service = OnDeviceTranslationService()
            try service.activateInstalledSession(source: source, target: target, preference: preference)
            defer { service.cancel() }
            let result = try await service.translate("I use Apple Watch with SCADA. Apple Watch is useful.", rules: rules)
            // Assert properties only: don't include translated content in test output.
            XCTAssertTrue(result.components(separatedBy: "苹果手表").count == 3, "Both fixed terms must use the specified translation")
            XCTAssertTrue(result.contains("SCADA"), "The kept term must remain unchanged")
            XCTAssertFalse(result.contains("[[HC_"), "Internal markers must not reach captions or speech")
            XCTAssertFalse(result.contains("Apple Watch"), "The specified translation must replace the original term")
        }
    }
}

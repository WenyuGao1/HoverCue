import Foundation
import Translation
import XCTest
@testable import LocalDualCaption

@MainActor
private final class ContextGeneratorStub: ContextualTextGenerating {
    enum Behavior { case success, failure, cancelled, blocked }
    var behavior: Behavior = .success
    var calls: [(String, [String])] = []
    var continuation: CheckedContinuation<String, Never>?
    func translate(_ text: String, context: [String], source: CaptionLanguageSelection,
                   target: CaptionLanguageSelection, rules: [TranslationTermRule]) async throws -> String {
        calls.append((text, context))
        switch behavior {
        case .success: return "CURRENT TRANSLATION"
        case .failure: throw ContextualTranslationError.invalidOutput
        case .cancelled: throw CancellationError()
        case .blocked: return await withCheckedContinuation { continuation = $0 }
        }
    }
    func release() { continuation?.resume(returning: "LATE TRANSLATION"); continuation = nil }
}

final class ContextualTranslationTests: XCTestCase {
    private let english = CaptionLanguageSelection(language: .english, chineseScript: .simplified)
    private let chinese = CaptionLanguageSelection(language: .chinese, chineseScript: .simplified)
    private func work(_ sequence: Int = 0, generation: Int = 1, text: String = "Current public sentence.") -> TranslationWorkItem {
        TranslationWorkItem(segmentID: "public-\(sequence)", sequence: sequence, text: text, generation: generation)
    }
    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition())
    }

    func testContextSnapshotsAreBoundedAndNeverAcquireFutureText() {
        var window = TranslationContextWindow()
        let first = window.snapshotAndAppend(work(0), now: 100)
        let second = window.snapshotAndAppend(work(1, text: "Second public sentence."), now: 101)
        for n in 2..<12 { _ = window.snapshotAndAppend(work(n, text: String(repeating: "公开样本", count: 70)), now: 100 + Double(n)) }
        let latest = window.snapshotAndAppend(work(12), now: 112)
        XCTAssertTrue(first.precedingSources.isEmpty)
        XCTAssertEqual(second.precedingSources, ["Current public sentence."])
        XCTAssertLessThanOrEqual(latest.precedingSources.count, 4)
        XCTAssertLessThanOrEqual(latest.precedingSources.joined().utf8.count, 1_600)
        XCTAssertTrue(latest.precedingSources.allSatisfy { $0.utf8.count <= 600 })
    }

    func testContextExpiresOnPauseGenerationChangeResetAndClockReversal() {
        var window = TranslationContextWindow()
        _ = window.snapshotAndAppend(work(), now: 100)
        XCTAssertTrue(window.snapshotAndAppend(work(1), now: 131).precedingSources.isEmpty)
        XCTAssertTrue(window.snapshotAndAppend(work(0, generation: 2), now: 132).precedingSources.isEmpty)
        XCTAssertTrue(window.snapshotAndAppend(work(1, generation: 2), now: 1).precedingSources.isEmpty)
        window.reset()
        XCTAssertTrue(window.snapshotAndAppend(work(2, generation: 2), now: 2).precedingSources.isEmpty)
    }

    func testContextDoesNotIncludeOutOfOrderOrSameSequenceText() {
        var window = TranslationContextWindow()
        _ = window.snapshotAndAppend(work(5), now: 100)
        XCTAssertTrue(window.snapshotAndAppend(work(3), now: 101).precedingSources.isEmpty)
        XCTAssertTrue(window.snapshotAndAppend(work(3), now: 102).precedingSources.isEmpty)
    }

    func testOversizedGraphemeCannotEscapeContextByteLimit() {
        let text = "a" + String(repeating: "\u{301}", count: 2_000)
        XCTAssertTrue(TranslationContextWindow.prefix(text, maximumBytes: 600).isEmpty)
        XCTAssertEqual(TranslationContextWindow.prefix("中文🙂", maximumBytes: 6), "中文")
    }

    func testOutputValidationRejectsMissingChangedAndInventedNumbers() throws {
        XCTAssertEqual(try ContextualTranslationValidation.validate("周五15点见面。", source: "Meet at 15 on Friday.", target: chinese), "周五15点见面。")
        for text in ["周五50点见面。", "周五见面。", "周五15点见面，费用20元。", "", "```translation```"] {
            XCTAssertThrowsError(try ContextualTranslationValidation.validate(text, source: "Meet at 15 on Friday.", target: chinese))
        }
        XCTAssertThrowsError(try ContextualTranslationValidation.validate("费用是314。", source: "The cost is 3.14.", target: chinese))
        XCTAssertThrowsError(try ContextualTranslationValidation.validate("温度为15。", source: "The temperature is -15.", target: chinese))
    }

    func testOutputValidationAllowsLocalizedNumbersAndDateFormatting() throws {
        _ = try ContextualTranslationValidation.validate("预算为1.000欧元。", source: "The budget is 1,000 euros.", target: chinese)
        _ = try ContextualTranslationValidation.validate("2026年11月4日。", source: "2026-11-04.", target: chinese)
        _ = try ContextualTranslationValidation.validate("费用为15。", source: "The cost is 15.00.", target: chinese)
    }

    func testWrongOutputScriptsAreRejectedAndShortNamesAllowed() throws {
        XCTAssertThrowsError(try ContextualTranslationValidation.validate("This sentence should have been translated.", source: "This sentence should have been translated.", target: chinese))
        XCTAssertThrowsError(try ContextualTranslationValidation.validate("这段中文并不是所需的英语翻译。", source: "Public text.", target: english))
        XCTAssertEqual(try ContextualTranslationValidation.validate("SCADA", source: "SCADA", target: chinese), "SCADA")
    }

    @MainActor func testContextualPreferencePersistsWithoutEnablingHistory() throws {
        let suite = "HoverCue.ContextualTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = OverlaySettings(defaults: defaults)
        settings.translationModelPreference = .contextual
        XCTAssertEqual(OverlaySettings(defaults: defaults).translationModelPreference, .contextual)
        XCTAssertEqual(TranslationModelPreference.allCases, [.lowLatency, .contextual])
        let store = TranslationHistoryStore(digestGenerator: nil)
        XCTAssertFalse(store.enabled)
    }

    @MainActor func testLocalRequestCompletesAndReleasesItsSlot() async throws {
        let generator = ContextGeneratorStub()
        let runner = TimedContextualRequest(generator: generator)
        let output = try await runner.run(text: "CURRENT", context: ["PRIOR"], source: english, target: chinese, rules: [], timeout: 1)
        XCTAssertEqual(output, "CURRENT TRANSLATION")
        XCTAssertEqual(generator.calls.first?.1, ["PRIOR"])
        XCTAssertFalse(runner.isBusy)
    }

    @MainActor func testDeadlineDoesNotWaitForUncooperativeRequestOrStartAnotherOne() async throws {
        let generator = ContextGeneratorStub(); generator.behavior = .blocked
        let runner = TimedContextualRequest(generator: generator)
        do { _ = try await runner.run(text: "CURRENT", context: [], source: english, target: chinese, rules: [], timeout: 0.02); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? ContextualTranslationError, .timeout) }
        XCTAssertTrue(runner.isBusy)
        do { _ = try await runner.run(text: "NEXT", context: [], source: english, target: chinese, rules: [], timeout: 1); XCTFail("Expected busy") }
        catch { XCTAssertEqual(error as? ContextualTranslationError, .busy) }
        XCTAssertEqual(generator.calls.count, 1)
        generator.release()
        try await waitUntil { !runner.isBusy }
    }

    @MainActor func testCancellationReturnsWithoutWaitingForUncooperativeModel() async throws {
        let generator = ContextGeneratorStub(); generator.behavior = .blocked
        let runner = TimedContextualRequest(generator: generator)
        let task = Task { try await runner.run(text: "CURRENT", context: [], source: english, target: chinese, rules: [], timeout: 2) }
        try await waitUntil { generator.continuation != nil }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request must not return output") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(runner.isBusy)
        generator.release()
        try await waitUntil { !runner.isBusy }
    }

    @MainActor func testCoordinatorUsesImmutableContextAndPublishesOneResult() async throws {
        let generator = ContextGeneratorStub()
        let coordinator = ContextualTranslationCoordinator(generator: generator)
        coordinator.activate(source: english, target: chinese, availability: .available)
        var item = work(); item.context = .init(precedingSources: ["PRIOR ONLY"], enqueuedAt: ProcessInfo.processInfo.systemUptime)
        var fallbacks = 0
        let result = try await coordinator.translate(item, rules: [], queuedCount: 0) { fallbacks += 1; return "SYSTEM" }
        XCTAssertEqual(result, "CURRENT TRANSLATION")
        XCTAssertEqual(generator.calls.first?.1, ["PRIOR ONLY"])
        XCTAssertEqual(fallbacks, 0)
        XCTAssertEqual(coordinator.statusKey, "Contextual enhancement · On-device")
    }

    @MainActor func testOneFailureFallsBackAndSuccessResetsFailureCounter() async throws {
        let generator = ContextGeneratorStub(); generator.behavior = .failure
        let coordinator = ContextualTranslationCoordinator(generator: generator)
        coordinator.activate(source: english, target: chinese, availability: .available)
        let first = try await coordinator.translate(work(), rules: [], queuedCount: 0) { "SYSTEM" }
        XCTAssertEqual(first, "SYSTEM")
        XCTAssertEqual(coordinator.statusKey, "Using system translation for this sentence.")
        generator.behavior = .success
        _ = try await coordinator.translate(work(1), rules: [], queuedCount: 0) { XCTFail("Unexpected fallback"); return "SYSTEM" }
        generator.behavior = .failure
        _ = try await coordinator.translate(work(2), rules: [], queuedCount: 0) { "SYSTEM" }
        XCTAssertEqual(coordinator.statusKey, "Using system translation for this sentence.")
    }

    @MainActor func testFrameworkCancellationDoesNotDiscardCurrentSentenceWhenCallerIsActive() async throws {
        let generator = ContextGeneratorStub(); generator.behavior = .cancelled
        let coordinator = ContextualTranslationCoordinator(generator: generator)
        coordinator.activate(source: english, target: chinese, availability: .available)
        let result = try await coordinator.translate(work(), rules: [], queuedCount: 0) { "SYSTEM CURRENT" }
        XCTAssertEqual(result, "SYSTEM CURRENT")
        XCTAssertEqual(coordinator.statusKey, "Using system translation for this sentence.")
    }

    @MainActor func testTwoFailuresLatchFallbackUntilNextCaptionSession() async throws {
        let generator = ContextGeneratorStub(); generator.behavior = .failure
        let coordinator = ContextualTranslationCoordinator(generator: generator)
        coordinator.activate(source: english, target: chinese, availability: .available)
        var outputs: [String] = []
        for n in 0..<3 { outputs.append(try await coordinator.translate(work(n), rules: [], queuedCount: 0) { "SYSTEM-\(n)" }) }
        XCTAssertEqual(outputs, ["SYSTEM-0", "SYSTEM-1", "SYSTEM-2"])
        XCTAssertEqual(generator.calls.count, 2)
        XCTAssertEqual(coordinator.statusKey, "Contextual enhancement paused for this session; using system translation.")
        generator.behavior = .success
        coordinator.activate(source: english, target: chinese, availability: .available)
        _ = try await coordinator.translate(work(), rules: [], queuedCount: 0) { XCTFail("Unexpected fallback"); return "SYSTEM" }
        XCTAssertEqual(generator.calls.count, 3)
    }

    @MainActor func testUnavailableModelUsesSystemWithoutStartingLocalRequest() async throws {
        let generator = ContextGeneratorStub()
        let coordinator = ContextualTranslationCoordinator(generator: generator)
        for availability in [ContextualModelAvailability.deviceNotEligible, .intelligenceDisabled, .modelNotReady, .unsupportedLanguage] {
            coordinator.activate(source: english, target: chinese, availability: availability)
            let output = try await coordinator.translate(work(), rules: [], queuedCount: 0) { "SYSTEM" }
            XCTAssertEqual(output, "SYSTEM")
            XCTAssertEqual(coordinator.statusKey, "Contextual enhancement unavailable; using system translation.")
        }
        XCTAssertTrue(generator.calls.isEmpty)
    }

    @MainActor func testBacklogAndAgeSwitchToSystemBeforeDiscardingAnySentence() async throws {
        let generator = ContextGeneratorStub()
        let coordinator = ContextualTranslationCoordinator(generator: generator, now: { 200 })
        coordinator.activate(source: english, target: chinese, availability: .available)
        _ = try await coordinator.translate(work(), rules: [], queuedCount: 6) { "SYSTEM" }
        XCTAssertTrue(generator.calls.isEmpty)
        coordinator.activate(source: english, target: chinese, availability: .available)
        var old = work(); old.context = .init(enqueuedAt: 100)
        _ = try await coordinator.translate(old, rules: [], queuedCount: 0) { "SYSTEM" }
        XCTAssertTrue(generator.calls.isEmpty)
    }

    @MainActor func testRestartRejectsLateLocalOutputAndKeepsSingleModelSlot() async throws {
        let generator = ContextGeneratorStub(); generator.behavior = .blocked
        let coordinator = ContextualTranslationCoordinator(generator: generator)
        coordinator.activate(source: english, target: chinese, availability: .available)
        let oldTask = Task { try await coordinator.translate(work(), rules: [], queuedCount: 0) { XCTFail("Cancelled generation must not fall back"); return "SYSTEM" } }
        try await waitUntil { generator.continuation != nil }
        coordinator.cancel()
        coordinator.activate(source: english, target: chinese, availability: .available)
        do { _ = try await oldTask.value; XCTFail("Old result must be rejected") } catch { XCTAssertTrue(error is CancellationError) }
        let next = try await coordinator.translate(work(0, generation: 2), rules: [], queuedCount: 0) { "NEW SYSTEM" }
        XCTAssertEqual(next, "NEW SYSTEM")
        XCTAssertEqual(generator.calls.count, 1)
        generator.release()
        try await waitUntil { !coordinator.localRequestInFlight }
        generator.behavior = .success
        let final = try await coordinator.translate(work(1, generation: 2), rules: [], queuedCount: 0) { "SYSTEM" }
        XCTAssertEqual(final, "CURRENT TRANSLATION")
    }

    @MainActor func testRestartAlsoRejectsLateSystemFallbackOutput() async throws {
        let generator = ContextGeneratorStub()
        let coordinator = ContextualTranslationCoordinator(generator: generator)
        coordinator.activate(source: english, target: chinese, availability: .modelNotReady)
        var pending: CheckedContinuation<String, Never>?
        let oldTask = Task { try await coordinator.translate(work(), rules: [], queuedCount: 0) { await withCheckedContinuation { pending = $0 } } }
        try await waitUntil { pending != nil }
        coordinator.cancel()
        coordinator.activate(source: english, target: chinese, availability: .available)
        pending?.resume(returning: "STALE SYSTEM")
        do { _ = try await oldTask.value; XCTFail("Old fallback must be rejected") } catch { XCTAssertTrue(error is CancellationError) }
    }

    @MainActor func testContextIsNotPersistedByHistory() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "HoverCue-ContextPrivacy-\(UUID().uuidString)/history.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TranslationHistoryStore(url: url, digestGenerator: nil)
        var item = work(); item.context = .init(precedingSources: ["PRIVATE CONTEXT MUST NOT BE SAVED"], enqueuedAt: 100)
        store.record(item)
        await store.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        store.enable(); store.beginSession(source: "en", target: "zh-Hans", generation: 1)
        store.record(item); store.complete(item, translation: "公开译文。")
        store.disable(); await store.flush()
        let session = try XCTUnwrap(store.sessions.first)
        let page = try await store.page(sessionID: session.id, offset: 0)
        XCTAssertEqual(page.entries.first?.source, "Current public sentence.")
        XCTAssertFalse(page.entries.contains { $0.source.contains("PRIVATE CONTEXT") || ($0.translation ?? "").contains("PRIVATE CONTEXT") })
    }

    func testContextualModeCopyIsPresentInAllInterfaceLanguages() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let keys = ["Contextual enhancement", "Contextual enhancement · On-device", "Contextual enhancement paused for this session; using system translation.", "Using system translation for this sentence.", "Contextual enhancement unavailable; using system translation."]
        for locale in HistoryDigestLanguagePolicy.identifiers where locale != "en" {
            let data = try Data(contentsOf: root.appending(path: "LocalDualCaption/\(locale).lproj/Localizable.strings"))
            let strings = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            for key in keys { XCTAssertFalse(strings[key, default: ""].isEmpty, "\(locale): \(key)") }
        }
    }

    @MainActor func testSystemFallbackPreservesJapaneseNegationWithoutAutomaticMarkers() async throws {
        guard #available(macOS 26.4, *) else { throw XCTSkip("Requires installed translation") }
        let target = CaptionLanguageSelection(language: .japanese, chineseScript: .simplified)
        let availability = await LanguageAvailability(preferredStrategy: .lowLatency)
            .status(from: english.translationLanguage, to: target.translationLanguage)
        guard availability == .installed else { throw XCTSkip("Offline English and Japanese resources aren't installed") }
        let service = OnDeviceTranslationService()
        defer { service.cancel() }
        try service.activateInstalledSession(source: english, target: target, preference: .contextual)
        let work = TranslationWorkItem(segmentID: "synthetic-negation", sequence: 1,
            text: "The meeting is on Friday at 15:30, not 16:00.", generation: 1)
        let result = try await service.translate(work, rules: [], queuedCount: 6)
        XCTAssertTrue(result.contains("金曜"), "The weekday must remain Friday")
        XCTAssertTrue(result.contains("15") && result.contains("30") && result.contains("16"), "Both times must remain present")
        XCTAssertTrue(["ありません", "ではない", "ではなく", "じゃない", "なく"].contains(where: result.contains),
                      "The second time must remain negated")
        XCTAssertFalse(result.contains("[[HC_"), "Automatic markers must not damage fallback grammar")
        XCTAssertEqual(service.contextualStatusKey, "Contextual enhancement paused for this session; using system translation.")
    }

    func testCompactMarkersAreExactCollisionCheckedAndKeepLegacyDefaults() throws {
        guard #available(macOS 26.4, *) else { return }
        let rules = [TranslationTermRule(source: "Friday", translation: "周五")]
        let local = try ProtectedTermTranslation(text: "Friday at 15:30.", rules: rules, compactMarkers: true)
        XCTAssertEqual(local.terms.first?.marker, "[[HT:0]]")
        XCTAssertEqual(try local.restore(String(local.input.characters)), "周五 at 15:30.")
        XCTAssertThrowsError(try local.restore("[[HT:0]] [[HT:0]]"))
        let collision = try ProtectedTermTranslation(text: "[[HT: Friday", rules: rules, compactMarkers: true)
        XCTAssertFalse(collision.terms.first!.marker.hasPrefix("[[HT:0"))
        let legacy = try ProtectedTermTranslation(text: "Friday", rules: rules)
        XCTAssertTrue(legacy.terms.first!.marker.hasPrefix("[[HC_"))
    }

    func testWrongWeekdayIsRejectedAcrossLanguages() throws {
        let portuguese = CaptionLanguageSelection(language: .portuguese, chineseScript: .simplified)
        XCTAssertThrowsError(try ContextualTranslationValidation.validate("A reunião é no sábado.", source: "The meeting is on Friday.", target: portuguese))
        _ = try ContextualTranslationValidation.validate("A reunião é na sexta-feira.", source: "The meeting is on Friday.", target: portuguese)
        XCTAssertEqual(ContextualTranslationFacts.detectedWeekdays(in: "金曜日，星期五，금요일"), [4])
        XCTAssertTrue(ContextualTranslationFacts.detectedWeekdays(in: "Fridayish is a public made-up name.").isEmpty)
    }
}

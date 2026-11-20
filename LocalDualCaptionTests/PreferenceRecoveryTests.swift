import XCTest
@testable import LocalDualCaption

final class PreferenceRecoveryTests: XCTestCase {
    private func app(_ pid: Int32, bundle: String = "org.example.player", auxiliary: Bool = false) -> AudioSource {
        AudioSource(id: "\(bundle)-\(pid)", title: "Player", bundleIdentifier: bundle,
                    processID: pid, isAuxiliary: auxiliary)
    }

    func testApplicationClassificationKeepsHelpersAndUnknownProcessesOutOfPrimaryList() {
        let bundle = "org.example.player"
        XCTAssertFalse(ApplicationAudioSourceCatalog.isAuxiliary(isRegularApplication: true,
            bundleURL: URL(fileURLWithPath: "/Applications/Player.app"), runningBundleID: bundle, captureBundleID: bundle))
        XCTAssertTrue(ApplicationAudioSourceCatalog.isAuxiliary(isRegularApplication: false,
            bundleURL: URL(fileURLWithPath: "/Applications/Player.app"), runningBundleID: bundle, captureBundleID: bundle))
        XCTAssertTrue(ApplicationAudioSourceCatalog.isAuxiliary(isRegularApplication: true,
            bundleURL: URL(fileURLWithPath: "/Applications/Player.app/Contents/Frameworks/Helper.app"),
            runningBundleID: bundle, captureBundleID: bundle))
        XCTAssertTrue(ApplicationAudioSourceCatalog.isAuxiliary(isRegularApplication: true,
            bundleURL: URL(fileURLWithPath: "/Applications/Player.app"), runningBundleID: bundle, captureBundleID: "org.other.host"))
        XCTAssertTrue(ApplicationAudioSourceCatalog.isAuxiliary(isRegularApplication: false,
            bundleURL: nil, runningBundleID: nil, captureBundleID: bundle))
    }

    func testDisappearingApplicationNeverFallsBackToAllSystemAudio() throws {
        let selected = app(10)
        let result = ApplicationAudioSourceCatalog.preservingSelection(selected.id, previous: [selected],
            refreshed: [.allSystemAudio, .systemDefaultMicrophone])
        XCTAssertEqual(result.selectedID, selected.id)
        let missing = try XCTUnwrap(result.sources.first { $0.id == selected.id })
        XCTAssertFalse(missing.isAvailable)
        XCTAssertFalse(missing.isMicrophone)
        XCTAssertEqual(missing.title, selected.title)
        let repeated = ApplicationAudioSourceCatalog.preservingSelection(result.selectedID, previous: result.sources,
            refreshed: [.allSystemAudio])
        XCTAssertEqual(repeated.sources.filter { $0.id == selected.id }.count, 1)
        XCTAssertEqual(repeated.selectedID, selected.id)
    }

    func testRestartedApplicationRecoversByUnambiguousBundleIdentityIncludingLegacySelections() {
        let old = app(10, bundle: "org.example.my-player")
        let new = app(20, bundle: "org.example.my-player")
        let result = ApplicationAudioSourceCatalog.preservingSelection(old.id, previous: [], refreshed: [.allSystemAudio, new])
        XCTAssertEqual(result.selectedID, new.id)
        XCTAssertEqual(result.sources.count, 2)
        let ambiguous = ApplicationAudioSourceCatalog.preservingSelection(old.id, previous: [],
            refreshed: [.allSystemAudio, new, app(30, bundle: "org.example.my-player")])
        XCTAssertEqual(ambiguous.selectedID, old.id)
        XCTAssertFalse(ambiguous.sources.first!.isAvailable)
    }

    func testUnavailableMicrophoneAndAuxiliarySelectionsStayDistinct() {
        let mic = AudioSource.microphone(title: "USB", deviceUID: "device-123")
        let result = ApplicationAudioSourceCatalog.preservingSelection(mic.id, previous: [], refreshed: [.allSystemAudio])
        XCTAssertTrue(result.sources.first!.isMicrophone)
        XCTAssertFalse(result.sources.first!.isAvailable)
        XCTAssertEqual(result.selectedID, mic.id)
        let helper = app(40, auxiliary: true)
        let existing = ApplicationAudioSourceCatalog.preservingSelection(helper.id, previous: [], refreshed: [.allSystemAudio, helper])
        XCTAssertEqual(existing.selectedID, helper.id)
        XCTAssertTrue(existing.sources.last!.isAuxiliary)
    }

    @MainActor
    func testVoicesSurviveDirectionSwapsAndReloadWithoutCrossLanguageOverwrite() throws {
        let suite = "HoverCue.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = OverlaySettings(defaults: defaults)
        settings.translationVoiceIdentifier = "voice.chinese.chosen"
        settings.swapLanguages()
        settings.resolveTranslationVoice(availableIdentifiers: ["voice.english.default", "voice.english.chosen"])
        settings.translationVoiceIdentifier = "voice.english.chosen"
        settings.swapLanguages()
        settings.resolveTranslationVoice(availableIdentifiers: ["voice.chinese.default", "voice.chinese.chosen"])
        XCTAssertEqual(settings.translationVoiceIdentifier, "voice.chinese.chosen")
        let reloaded = OverlaySettings(defaults: defaults)
        reloaded.swapLanguages()
        reloaded.resolveTranslationVoice(availableIdentifiers: ["voice.english.default", "voice.english.chosen"])
        XCTAssertEqual(reloaded.translationVoiceIdentifier, "voice.english.chosen")
    }

    @MainActor
    func testLegacyVoiceMigratesOnceAndChineseRegionsRememberSeparateVoices() throws {
        let suite = "HoverCue.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("legacy.han", forKey: OverlaySettings.Key.translationVoiceIdentifier)
        let settings = OverlaySettings(defaults: defaults)
        XCTAssertEqual(settings.preferredTranslationVoiceIdentifier, "legacy.han")
        settings.setTargetChineseScript(.traditional)
        settings.resolveTranslationVoice(availableIdentifiers: ["voice.taiwan"])
        XCTAssertNil(settings.preferredTranslationVoiceIdentifier)
        settings.translationVoiceIdentifier = "voice.taiwan"
        settings.setTargetChineseScript(.simplified)
        settings.resolveTranslationVoice(availableIdentifiers: ["legacy.han"])
        XCTAssertEqual(settings.translationVoiceIdentifier, "legacy.han")
        let reloaded = OverlaySettings(defaults: defaults)
        reloaded.setTargetChineseScript(.traditional)
        reloaded.resolveTranslationVoice(availableIdentifiers: ["voice.taiwan"])
        XCTAssertEqual(reloaded.translationVoiceIdentifier, "voice.taiwan")
    }

    @MainActor
    func testUnavailableVoiceFallbackDoesNotErasePreferenceAcrossRestart() throws {
        let suite = "HoverCue.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = OverlaySettings(defaults: defaults)
        settings.translationVoiceIdentifier = "chosen.voice"
        settings.resolveTranslationVoice(availableIdentifiers: ["fallback.voice"])
        XCTAssertEqual(settings.translationVoiceIdentifier, "fallback.voice")
        XCTAssertEqual(settings.preferredTranslationVoiceIdentifier, "chosen.voice")
        let reloaded = OverlaySettings(defaults: defaults)
        reloaded.resolveTranslationVoice(availableIdentifiers: [])
        XCTAssertEqual(reloaded.translationVoiceIdentifier, "")
        XCTAssertEqual(reloaded.preferredTranslationVoiceIdentifier, "chosen.voice")
        reloaded.resolveTranslationVoice(availableIdentifiers: ["fallback.voice", "chosen.voice"])
        XCTAssertEqual(reloaded.translationVoiceIdentifier, "chosen.voice")
        reloaded.translationVoiceIdentifier = "fallback.voice"
        XCTAssertEqual(reloaded.preferredTranslationVoiceIdentifier, "fallback.voice")
    }

    @MainActor
    func testAppModelRestoresTheSelectedInstalledVoiceAfterLanguageSwap() throws {
        let suite = "HoverCue.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = OverlaySettings(defaults: defaults)
        let model = AppModel(settings: settings)
        let chinese = try XCTUnwrap(model.translationVoiceOptions.last?.id)
        settings.translationVoiceIdentifier = chinese
        settings.swapLanguages()
        model.refreshTranslationVoices()
        let english = try XCTUnwrap(model.translationVoiceOptions.last?.id)
        settings.translationVoiceIdentifier = english
        settings.swapLanguages()
        model.refreshTranslationVoices()
        XCTAssertEqual(settings.translationVoiceIdentifier, chinese)
        XCTAssertFalse(model.usingFallbackTranslationVoice)
        settings.swapLanguages()
        model.refreshTranslationVoices()
        XCTAssertEqual(settings.translationVoiceIdentifier, english)
    }
}

import Foundation
import XCTest
@testable import LocalDualCaption

final class SettingsAndPrivacyTests: XCTestCase {
    @MainActor
    func testMenuThemePersistsWithoutChangingCaptionAppearance() throws {
        let suiteName = "LocalDualCaptionTests.Theme.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = OverlaySettings(defaults: defaults)
        settings.glassAppearance = .highTransparency
        settings.englishColorHex = "ABCDEF"
        settings.chineseColorHex = "FEDCBA"
        settings.englishFontSize = 25
        settings.overlayWidth = 920

        for theme in InterfaceTheme.allCases {
            defaults.set(theme.rawValue, forKey: InterfaceTheme.storageKey)
            let reloadedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            XCTAssertEqual(InterfaceTheme.resolved(reloadedDefaults.string(forKey: InterfaceTheme.storageKey) ?? ""), theme)
            let reloaded = OverlaySettings(defaults: reloadedDefaults)
            XCTAssertEqual(reloaded.glassAppearance, .highTransparency)
            XCTAssertEqual(reloaded.englishColorHex, "ABCDEF")
            XCTAssertEqual(reloaded.chineseColorHex, "FEDCBA")
            XCTAssertEqual(reloaded.englishFontSize, 25)
            XCTAssertEqual(reloaded.overlayWidth, 920)
        }
        XCTAssertEqual(InterfaceTheme.resolved("obsolete-theme"), .system)
        XCTAssertEqual(InterfaceTheme.resolved("pink"), .red)
    }

    @MainActor
    func testSettingsNeverPersistCaptionContent() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = OverlaySettings(defaults: defaults)
        settings.englishFontSize = 30
        settings.vocabulary = ["SCADA"]
        let keys = Set(defaults.dictionaryRepresentation().keys)
        XCTAssertFalse(keys.contains { $0.localizedCaseInsensitiveContains("caption") })
        XCTAssertFalse(keys.contains { $0.localizedCaseInsensitiveContains("transcript") })
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { ($0 as? String) == "private spoken words" })
    }

    func testVocabularyExamplesFollowSourceLanguageAndLocalizeTheirHeading() {
        var examples = Set<String>()
        for language in CaptionLanguage.allCases {
            let scripts: [ChineseScript] = language == .chinese ? [.simplified, .traditional] : [.simplified]
            for script in scripts {
                let selection = CaptionLanguageSelection(language: language, chineseScript: script)
                let terms = VocabularyExamples.terms(for: selection)
                XCTAssertGreaterThan(terms.count, 1)
                XCTAssertTrue(terms.allSatisfy { !$0.isEmpty && !$0.contains("\n") && !$0.contains("→") })
                examples.insert(terms.joined(separator: "\n"))
                for appLanguage in AppLanguage.allCases {
                    let heading = VocabularyExamples.title(for: selection, in: appLanguage)
                    XCTAssertTrue(heading.contains(language.displayName(in: appLanguage)))
                    XCTAssertFalse(heading.contains("%@"))
                    if appLanguage != .english {
                        XCTAssertNotEqual(appLanguage.localized("Examples for %@ — one term per line"), "Examples for %@ — one term per line")
                        XCTAssertNotEqual(appLanguage.localized("Light Pink"), "Light Pink")
                    }
                }
            }
        }
        XCTAssertEqual(examples.count, 10, "Each source language and Chinese script needs its own example.")
        XCTAssertTrue(VocabularyExamples.terms(for: .init(language: .chinese, chineseScript: .simplified)).contains("苹果手表"))
        XCTAssertTrue(VocabularyExamples.terms(for: .init(language: .chinese, chineseScript: .traditional)).contains("蘋果手錶"))
    }

    @MainActor
    func testProfessionalVocabularyLoadsFromUserDefaults() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["rectenna", "NESO"], forKey: OverlaySettings.Key.vocabulary)
        let settings = OverlaySettings(defaults: defaults)
        XCTAssertEqual(settings.vocabulary, ["rectenna", "NESO"])
    }

    @MainActor
    func testAutomaticTranslationSpeechDefaultsOffAndPersists() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = OverlaySettings(defaults: defaults)
        XCTAssertFalse(settings.automaticallySpeakTranslations)
        settings.automaticallySpeakTranslations = true
        XCTAssertTrue(OverlaySettings(defaults: defaults).automaticallySpeakTranslations)
    }

    @MainActor
    func testTranslationPlaybackVoicePersists() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = OverlaySettings(defaults: defaults)
        settings.translationVoiceIdentifier = "com.apple.voice.example"
        XCTAssertEqual(
            OverlaySettings(defaults: defaults).translationVoiceIdentifier,
            "com.apple.voice.example"
        )
    }

    @MainActor
    func testSelectedMicrophonePersistsByStableSourceIdentifier() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let microphone = AudioSource.microphone(
            title: "Test Microphone",
            deviceUID: "test-device-uid"
        )
        let settings = OverlaySettings(defaults: defaults)
        settings.selectedAudioSourceID = microphone.id

        let reloaded = OverlaySettings(defaults: defaults)
        XCTAssertEqual(reloaded.selectedAudioSourceID, microphone.id)
        XCTAssertEqual(AppModel(settings: reloaded).selectedSourceID, microphone.id)
    }

    func testConcreteAndUnavailableMicrophoneSourcesRemainDistinctFromSystemAudio() throws {
        let microphone = AudioSource.microphone(
            title: "Test Microphone",
            deviceUID: "test-device-uid"
        )
        XCTAssertTrue(microphone.isMicrophone)
        XCTAssertTrue(microphone.isAvailable)
        XCTAssertFalse(AudioSource.allSystemAudio.isMicrophone)

        let unavailable = try XCTUnwrap(
            AudioSource.unavailableMicrophone(forSourceID: microphone.id)
        )
        XCTAssertEqual(unavailable.id, microphone.id)
        XCTAssertEqual(unavailable.microphoneDeviceUID, "test-device-uid")
        XCTAssertTrue(unavailable.isMicrophone)
        XCTAssertFalse(unavailable.isAvailable)
    }

    func testMicrophoneCatalogCanInspectTheHostWithoutStartingCapture() throws {
        _ = try MicrophoneDeviceCatalog.availableSources()
    }

    @MainActor
    func testProfessionalVocabularyDefaultsToEmpty() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(OverlaySettings(defaults: defaults).vocabulary.isEmpty)
    }

    @MainActor
    func testLegacyBundledVocabularyIsClearedWithoutErasingCustomTerms() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyVocabulary = [
            "renewable energy", "offshore wind", "onshore wind", "solar power",
            "energy storage", "battery storage", "curtailment", "grid integration",
            "power system", "electrolyser", "green hydrogen", "green ammonia",
            "LCOE", "SCADA", "capacity factor", "space-based solar power", "SBSP",
            "wireless power transmission", "rectenna", "microwave transmission",
            "photovoltaic", "inverter", "National Energy System Operator", "NESO"
        ]
        defaults.set(legacyVocabulary, forKey: OverlaySettings.Key.vocabulary)

        XCTAssertTrue(OverlaySettings(defaults: defaults).vocabulary.isEmpty)
        XCTAssertEqual(defaults.stringArray(forKey: OverlaySettings.Key.vocabulary), [])

        defaults.set(["User edited term"], forKey: OverlaySettings.Key.vocabulary)
        XCTAssertEqual(
            OverlaySettings(defaults: defaults).vocabulary,
            ["User edited term"]
        )
    }

    @MainActor
    func testOverlayHeightPersistsAndReloads() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = OverlaySettings(defaults: defaults)
        XCTAssertEqual(settings.overlayHeight, OverlaySettings.defaultOverlayHeight)
        settings.overlayHeight = 380

        XCTAssertEqual(defaults.double(forKey: OverlaySettings.Key.overlayHeight), 380)
        let reloaded = OverlaySettings(defaults: defaults)
        XCTAssertEqual(reloaded.overlayHeight, 380)
    }

    @MainActor
    func testCaptionDisplayModePersistsAndDefaultsToBothCaptions() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = OverlaySettings(defaults: defaults)
        XCTAssertEqual(settings.captionDisplayMode, .transcriptionAndTranslation)
        settings.captionDisplayMode = .translationOnly

        XCTAssertEqual(
            OverlaySettings(defaults: defaults).captionDisplayMode,
            .translationOnly
        )
    }

    func testCaptionDisplayModesExposeRequestedCaptionLayers() {
        XCTAssertTrue(CaptionDisplayMode.transcriptionAndTranslation.showsTranscription)
        XCTAssertTrue(CaptionDisplayMode.transcriptionAndTranslation.showsTranslation)
        XCTAssertTrue(CaptionDisplayMode.transcriptionOnly.showsTranscription)
        XCTAssertFalse(CaptionDisplayMode.transcriptionOnly.showsTranslation)
        XCTAssertFalse(CaptionDisplayMode.translationOnly.showsTranscription)
        XCTAssertTrue(CaptionDisplayMode.translationOnly.showsTranslation)
    }

    @MainActor
    func testGlassAppearanceDefaultsToDarkAndPersists() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = OverlaySettings(defaults: defaults)
        XCTAssertEqual(settings.glassAppearance, .dark)
        settings.glassAppearance = .highTransparency

        XCTAssertEqual(
            defaults.string(forKey: OverlaySettings.Key.glassAppearance),
            "highTransparency"
        )
        XCTAssertEqual(
            OverlaySettings(defaults: defaults).glassAppearance,
            .highTransparency
        )
    }

    func testCaptionsHaveNoShadowBlurOrRasterizedDuplicate() throws {
        let overlaySource = try String(
            contentsOf: workspaceRoot.appending(
                path: "LocalDualCaption/Overlay/CaptionOverlayView.swift"
            ),
            encoding: .utf8
        )
        let previewSource = try String(
            contentsOf: workspaceRoot.appending(
                path: "LocalDualCaption/UI/MainControlView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(overlaySource.contains("struct CaptionText"))
        XCTAssertFalse(overlaySource.contains("SoftShadowCaptionText"))
        XCTAssertFalse(overlaySource.contains(".drawingGroup("))
        XCTAssertFalse(overlaySource.contains(".blur("))
        XCTAssertFalse(overlaySource.contains(".shadow("))
        XCTAssertFalse(previewSource.contains("SoftShadowCaptionText"))
        XCTAssertFalse(previewSource.contains(".drawingGroup("))
        XCTAssertFalse(previewSource.contains(".blur("))
    }

    func testLiquidGlassAdditionalOpacityIsFixedAtZero() {
        XCTAssertEqual(OverlayGlassMetrics.fixedAdditionalOpacity, 0, accuracy: 0.0001)
    }

    func testLightAndDarkGlassHaveDistinctSubtleNativeTints() {
        XCTAssertGreaterThan(OverlayGlassMetrics.lightGlassTintOpacity, 0)
        XCTAssertLessThanOrEqual(OverlayGlassMetrics.lightGlassTintOpacity, 0.15)
        XCTAssertGreaterThan(OverlayGlassMetrics.darkGlassTintOpacity, 0)
        XCTAssertLessThanOrEqual(OverlayGlassMetrics.darkGlassTintOpacity, 0.25)
        XCTAssertGreaterThan(
            OverlayGlassMetrics.darkGlassTintOpacity,
            OverlayGlassMetrics.lightGlassTintOpacity
        )
    }

    func testHighTransparencyGlassIsNearlyClearWithSubtleBorder() {
        XCTAssertGreaterThan(OverlayGlassMetrics.highTransparencyGlassOpacity, 0)
        XCTAssertLessThanOrEqual(OverlayGlassMetrics.highTransparencyGlassOpacity, 0.05)
        XCTAssertGreaterThanOrEqual(OverlayGlassMetrics.highTransparencyBorderWidth, 1)
        XCTAssertGreaterThan(OverlayGlassMetrics.highTransparencyBorderOpacity, 0.25)
    }

    func testOverlayUsesNativeAppKitClearGlass() throws {
        let source = try String(
            contentsOf: workspaceRoot.appending(path: "LocalDualCaption/Overlay/OverlayGlassBackground.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("NSGlassEffectView"))
        XCTAssertTrue(source.contains("style = .clear"))
        XCTAssertTrue(source.contains("alphaValue = appearance == .highTransparency"))
        XCTAssertTrue(source.contains("OverlayGlassMetrics.highTransparencyGlassOpacity"))
        XCTAssertTrue(source.contains("OverlayGlassMetrics.lightGlassTintOpacity"))
        XCTAssertTrue(source.contains("OverlayGlassMetrics.darkGlassTintOpacity"))
        XCTAssertTrue(source.contains("case .highTransparency:"))
        XCTAssertTrue(source.contains("tintColor = nil"))
        XCTAssertFalse(source.contains("baseTint.withAlphaComponent"))
        XCTAssertTrue(source.contains("OverlayGlassAppearance"))
        XCTAssertTrue(source.contains(".aqua"))
        XCTAssertTrue(source.contains(".darkAqua"))
        XCTAssertFalse(source.contains(".glassEffect("))
    }

    func testSettingsExposeSegmentedGlassAppearanceWithoutSliderTickMarks() throws {
        let source = try String(
            contentsOf: workspaceRoot.appending(path: "LocalDualCaption/UI/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Glass appearance"))
        XCTAssertTrue(source.contains("OverlayGlassAppearance.light"))
        XCTAssertTrue(source.contains("OverlayGlassAppearance.dark"))
        XCTAssertTrue(source.contains("OverlayGlassAppearance.highTransparency"))
        XCTAssertTrue(source.contains("High Transparency"))
        XCTAssertTrue(source.contains(".pickerStyle(.segmented)"))
        XCTAssertFalse(source.contains("Glass opacity"))
        XCTAssertFalse(source.contains("$settings.backgroundOpacity"))
        XCTAssertFalse(source.contains("step:"))
    }

    func testEverySidebarPageSharesOneStartStopControl() throws {
        let source = try String(contentsOf: workspaceRoot.appending(path: "LocalDualCaption/UI/MainControlView.swift"), encoding: .utf8)
        let shell = try String(contentsOf: workspaceRoot.appending(path: "LocalDualCaption/UI/MainView.swift"), encoding: .utf8)
        XCTAssertTrue(shell.contains("NavigationSplitView"))
        XCTAssertTrue(shell.contains("CaptionControlBar(model: model, settings: settings)"))
        XCTAssertTrue(source.contains("model.running ? \"Stop Captions\" : \"Start Captions\""))
        XCTAssertTrue(source.contains("await model.stopCaptions()"))
        XCTAssertTrue(source.contains("await model.startCaptions()"))
        XCTAssertFalse(source.contains("$settings.glassAppearance"))
    }

    func testCaptionControlsKeepExistingBindingsAfterVisualRegrouping() throws {
        let mainSource = try String(
            contentsOf: workspaceRoot.appending(path: "LocalDualCaption/UI/MainControlView.swift"),
            encoding: .utf8
        )
        let languageSource = try String(
            contentsOf: workspaceRoot.appending(path: "LocalDualCaption/UI/LanguagePairControls.swift"),
            encoding: .utf8
        )
        let audioSource = try String(
            contentsOf: workspaceRoot.appending(path: "LocalDualCaption/UI/AudioSourcePicker.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(mainSource.contains("ControlPageScrollView(model: model, settings: settings"))
        XCTAssertTrue(mainSource.contains("captureLabel(\"Audio source\")"))
        XCTAssertTrue(mainSource.contains("captureLabel(\"Languages\")"))
        XCTAssertTrue(mainSource.contains("AudioSourcePicker(model: model)"))
        XCTAssertTrue(mainSource.contains("CaptionLanguagePairControls(model: model, settings: settings)"))
        XCTAssertTrue(mainSource.contains("CaptionSpeechRegionPicker(model: model, settings: settings)"))
        let playbackSource = try String(
            contentsOf: workspaceRoot.appending(path: "LocalDualCaption/UI/InterfaceStyle.swift"),
            encoding: .utf8
        )
        let settingsSource = try String(contentsOf: workspaceRoot.appending(path: "LocalDualCaption/UI/SettingsView.swift"), encoding: .utf8)
        XCTAssertTrue(settingsSource.contains("TranslationPlaybackControls(model: model, settings: settings)"))
        XCTAssertTrue(playbackSource.contains("model.translationVoiceOptions"))
        XCTAssertTrue(playbackSource.contains("$settings.translationVoiceIdentifier"))
        XCTAssertTrue(playbackSource.contains("model.toggleAutomaticTranslationSpeech()"))
        XCTAssertTrue(mainSource.contains("settings.availableSpeechVariants.count > 1"))
        XCTAssertFalse(mainSource.contains("\n                        LanguagePairControls(model: model"))
        XCTAssertTrue(languageSource.contains("struct CaptionLanguagePairControls"))
        XCTAssertTrue(languageSource.contains("struct CaptionSpeechRegionPicker"))
        XCTAssertTrue(languageSource.contains("struct CaptionLanguageOption"))
        XCTAssertTrue(languageSource.contains("ChineseScript.allCases.map"))
        XCTAssertTrue(languageSource.contains("arrow.left.arrow.right"))
        XCTAssertTrue(languageSource.contains(".help(\"Swap languages\")"))
        XCTAssertTrue(languageSource.contains("$0.language != settings.sourceLanguage"))
        XCTAssertTrue(audioSource.contains("Section(\"Microphones\")"))
        XCTAssertTrue(audioSource.contains("Section(\"System Audio\")"))
        XCTAssertTrue(audioSource.contains(".help(\"Refresh audio sources\")"))
        XCTAssertTrue(audioSource.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertFalse(audioSource.contains("Text(\"Audio source\")"))
    }

    func testMicrophoneCaptureBindsOnlyExplicitDevicesAndRecoversInPlace() throws {
        let catalogSource = try String(
            contentsOf: workspaceRoot.appending(
                path: "LocalDualCaption/Audio/MicrophoneDeviceCatalog.swift"
            ),
            encoding: .utf8
        )
        let captureSource = try String(
            contentsOf: workspaceRoot.appending(
                path: "LocalDualCaption/Audio/MicrophoneAudioCapture.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(catalogSource.contains("kAudioDevicePropertyDeviceUID"))
        XCTAssertTrue(catalogSource.contains("kAudioDevicePropertyScopeInput"))
        XCTAssertTrue(captureSource.contains("if !source.isSystemDefaultMicrophone"))
        XCTAssertTrue(captureSource.contains("setDeviceID(deviceID)"))
        XCTAssertTrue(captureSource.contains("scheduleRecovery(generation:"))
        XCTAssertTrue(captureSource.contains("recoverLocked(expectedGeneration:"))
        XCTAssertTrue(captureSource.contains("Keep the existing I/O unit and its selected device"))
        XCTAssertFalse(captureSource.contains("try startLocked(\n                source: source"))
        XCTAssertFalse(captureSource.contains("SCStreamOutputType.microphone"))
    }

    func testMicrophoneRecoveryBudgetPreventsAnInfiniteRestartLoop() {
        var budget = MicrophoneRecoveryBudget()

        for expectedAttempt in 1...MicrophoneRecoveryBudget.maximumConsecutiveAttempts {
            XCTAssertTrue(budget.beginAttempt())
            XCTAssertEqual(budget.consecutiveAttempts, expectedAttempt)
        }
        XCTAssertFalse(budget.beginAttempt())

        budget.markStable()
        XCTAssertEqual(budget.consecutiveAttempts, 0)
        XCTAssertTrue(budget.beginAttempt())
    }

    func testStoppingCaptionsAlwaysHidesTheOverlay() throws {
        let source = try String(
            contentsOf: workspaceRoot.appending(path: "LocalDualCaption/App/AppModel.swift"),
            encoding: .utf8
        )
        let stopFunction = try XCTUnwrap(
            source.range(of: "private func stopCaptions(finalStatus: CaptionStatus) async")
        )
        let stopBody = source[stopFunction.lowerBound...]

        XCTAssertTrue(stopBody.hasPrefix("private func stopCaptions(finalStatus: CaptionStatus) async {\n        hideOverlay()"))
    }

    func testLiquidGlassUsesGenerousContinuousCornerRadii() {
        XCTAssertGreaterThanOrEqual(OverlayGlassMetrics.overlayCornerRadius, 26)
        XCTAssertEqual(
            OverlayGlassMetrics.previewCornerRadius,
            OverlayGlassMetrics.overlayCornerRadius
        )
    }

    func testOverlayPreviewUsesTheSameCaptionGeometryAndTypography() throws {
        let source = try String(
            contentsOf: workspaceRoot.appending(
                path: "LocalDualCaption/UI/MainControlView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("OverlayGlassPreviewSurface("))
        XCTAssertTrue(source.contains("cornerRadius: OverlayGlassMetrics.overlayCornerRadius"))
        XCTAssertTrue(source.contains("OverlayGlassMetrics.captionPairSpacing"))
        XCTAssertTrue(source.contains("OverlayGlassMetrics.captionHorizontalPadding"))
        XCTAssertTrue(source.contains("OverlayGlassMetrics.captionVerticalPadding"))
        XCTAssertTrue(source.contains("alignment: .bottomLeading"))
        XCTAssertTrue(source.contains(".padding(OverlayGlassMetrics.captionOuterPadding)"))
        XCTAssertTrue(source.contains("size: settings.englishFontSize"))
        XCTAssertTrue(source.contains("size: settings.chineseFontSize"))
        XCTAssertFalse(source.contains("min(settings.englishFontSize"))
        XCTAssertFalse(source.contains("min(settings.chineseFontSize"))
    }

    @MainActor
    func testOverlayPreviewUsesLandscapeAndRespondsToEveryGlassMode() {
        let preview = OverlayGlassPreviewView(
            appearance: .light,
            cornerRadius: OverlayGlassMetrics.overlayCornerRadius
        )

        XCTAssertTrue(preview.hasLandscapeImageForTesting)
        XCTAssertEqual(preview.glassAppearanceForTesting?.name, .aqua)
        XCTAssertEqual(preview.glassOpacityForTesting, 1, accuracy: 0.001)
        XCTAssertEqual(
            preview.glassTintOpacityForTesting,
            OverlayGlassMetrics.lightGlassTintOpacity,
            accuracy: 0.001
        )
        XCTAssertEqual(
            preview.glassTintColorForTesting?.redComponent ?? -1,
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(preview.glassBorderWidthForTesting, 0, accuracy: 0.001)

        preview.apply(
            appearance: .dark,
            cornerRadius: OverlayGlassMetrics.overlayCornerRadius
        )
        XCTAssertEqual(preview.glassAppearanceForTesting?.name, .darkAqua)
        XCTAssertEqual(preview.glassOpacityForTesting, 1, accuracy: 0.001)
        XCTAssertEqual(
            preview.glassTintOpacityForTesting,
            OverlayGlassMetrics.darkGlassTintOpacity,
            accuracy: 0.001
        )
        XCTAssertEqual(
            preview.glassTintColorForTesting?.redComponent ?? -1,
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(preview.glassBorderWidthForTesting, 0, accuracy: 0.001)

        preview.apply(
            appearance: .highTransparency,
            cornerRadius: OverlayGlassMetrics.overlayCornerRadius
        )
        XCTAssertEqual(preview.glassAppearanceForTesting?.name, .aqua)
        XCTAssertEqual(
            preview.glassOpacityForTesting,
            OverlayGlassMetrics.highTransparencyGlassOpacity,
            accuracy: 0.001
        )
        XCTAssertNil(preview.glassTintColorForTesting)
        XCTAssertEqual(preview.glassTintOpacityForTesting, 0, accuracy: 0.001)
        XCTAssertEqual(
            preview.glassBorderWidthForTesting,
            OverlayGlassMetrics.highTransparencyBorderWidth,
            accuracy: 0.001
        )
        XCTAssertNotNil(
            Bundle(for: OverlayGlassPreviewView.self).url(
                forResource: "OverlayPreviewLandscape",
                withExtension: "png"
            )
        )
    }

    @MainActor
    func testStoredOverlayHeightIsClampedToSafeWindowBounds() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(10_000, forKey: OverlaySettings.Key.overlayHeight)
        let settings = OverlaySettings(defaults: defaults)

        XCTAssertEqual(settings.overlayHeight, OverlaySettings.overlayHeightRange.upperBound)
    }

    @MainActor
    func testCaptionContentCannotOverrideUserSelectedWindowHeight() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = OverlaySettings(defaults: defaults)
        settings.overlayHeight = 340
        let controller = CaptionPanelController(model: AppModel(), settings: settings)

        XCTAssertTrue(controller.hostingSizingOptionsForTesting.isEmpty)
        XCTAssertTrue(controller.isUserResizableForTesting)
        XCTAssertTrue(controller.hasWindowShadowForTesting)
        XCTAssertFalse(controller.isMovableByBackgroundForTesting)
        XCTAssertFalse(controller.ignoresMouseEventsForTesting)
        XCTAssertTrue(controller.supportsInactiveEdgeResizeForTesting)
        XCTAssertTrue(controller.supportsInactiveMovementForTesting)
        XCTAssertTrue(controller.usesLayeredNativeGlassForTesting)
        XCTAssertEqual(controller.glassStyleForTesting, .clear)
        XCTAssertEqual(
            controller.glassCornerRadiusForTesting,
            OverlayGlassMetrics.overlayCornerRadius,
            accuracy: 0.001
        )
        XCTAssertEqual(
            controller.glassTintOpacityForTesting,
            OverlayGlassMetrics.darkGlassTintOpacity,
            accuracy: 0.001
        )
        XCTAssertEqual(
            controller.glassTintColorForTesting?.redComponent ?? -1,
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(controller.glassOpacityForTesting, 1, accuracy: 0.001)
        XCTAssertEqual(controller.captionContentOpacityForTesting, 1, accuracy: 0.001)
        XCTAssertEqual(controller.explicitGlassAppearanceForTesting?.name, .darkAqua)
        XCTAssertEqual(controller.glassBorderWidthForTesting, 0, accuracy: 0.001)
        XCTAssertEqual(controller.panelSizeForTesting.height, 340, accuracy: 0.5)

        // Appearance changes must update the native material and its subtle mode tint
        // immediately, without changing the glass view's own opacity.
        settings.glassAppearance = .light
        XCTAssertEqual(controller.explicitGlassAppearanceForTesting?.name, .aqua)
        XCTAssertEqual(
            controller.glassTintColorForTesting?.redComponent ?? -1,
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            controller.glassTintOpacityForTesting,
            OverlayGlassMetrics.lightGlassTintOpacity,
            accuracy: 0.001
        )
        XCTAssertEqual(controller.glassOpacityForTesting, 1, accuracy: 0.001)
        XCTAssertEqual(controller.glassBorderWidthForTesting, 0, accuracy: 0.001)

        settings.glassAppearance = .highTransparency
        XCTAssertEqual(controller.explicitGlassAppearanceForTesting?.name, .aqua)
        XCTAssertNil(controller.glassTintColorForTesting)
        XCTAssertEqual(
            controller.glassOpacityForTesting,
            OverlayGlassMetrics.highTransparencyGlassOpacity,
            accuracy: 0.001
        )
        XCTAssertEqual(
            controller.glassBorderWidthForTesting,
            OverlayGlassMetrics.highTransparencyBorderWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(
            controller.glassBorderOpacityForTesting,
            OverlayGlassMetrics.highTransparencyBorderOpacity,
            accuracy: 0.001
        )
        XCTAssertEqual(controller.captionContentOpacityForTesting, 1, accuracy: 0.001)

        // Font changes alter the SwiftUI subtitle content's intrinsic height. They must not
        // resize the AppKit panel or write a different value back to the height slider.
        settings.englishFontSize = 42
        settings.chineseFontSize = 48
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(controller.panelSizeForTesting.height, 340, accuracy: 0.5)
        XCTAssertEqual(settings.overlayHeight, 340, accuracy: 0.5)

        // Even an unexpected AppKit resize must be corrected from the saved setting rather
        // than persisted back into it.
        controller.simulateUnexpectedResizeForTesting(height: 510)
        XCTAssertEqual(controller.panelSizeForTesting.height, 340, accuracy: 0.5)
        XCTAssertEqual(settings.overlayHeight, 340, accuracy: 0.5)

        // A native edge or corner drag is accepted, saved, and reflected by the Settings
        // sliders without allowing caption content to participate in window sizing.
        controller.simulateUserResizeForTesting(width: 1_040, height: 500)
        XCTAssertEqual(controller.panelSizeForTesting.width, 1_040, accuracy: 0.5)
        XCTAssertEqual(controller.panelSizeForTesting.height, 500, accuracy: 0.5)
        XCTAssertEqual(settings.overlayWidth, 1_040, accuracy: 0.5)
        XCTAssertEqual(settings.overlayHeight, 500, accuracy: 0.5)
        XCTAssertEqual(
            defaults.double(forKey: OverlaySettings.Key.overlayWidth),
            1_040,
            accuracy: 0.5
        )
        XCTAssertEqual(
            defaults.double(forKey: OverlaySettings.Key.overlayHeight),
            500,
            accuracy: 0.5
        )

        let reloaded = OverlaySettings(defaults: defaults)
        XCTAssertEqual(reloaded.overlayWidth, 1_040, accuracy: 0.5)
        XCTAssertEqual(reloaded.overlayHeight, 500, accuracy: 0.5)

        // Native resizing remains constrained to the same safe ranges as the sliders.
        controller.simulateUserResizeForTesting(width: 10_000, height: 10_000)
        XCTAssertEqual(
            controller.panelSizeForTesting.width,
            OverlaySettings.overlayWidthRange.upperBound,
            accuracy: 0.5
        )
        XCTAssertEqual(
            controller.panelSizeForTesting.height,
            OverlaySettings.overlayHeightRange.upperBound,
            accuracy: 0.5
        )
        XCTAssertEqual(settings.overlayWidth, OverlaySettings.overlayWidthRange.upperBound)
        XCTAssertEqual(settings.overlayHeight, OverlaySettings.overlayHeightRange.upperBound)
    }

    @MainActor
    func testInactiveOverlayResizeUsesEveryEdgeAndPreservesOppositeEdges() {
        let bounds = NSRect(x: 0, y: 0, width: 820, height: 260)

        XCTAssertEqual(
            CaptionWindowResizer.edges(at: NSPoint(x: 2, y: 2), in: bounds),
            [.left, .bottom]
        )
        XCTAssertEqual(
            CaptionWindowResizer.edges(at: NSPoint(x: 818, y: 258), in: bounds),
            [.right, .top]
        )
        XCTAssertEqual(
            CaptionWindowResizer.edges(at: NSPoint(x: 410, y: 2), in: bounds),
            [.bottom]
        )
        XCTAssertTrue(
            CaptionWindowResizer.edges(at: NSPoint(x: 410, y: 130), in: bounds).isEmpty
        )
        XCTAssertEqual(CaptionWindowResizer.cursorRegions(in: bounds).count, 8)

        let initial = NSRect(x: 100, y: 200, width: 820, height: 260)
        let bottomLeftResize = CaptionWindowResizer.resizedFrame(
            initialFrame: initial,
            mouseDelta: NSPoint(x: 100, y: 40),
            edges: [.left, .bottom]
        )
        XCTAssertEqual(bottomLeftResize.origin.x, 200, accuracy: 0.001)
        XCTAssertEqual(bottomLeftResize.origin.y, 240, accuracy: 0.001)
        XCTAssertEqual(bottomLeftResize.width, 720, accuracy: 0.001)
        XCTAssertEqual(bottomLeftResize.height, 220, accuracy: 0.001)
        XCTAssertEqual(bottomLeftResize.maxX, initial.maxX, accuracy: 0.001)
        XCTAssertEqual(bottomLeftResize.maxY, initial.maxY, accuracy: 0.001)

        let maximumResize = CaptionWindowResizer.resizedFrame(
            initialFrame: initial,
            mouseDelta: NSPoint(x: 10_000, y: 10_000),
            edges: [.right, .top]
        )
        XCTAssertEqual(
            maximumResize.width,
            OverlaySettings.overlayWidthRange.upperBound,
            accuracy: 0.001
        )
        XCTAssertEqual(
            maximumResize.height,
            OverlaySettings.overlayHeightRange.upperBound,
            accuracy: 0.001
        )

        let minimumResize = CaptionWindowResizer.resizedFrame(
            initialFrame: initial,
            mouseDelta: NSPoint(x: 10_000, y: 10_000),
            edges: [.left, .bottom]
        )
        XCTAssertEqual(
            minimumResize.width,
            OverlaySettings.overlayWidthRange.lowerBound,
            accuracy: 0.001
        )
        XCTAssertEqual(
            minimumResize.height,
            OverlaySettings.overlayHeightRange.lowerBound,
            accuracy: 0.001
        )
        XCTAssertEqual(minimumResize.maxX, initial.maxX, accuracy: 0.001)
        XCTAssertEqual(minimumResize.maxY, initial.maxY, accuracy: 0.001)

        let moved = CaptionWindowResizer.movedFrame(
            initialFrame: initial,
            mouseDelta: NSPoint(x: 85, y: -45)
        )
        XCTAssertEqual(moved.origin.x, 185, accuracy: 0.001)
        XCTAssertEqual(moved.origin.y, 155, accuracy: 0.001)
        XCTAssertEqual(moved.size.width, initial.size.width, accuracy: 0.001)
        XCTAssertEqual(moved.size.height, initial.size.height, accuracy: 0.001)
    }

    @MainActor
    func testBritishAndAmericanLocalesCanSwitch() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = OverlaySettings(defaults: defaults)
        settings.localeIdentifier = "en-US"
        XCTAssertEqual(defaults.string(forKey: OverlaySettings.Key.localeIdentifier), "en-US")
        settings.localeIdentifier = "en-GB"
        XCTAssertEqual(defaults.string(forKey: OverlaySettings.Key.localeIdentifier), "en-GB")
    }

    func testExactlyNineBidirectionalLanguageCategoriesAreExposed() {
        XCTAssertEqual(CaptionLanguage.allCases.count, 9)
        XCTAssertEqual(
            Set(CaptionLanguage.allCases.map(\.languageCode)),
            Set(["de", "en", "es", "fr", "it", "ja", "ko", "pt", "zh"])
        )
    }

    @MainActor
    func testLanguagePairAndChineseScriptsPersistAndReload() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = OverlaySettings(defaults: defaults)
        settings.setSourceLanguage(.chinese)
        settings.setSourceChineseScript(.traditional)
        settings.setTargetLanguage(.japanese)

        let reloaded = OverlaySettings(defaults: defaults)
        XCTAssertEqual(reloaded.sourceLanguage, .chinese)
        XCTAssertEqual(reloaded.sourceChineseScript, .traditional)
        XCTAssertEqual(reloaded.targetLanguage, .japanese)
        XCTAssertEqual(reloaded.localeIdentifier, "zh-TW")
    }

    @MainActor
    func testEveryBidirectionalLanguagePairSurvivesRepeatedSwitchAndReload() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for source in CaptionLanguage.allCases {
            let scripts: [ChineseScript] = source == .chinese ? ChineseScript.allCases : [.simplified]
            for script in scripts {
                for target in CaptionLanguage.allCases where target != source {
                    let settings = OverlaySettings(defaults: defaults)
                    settings.setSourceLanguage(source)
                    settings.setSourceChineseScript(script)
                    settings.setTargetLanguage(target)

                    let reloaded = OverlaySettings(defaults: defaults)
                    XCTAssertEqual(reloaded.sourceLanguage, source)
                    XCTAssertEqual(reloaded.sourceChineseScript, script)
                    XCTAssertEqual(reloaded.targetLanguage, target)
                    XCTAssertNotEqual(reloaded.sourceLanguage, reloaded.targetLanguage)
                    XCTAssertTrue(
                        reloaded.availableSpeechVariants.contains {
                            $0.localeIdentifier == reloaded.localeIdentifier
                        }
                    )
                }
            }
        }
    }

    @MainActor
    func testSelectingCurrentTargetAsSourcePreservesAValidBidirectionalPair() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = OverlaySettings(defaults: defaults)
        XCTAssertEqual(settings.sourceLanguage, .english)
        XCTAssertEqual(settings.targetLanguage, .chinese)

        settings.setSourceLanguage(.chinese)

        XCTAssertEqual(settings.sourceLanguage, .chinese)
        XCTAssertEqual(settings.targetLanguage, .english)
        XCTAssertEqual(settings.localeIdentifier, "zh-CN")
    }

    @MainActor
    func testSwapLanguagesAlsoSwapsChineseScriptSelection() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = OverlaySettings(defaults: defaults)
        settings.setTargetChineseScript(.traditional)
        settings.swapLanguages()

        XCTAssertEqual(settings.sourceLanguage, .chinese)
        XCTAssertEqual(settings.sourceChineseScript, .traditional)
        XCTAssertEqual(settings.targetLanguage, .english)
        XCTAssertEqual(settings.localeIdentifier, "zh-TW")
    }

    func testChineseTranslationIdentifiersFollowManualScriptSelection() {
        XCTAssertEqual(
            CaptionLanguageSelection(language: .chinese, chineseScript: .simplified)
                .translationLanguage.maximalIdentifier,
            "zh-Hans-CN"
        )
        XCTAssertEqual(
            CaptionLanguageSelection(language: .chinese, chineseScript: .traditional)
                .translationLanguage.languageCode?.identifier,
            "zh"
        )
    }

    @MainActor
    func testTranslationModelPreferencePersistsAndReloads() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = OverlaySettings(defaults: defaults)
        XCTAssertEqual(settings.translationModelPreference, .lowLatency)
        settings.translationModelPreference = .contextual

        XCTAssertEqual(
            defaults.string(forKey: OverlaySettings.Key.translationModelPreference),
            TranslationModelPreference.contextual.rawValue
        )
        XCTAssertEqual(OverlaySettings(defaults: defaults).translationModelPreference, .contextual)
    }

    @MainActor
    func testTranslationPauseIsFixedAtRequestedDefault() {
        XCTAssertEqual(OverlaySettings.translationPause, 0.75, accuracy: 0.001)
    }

    func testTranslationModelPreferencesMapToRequestedSystemStrategies() {
        if #available(macOS 26.4, *) {
            XCTAssertEqual(TranslationModelPreference.lowLatency.strategy, .lowLatency)
            XCTAssertEqual(TranslationModelPreference.contextual.strategy, .highFidelity)
        }
    }

    @MainActor
    func testAppLanguagePersistsAndReloads() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = OverlaySettings(defaults: defaults)
        XCTAssertEqual(settings.appLanguage, .english)
        settings.appLanguage = .simplifiedChinese

        XCTAssertEqual(defaults.string(forKey: OverlaySettings.Key.appLanguage), "zh-Hans")
        XCTAssertEqual(OverlaySettings(defaults: defaults).appLanguage, .simplifiedChinese)
    }

    @MainActor
    func testAllTenInterfaceLanguagesPersistAcrossRepeatedReloads() throws {
        let suiteName = "LocalDualCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for _ in 0..<10 {
            for language in AppLanguage.allCases {
                let settings = OverlaySettings(defaults: defaults)
                settings.appLanguage = language
                XCTAssertEqual(OverlaySettings(defaults: defaults).appLanguage, language)
            }
        }
    }

    func testSimplifiedChineseLocalizationIsBundled() {
        XCTAssertEqual(AppLanguage.simplifiedChinese.localized("Settings"), "设置")
        XCTAssertEqual(AppLanguage.simplifiedChinese.localized("Start Captions"), "开始字幕")
        XCTAssertEqual(AppLanguage.simplifiedChinese.localized("High quality"), "高质量")
        XCTAssertEqual(AppLanguage.simplifiedChinese.localized("Caption display"), "字幕显示")
        XCTAssertEqual(AppLanguage.simplifiedChinese.localized("Translation only"), "仅显示翻译")
        XCTAssertEqual(AppLanguage.simplifiedChinese.localized("Permissions"), "权限")
        XCTAssertEqual(AppLanguage.simplifiedChinese.localized("Ready for offline captions"), "已准备好离线字幕")
        XCTAssertEqual(AppLanguage.simplifiedChinese.localized("Languages"), "语言")
        XCTAssertEqual(AppLanguage.simplifiedChinese.localized("Speech region"), "语音地区")
        XCTAssertEqual(AppLanguage.simplifiedChinese.localized("Playback voice"), "播放音色")
        XCTAssertEqual(AppLanguage.simplifiedChinese.localized("Premium"), "高级")
        XCTAssertEqual(AppLanguage.simplifiedChinese.localized("Overlay appearance"), "悬浮字幕外观")
        XCTAssertEqual(AppLanguage.simplifiedChinese.localized("Appearance"), "外观")
        XCTAssertEqual(AppLanguage.simplifiedChinese.localized("About terminology"), "关于术语")
        XCTAssertEqual(AppLanguage.english.localized("Settings"), "Settings")
    }

    func testTenInterfaceLanguagesAreAvailable() {
        XCTAssertEqual(AppLanguage.allCases.count, 10)
        XCTAssertEqual(
            Set(AppLanguage.allCases.map(\.rawValue)),
            Set(["en", "zh-Hans", "zh-Hant", "de", "es", "fr", "it", "ja", "ko", "pt"])
        )
    }

    func testAdditionalInterfaceLocalizationsAreBundled() {
        XCTAssertEqual(AppLanguage.traditionalChinese.localized("Settings"), "設定")
        XCTAssertEqual(AppLanguage.german.localized("Settings"), "Einstellungen")
        XCTAssertEqual(AppLanguage.spanish.localized("Start Captions"), "Iniciar subtítulos")
        XCTAssertEqual(AppLanguage.french.localized("Target language"), "Langue cible")
        XCTAssertEqual(AppLanguage.italian.localized("App language"), "Lingua dell’app")
        XCTAssertEqual(AppLanguage.japanese.localized("Stop Captions"), "字幕を停止")
        XCTAssertEqual(AppLanguage.korean.localized("Source language"), "원본 언어")
        XCTAssertEqual(AppLanguage.portuguese.localized("Translation model"), "Modelo de tradução")
    }

    func testModelDownloadsUseCircularActivityIndicators() throws {
        let source = try String(
            contentsOf: workspaceRoot.appending(path: "LocalDualCaption/UI/PermissionsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("ActivityStatus"))
        XCTAssertTrue(source.contains(".progressViewStyle(.circular)"))
        XCTAssertFalse(source.contains(".progressViewStyle(.linear)"))
        XCTAssertFalse(source.contains("speechDownloadProgress"))
    }

    func testSettingsUseStateDrivenPermissionAndModelActions() throws {
        let settingsSource = try String(
            contentsOf: workspaceRoot.appending(path: "LocalDualCaption/UI/SettingsView.swift"),
            encoding: .utf8
        )
        let statusSource = try String(
            contentsOf: workspaceRoot.appending(path: "LocalDualCaption/UI/PermissionsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settingsSource.contains("title: \"Permissions and offline models\""))
        XCTAssertTrue(settingsSource.contains("PermissionsView(model: model)"))
        XCTAssertTrue(settingsSource.contains("OfflineModelsView(model: model, settings: settings)"))
        XCTAssertTrue(statusSource.contains("case .granted:"))
        XCTAssertTrue(statusSource.contains("Button(\"Allow\""))
        XCTAssertTrue(statusSource.contains("Button(\"Open Settings\""))
        XCTAssertTrue(statusSource.contains("Ready for offline captions"))
        XCTAssertTrue(statusSource.contains("DisclosureGroup(\"How to test offline\""))
        XCTAssertFalse(settingsSource.contains("Refresh status"))
        XCTAssertFalse(settingsSource.contains("Prepare offline models"))
        XCTAssertFalse(settingsSource.contains("Restore default vocabulary"))
        XCTAssertFalse(statusSource.contains(".font(.callout.monospaced())"))
    }

    func testProfessionalVocabularyHelpUsesClickPopover() throws {
        let source = try String(
            contentsOf: workspaceRoot.appending(path: "LocalDualCaption/UI/TranslationTerminologyView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("InterfaceHelpButton(title: \"About terminology\""))
        XCTAssertFalse(source.contains(".onHover"))
        let helpSource = try String(contentsOf: workspaceRoot.appending(path: "LocalDualCaption/UI/InterfaceStyle.swift"), encoding: .utf8)
        XCTAssertTrue(helpSource.contains(".popover(isPresented: $presented"))
        XCTAssertTrue(helpSource.contains(".accessibilityLabel(title)"))
        XCTAssertTrue(source.contains("up to 200 entries"))
        XCTAssertTrue(source.contains("Specified translations take priority"))
        XCTAssertTrue(source.contains("Rules stay on this Mac"))
    }

    func testSpeechPermissionBridgeIsExplicitlyNonisolated() throws {
        let source = try String(
            contentsOf: workspaceRoot.appending(path: "LocalDualCaption/App/AppModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private nonisolated static func requestSpeechAuthorization()"))
        XCTAssertTrue(source.contains("The system does not guarantee the execution"))
    }

    func testTerminationCancelsDownloadsAndHasAWatchdog() throws {
        let modelSource = try String(
            contentsOf: workspaceRoot.appending(path: "LocalDualCaption/App/AppModel.swift"),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: workspaceRoot.appending(path: "LocalDualCaption/App/LocalDualCaptionApp.swift"),
            encoding: .utf8
        )
        let translationSource = try String(
            contentsOf: workspaceRoot.appending(
                path: "LocalDualCaption/Translation/OnDeviceTranslationService.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(modelSource.contains("modelPreparationTask?.cancel()"))
        XCTAssertTrue(modelSource.contains("translationConfiguration = nil"))
        XCTAssertTrue(translationSource.contains("preparingSessionBox?.cancel()"))
        XCTAssertTrue(appSource.contains("Task.sleep(for: .seconds(2))"))
    }

    @MainActor
    func testTerminationLatchRejectsEverySubsequentStartRequest() async {
        let model = AppModel()

        XCTAssertFalse(model.beginTermination())
        for _ in 0..<100 {
            await model.startCaptions()
            XCTAssertFalse(model.starting)
            XCTAssertFalse(model.running)
            XCTAssertEqual(model.status, .stopped)
        }
    }

    func testNoNetworkClientEntitlementAndApprovedMicrophoneEntitlement() throws {
        let entitlements = try String(contentsOf: workspaceRoot.appending(path: "Config/LocalDualCaption.entitlements"), encoding: .utf8)
        XCTAssertFalse(entitlements.contains("com.apple.security.network.client"))
        XCTAssertTrue(entitlements.contains("com.apple.security.device.audio-input"))
        XCTAssertTrue(entitlements.contains("com.apple.security.app-sandbox"))
    }

    func testPrivacyUsageDescriptionsDeclareSelectedMicrophoneUse() throws {
        let plist = try String(contentsOf: workspaceRoot.appending(path: "Config/Info.plist"), encoding: .utf8)
        XCTAssertTrue(plist.contains("NSScreenCaptureUsageDescription"))
        XCTAssertTrue(plist.contains("NSSpeechRecognitionUsageDescription"))
        XCTAssertTrue(plist.contains("NSMicrophoneUsageDescription"))
        XCTAssertTrue(plist.contains("only after you select a microphone source"))
    }

    func testNoThirdPartyPackageOrNetworkSDK() throws {
        let project = try String(contentsOf: workspaceRoot.appending(path: "LocalDualCaption.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertFalse(project.contains("XCRemoteSwiftPackageReference"))
        XCTAssertFalse(project.contains("packageProductDependencies"))

        let sourceRoot = workspaceRoot.appending(path: "LocalDualCaption")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil))
        let forbidden = ["Alamofire", "OpenAI", "AWS", "Firebase", "MLX", "PyTorch", "Transformers"]
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                XCTAssertFalse(source.contains("import \(token)"), "Forbidden SDK import in \(file.lastPathComponent)")
            }
        }
    }

    private var workspaceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

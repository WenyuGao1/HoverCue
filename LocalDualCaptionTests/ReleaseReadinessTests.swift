import Foundation
import XCTest

final class ReleaseReadinessTests: XCTestCase {
    private let brand = "HoverCue"
    private let appBundleIdentifier = "com.wenyugao.hovercue"
    private let testBundleIdentifier = "com.wenyugao.hovercue.tests"

    private let allLocales = [
        "en", "zh-Hans", "zh-Hant", "de", "es",
        "fr", "it", "ja", "ko", "pt"
    ]

    private let nonEnglishLocales = [
        "zh-Hans", "zh-Hant", "de", "es", "fr", "it", "ja", "ko", "pt"
    ]

    private let releaseCriticalLocalizationKeys = [
        "Audio, recognition, and translation stay on this Mac. Text history is off by default and can be saved and exported only when you enable it.",
        "Microphone access is requested only after you select a microphone source or explicitly allow it.",
        "Live captions and translations may contain errors. For important content, verify against the original audio.",
        "macOS groups system-audio access under “Screen & System Audio Recording”. HoverCue registers audio only.",
        "Speech Recognition permission is required before the local model can be prepared.",
        "Model downloads are managed by macOS and may require internet the first time. HoverCue itself has no network-client permission.",
        "If macOS asks you to restart after a permission change, quit and reopen HoverCue."
    ]

    private let privacyPolicyLocalizationKeys = [
        "Privacy Policy",
        "Done",
        "On-device processing",
        "HoverCue processes audio, recognition, translation, and optional spoken translation on this Mac. Audio is never saved or uploaded.",
        "User-selected audio source",
        "HoverCue processes system audio or a selected microphone only when you select that source. It does not capture screen pixels, screenshots, or video.",
        "Optional local text history",
        "Text history is off at every app launch. After you confirm everyone is informed and agrees, new stable original text and translations can be saved locally and exported manually. You can delete saved history at any time.",
        "No accounts or tracking",
        "HoverCue has no accounts, analytics, advertising, or tracking.",
        "Settings stored locally",
        "App settings and terminology are saved in UserDefaults. Optional text history is stored separately in the app's local container, excluded from automatic backup. Exports go only to the location you choose; synced folders may sync them.",
        "Apple-managed language resources",
        "Speech and translation resources are managed by Apple and may be downloaded by macOS on demand. HoverCue has no network-client permission."
    ]

    func testFormalProductIdentityAndTestHostAreConsistent() throws {
        let project = try text(at: "LocalDualCaption.xcodeproj/project.pbxproj")
        let info = try propertyListDictionary(at: "Config/Info.plist")

        XCTAssertEqual(info["CFBundleDisplayName"] as? String, brand)
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "$(PRODUCT_BUNDLE_IDENTIFIER)")
        XCTAssertEqual(info["CFBundleName"] as? String, "$(PRODUCT_NAME)")
        XCTAssertEqual(info["CFBundleExecutable"] as? String, "$(EXECUTABLE_NAME)")
        XCTAssertEqual(info["CFBundleVersion"] as? String, "$(CURRENT_PROJECT_VERSION)")

        XCTAssertEqual(occurrenceCount("CURRENT_PROJECT_VERSION = 29;", in: project), 2)
        XCTAssertEqual(
            occurrenceCount("PRODUCT_BUNDLE_IDENTIFIER = \(appBundleIdentifier);", in: project),
            2
        )
        XCTAssertEqual(
            occurrenceCount("PRODUCT_BUNDLE_IDENTIFIER = \(testBundleIdentifier);", in: project),
            2
        )
        XCTAssertEqual(occurrenceCount("PRODUCT_NAME = \(brand);", in: project), 2)
        XCTAssertEqual(occurrenceCount("PRODUCT_MODULE_NAME = LocalDualCaption;", in: project), 2)
        XCTAssertEqual(
            occurrenceCount(
                "TEST_HOST = \"$(BUILT_PRODUCTS_DIR)/\(brand).app/Contents/MacOS/\(brand)\";",
                in: project
            ),
            2
        )
        XCTAssertTrue(project.contains("path = \(brand).app;"))
        XCTAssertTrue(project.contains("productName = \(brand);"))
    }

    func testEveryInfoPlistLocalizationUsesFormalNameAndAllPermissionKeys() throws {
        let expectedKeys: Set<String> = [
            "CFBundleDisplayName",
            "NSMicrophoneUsageDescription",
            "NSScreenCaptureUsageDescription",
            "NSSpeechRecognitionUsageDescription"
        ]

        for locale in allLocales {
            let path = "LocalDualCaption/\(locale).lproj/InfoPlist.strings"
            let strings = try stringsDictionary(at: path)

            XCTAssertEqual(Set(strings.keys), expectedKeys, "Unexpected keys in \(path)")
            XCTAssertEqual(strings["CFBundleDisplayName"], brand, "Wrong app name in \(path)")
            XCTAssertTrue(
                strings["NSScreenCaptureUsageDescription"]?.contains(brand) == true,
                "Screen/system-audio explanation must name \(brand) in \(path)"
            )
            XCTAssertTrue(
                strings["NSSpeechRecognitionUsageDescription"]?.contains(brand) == true,
                "Speech explanation must name \(brand) in \(path)"
            )
            XCTAssertTrue(
                strings["NSMicrophoneUsageDescription"]?.contains(brand) == true,
                "Microphone explanation must name \(brand) in \(path)"
            )
        }
    }

    func testCriticalReleaseCopyIsUsedBySourceAndFullyTranslated() throws {
        let sourcePaths = [
            "LocalDualCaption/Overlay/OverlaySettings.swift",
            "LocalDualCaption/UI/MainControlView.swift",
            "LocalDualCaption/UI/OnboardingView.swift",
            "LocalDualCaption/UI/SettingsView.swift"
        ]
        let source = try sourcePaths.map(text(at:)).joined(separator: "\n")

        for key in releaseCriticalLocalizationKeys {
            XCTAssertTrue(source.contains("\"\(key)\""), "Release copy is not used by source: \(key)")
        }

        for locale in nonEnglishLocales {
            let path = "LocalDualCaption/\(locale).lproj/Localizable.strings"
            let strings = try stringsDictionary(at: path)

            for key in releaseCriticalLocalizationKeys {
                let value = try XCTUnwrap(strings[key], "Missing key in \(path): \(key)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertNotEqual(value, key, "Untranslated English value in \(path): \(key)")
            }
        }
    }

    func testEveryStringsFileIsAValidPropertyListWithoutDuplicateKeys() throws {
        let localizationRoot = workspaceRoot.appending(path: "LocalDualCaption")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: localizationRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        let files = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "strings" else { return nil }
            return url
        }.sorted { $0.path < $1.path }

        XCTAssertEqual(files.count, 19, "Expected 10 InfoPlist and 9 Localizable files")

        for file in files {
            let data = try Data(contentsOf: file)
            let propertyList = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
            XCTAssertTrue(propertyList is [String: String], "Invalid strings dictionary: \(file.path)")

            let rawText = try String(contentsOf: file, encoding: .utf8)
            let keys = try rawKeys(in: rawText)
            let duplicates = Dictionary(grouping: keys, by: { $0 })
                .filter { $0.value.count > 1 }
                .keys
                .sorted()
            XCTAssertTrue(duplicates.isEmpty, "Duplicate keys in \(file.path): \(duplicates)")
        }
    }

    func testPrivacyPolicyIsNativeOfflineAccurateAndFullyLocalized() throws {
        let settings = try text(at: "LocalDualCaption/UI/SettingsView.swift")
        let policy = try text(at: "LocalDualCaption/UI/PrivacyPolicyView.swift")

        XCTAssertTrue(settings.contains("Label(\"Privacy Policy\""))
        XCTAssertTrue(settings.contains(".sheet(isPresented: $privacyPolicyPresented)"))
        XCTAssertTrue(settings.contains("PrivacyPolicyView()"))
        XCTAssertTrue(policy.contains("NavigationStack"))
        XCTAssertTrue(policy.contains("Button(\"Done\")"))

        for key in privacyPolicyLocalizationKeys {
            XCTAssertTrue(
                settings.contains("\"\(key)\"") || policy.contains("\"\(key)\""),
                "Privacy policy key is not used by native UI: \(key)"
            )
        }

        for forbidden in ["URL(", "Link(", "openURL", "NSWorkspace", "WebView", "WKWebView"] {
            XCTAssertFalse(policy.contains(forbidden), "Privacy policy must remain offline: \(forbidden)")
        }

        XCTAssertEqual(allLocales.count, 10)
        XCTAssertEqual(nonEnglishLocales.count, 9)
        for locale in nonEnglishLocales {
            let path = "LocalDualCaption/\(locale).lproj/Localizable.strings"
            let strings = try stringsDictionary(at: path)

            for key in privacyPolicyLocalizationKeys {
                let value = try XCTUnwrap(strings[key], "Missing privacy policy key in \(path): \(key)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertNotEqual(value, key, "Untranslated privacy policy value in \(path): \(key)")
            }
        }
    }

    func testFormalAppConfigurationHasOnlyApprovedPrivacyEntitlements() throws {
        let entitlements = try propertyListDictionary(at: "Config/LocalDualCaption.entitlements")
        let info = try propertyListDictionary(at: "Config/Info.plist")
        let project = try text(at: "LocalDualCaption.xcodeproj/project.pbxproj")

        XCTAssertEqual(
            Set(entitlements.keys),
            [
                "com.apple.security.app-sandbox",
                "com.apple.security.device.audio-input",
                "com.apple.security.personal-information.speech-recognition",
                "com.apple.security.files.user-selected.read-write"
            ]
        )
        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(
            entitlements["com.apple.security.device.audio-input"] as? Bool,
            true
        )
        XCTAssertEqual(
            entitlements["com.apple.security.personal-information.speech-recognition"] as? Bool,
            true
        )
        XCTAssertNotNil(info["NSScreenCaptureUsageDescription"])
        XCTAssertNotNil(info["NSMicrophoneUsageDescription"])
        XCTAssertNotNil(info["NSSpeechRecognitionUsageDescription"])
        XCTAssertTrue(project.contains("CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;"))

        let formalConfiguration = [
            try text(at: "Config/LocalDualCaption.entitlements"),
            try text(at: "Config/Info.plist"),
            project
        ].joined(separator: "\n")
        let forbiddenConfigurationKeys = [
            "com.apple.security.network.",
            "com.apple.security.device.camera",
            "NSCameraUsageDescription",
            "get-task-allow"
        ]
        for key in forbiddenConfigurationKeys {
            XCTAssertFalse(formalConfiguration.contains(key), "Forbidden app configuration: \(key)")
        }
    }

    func testFirstRunInterfaceStatesCaptureLimitsAndAccuracyWarning() throws {
        let onboarding = try text(at: "LocalDualCaption/UI/OnboardingView.swift")

        XCTAssertTrue(
            onboarding.contains(
                "Audio, recognition, and translation stay on this Mac. Text history is off by default and can be saved and exported only when you enable it."
            )
        )
        XCTAssertTrue(onboarding.contains("Microphone access is requested only"))
        XCTAssertTrue(onboarding.contains("No screen images are captured"))
        XCTAssertTrue(onboarding.contains("Text history is off by default"))
        XCTAssertTrue(
            onboarding.contains(
                "Live captions and translations may contain errors. For important content, verify against the original audio."
            )
        )
    }

    func testHistoryInterfaceAndConsentAreFullyLocalized() throws {
        let keys = [
            "Summary queued. It will run when live captions are stopped.",
            "Creating a title and bilingual summary on this Mac…",
            "AI-generated summary. Check important details against the full transcript.",
            "Summaries are generated on this Mac using Apple Intelligence. Bilingual content is processed locally. Check important details against the full transcript.",
            "This Mac does not support the local Apple Intelligence model. Your full history is available.",
            "Enable Apple Intelligence in System Settings to create local summaries. Your full history is available.",
            "Apple’s local model is not ready. Summaries will retry when it becomes available.",
            "Apple’s local model does not support this session’s languages. Your full history is available.",
            "A summary could not be created. It will retry after the next app launch. Your full history is available.",
            "There is not enough meaningful text to summarize. Your full history is available.",
            "Before enabling history, make sure everyone involved knows and agrees.",
            "Learn about history and privacy",
            "History is saved on this Mac. Exports go only to the location you choose.",
            "Generated with Apple Intelligence · On-device",
            "About AI summaries",
            "AI summary",
            "Full transcript",
            "Some entries are incomplete. The summary uses only available text.",
            "A bilingual AI summary is not available yet. The full transcript follows.",
            "When history is enabled, titles and bilingual summaries are created automatically on this Mac after captions stop, when Apple Intelligence is available.",
            "Confirm that everyone involved knows and agrees to local text recording, AI summaries and export. Only new stable sentences will be saved. Audio is never saved.",
            "The AI summary did not match the selected languages and was not displayed. It will retry after the next app launch. Your full history is available.",
            "Translation history",
            "Save translation history",
            "History ready for new captions",
            "Saving text history",
            "Enable translation history?",
            "Everyone informed and agreed — enable",
            "Review, export, or delete text saved with permission.",
            "Local text history",
            "No translation history",
            "Session",
            "Choose a session",
            "Saved sessions",
            "Export TXT",
            "Delete",
            "Clear all",
            "Dismiss",
            "Cancel",
            "Translation failed",
            "Translation incomplete",
            "Previous page",
            "Next page",
            "Delete this history?",
            "Clear all history?",
            "Original",
            "Translation",
            "On-device processing",
            "Optional local text history",
            "Before recording or exporting, make sure everyone involved knows and agrees. History is saved on this Mac.",
            "Off by default on every app launch. Turning it off keeps existing history; audio is never saved.",
            "Confirm that everyone involved knows and agrees to local text recording, AI summaries and export. Only new stable sentences will be saved. Audio is never saved.",
            "Enable history after obtaining permission, then start captions. Existing history remains available after recording is turned off.",
            "This cannot be undone. Exported files are not deleted.",
            "Recording will stop and all saved sessions will be deleted. Exported files are not deleted.",
            "Deleting history does not remove files you already exported. Storage is limited to 100 MB and 1,000 sessions.",
            "History could not be saved. Recording has stopped; live captions continue.",
            "History reached its safety limit. Recording has stopped. Delete older history to free space.",
            "A history entry exceeded its safety limit. Recording has stopped.",
            "History could not be opened. Existing files have been kept.",
            "History could not be deleted. Please try again.",
            "History exported. Files saved to a synced folder may be synced by your system.",
            "History could not be exported. Your existing file has not been replaced.",
            "Audio, recognition, and translation stay on this Mac. Text history is off by default and can be saved and exported only when you enable it.",
            "HoverCue processes audio, recognition, translation, and optional spoken translation on this Mac. Audio is never saved or uploaded.",
            "Text history is off at every app launch. After you confirm everyone is informed and agrees, new stable original text and translations can be saved locally and exported manually. You can delete saved history at any time.",
            "App settings and terminology are saved in UserDefaults. Optional text history is stored separately in the app's local container, excluded from automatic backup. Exports go only to the location you choose; synced folders may sync them."
        ]
        for locale in nonEnglishLocales {
            let strings = try stringsDictionary(at: "LocalDualCaption/\(locale).lproj/Localizable.strings")
            for key in keys {
                XCTAssertFalse(strings[key, default: ""].isEmpty, "Missing history copy in \(locale): \(key)")
            }
            let consent = "Before recording or exporting, make sure everyone involved knows and agrees. History is saved on this Mac."
            XCTAssertNotEqual(strings[consent], consent)
        }
    }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: workspaceRoot.appending(path: relativePath), encoding: .utf8)
    }

    private func propertyListDictionary(at relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: workspaceRoot.appending(path: relativePath))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any],
            "Expected a dictionary property list at \(relativePath)"
        )
    }

    private func stringsDictionary(at relativePath: String) throws -> [String: String] {
        let data = try Data(contentsOf: workspaceRoot.appending(path: relativePath))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: String],
            "Expected a strings dictionary at \(relativePath)"
        )
    }

    private func rawKeys(in text: String) throws -> [String] {
        let expression = try NSRegularExpression(
            pattern: #"(?m)^\s*"((?:\\.|[^"\\])*)"\s*="#
        )
        let entireText = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: entireText).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private func occurrenceCount(_ needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private var workspaceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

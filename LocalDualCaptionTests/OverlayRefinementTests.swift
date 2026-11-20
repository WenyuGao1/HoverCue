import AppKit
import SwiftUI
import XCTest
@testable import LocalDualCaption

final class OverlayRefinementTests: XCTestCase {
    @MainActor func testLegacyQualityModeMigratesOnceAndOtherChoicesSurvive() throws {
        let suite = "HoverCue.ModeMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("highQuality", forKey: OverlaySettings.Key.translationModelPreference)
        XCTAssertEqual(OverlaySettings(defaults: defaults).translationModelPreference, .contextual)
        XCTAssertEqual(defaults.string(forKey: OverlaySettings.Key.translationModelPreference), "contextual")
        XCTAssertEqual(OverlaySettings(defaults: defaults).translationModelPreference, .contextual)
        for mode in TranslationModelPreference.allCases {
            defaults.set(mode.rawValue, forKey: OverlaySettings.Key.translationModelPreference)
            XCTAssertEqual(OverlaySettings(defaults: defaults).translationModelPreference, mode)
        }
        defaults.removeObject(forKey: OverlaySettings.Key.translationModelPreference)
        XCTAssertEqual(OverlaySettings(defaults: defaults).translationModelPreference, .lowLatency)
        XCTAssertEqual(TranslationModelPreference.allCases, [.lowLatency, .contextual])
    }

    @MainActor private func withHistory(_ operation: (CaptionHistoryView, OverlaySettings) throws -> Void) throws {
        let suite = "HoverCue.BottomLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = OverlaySettings(defaults: defaults)
        settings.englishFontSize = 24; settings.chineseFontSize = 24
        let view = CaptionHistoryView()
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 240)
        defer { view.shutdown(); defaults.removePersistentDomain(forName: suite) }
        try operation(view, settings)
    }

    @MainActor func testShortSourceTranslationBilingualAndWaitingRowsStartAtBottom() throws {
        try withHistory { view, settings in
            let variants: [CaptionHistoryRow] = [
                .init(id: "short", source: "Hello."), .init(id: "short", translation: "你好。"),
                .init(id: "short", source: "Hello.", translation: "你好。"),
                .init(id: "short", source: "Waiting for source-language audio…", isInterim: true)
            ]
            for row in variants {
                view.update(rows: [row], generation: 1, settings: settings)
                let frame = try XCTUnwrap(view.rowFrameForTesting("short"))
                XCTAssertGreaterThan(frame.minY, 0)
                XCTAssertEqual(frame.maxY, view.viewportFrameForTesting.height, accuracy: 0.5)
                XCTAssertEqual(view.offsetForTesting, 0, accuracy: 0.5)
                XCTAssertFalse(view.indicatorVisibleForTesting)
            }
        }
    }

    @MainActor func testInterimAndCompletedTranslationRemainAtBottomThenOverflowNormally() throws {
        try withHistory { view, settings in
            let first = CaptionHistoryRow(id: "first", source: "First.", translation: "第一条。")
            view.update(rows: [first, .init(id: "live", source: "Still recognizing", isInterim: true)], generation: 1, settings: settings)
            XCTAssertEqual(try XCTUnwrap(view.rowFrameForTesting("live")).maxY, view.viewportFrameForTesting.height, accuracy: 0.5)
            view.update(rows: [first, .init(id: "live", source: "The current sentence is ready.", translation: "当前句子已完成。")], generation: 1, settings: settings)
            XCTAssertEqual(try XCTUnwrap(view.rowFrameForTesting("live")).maxY, view.viewportFrameForTesting.height, accuracy: 0.5)
            let many = (0..<10).map { CaptionHistoryRow(id: "\($0)", source: "Public sample \($0).", translation: "公开示例。") }
            view.update(rows: many, generation: 1, settings: settings)
            XCTAssertGreaterThan(view.maximumOffsetForTesting, 0)
            XCTAssertEqual(try XCTUnwrap(view.rowFrameForTesting("9")).maxY - view.offsetForTesting,
                           view.viewportFrameForTesting.height, accuracy: 0.5)
        }
    }

    @MainActor func testWindowAndFontChangesKeepShortContentAtBottomAndFittingHistoryResumesFollowing() throws {
        try withHistory { view, settings in
            view.update(rows: [.init(id: "one", source: "Short source.", translation: "简短译文。")], generation: 1, settings: settings)
            for size in [NSSize(width: 330, height: 300), NSSize(width: 600, height: 420)] {
                settings.englishFontSize = 36; settings.chineseFontSize = 36
                view.frame.size = size
                view.update(rows: [.init(id: "one", source: "Short source.", translation: "简短译文。")], generation: 1, settings: settings)
                XCTAssertEqual(try XCTUnwrap(view.rowFrameForTesting("one")).maxY, view.viewportFrameForTesting.height, accuracy: 0.5)
            }
            let rows = (0..<10).map { CaptionHistoryRow(id: "\($0)", source: "Public sample \($0).", translation: "公开示例。") }
            view.update(rows: rows, generation: 1, settings: settings)
            view.scrollForTesting(to: 0.3)
            XCTAssertFalse(view.followsLatest)
            view.frame.size.height = 4000
            view.needsLayout = true; view.layoutSubtreeIfNeeded()
            XCTAssertTrue(view.followsLatest)
            XCTAssertFalse(view.footerVisibleForTesting)
            XCTAssertEqual(try XCTUnwrap(view.rowFrameForTesting("9")).maxY, view.viewportFrameForTesting.height, accuracy: 0.5)
        }
    }

    private func luminance(_ color: NSColor) throws -> Double {
        let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
        func linear(_ x: CGFloat) -> Double { x <= 0.04045 ? Double(x) / 12.92 : pow((Double(x) + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }

    @MainActor func testButtonHasOpaqueHighContrastColorsAcrossAllGlassModesAndStates() throws {
        for appearance in OverlayGlassAppearance.allCases {
            for state in CaptionButtonState.allCases {
                let palette = CaptionButtonPalette.colors(appearance: appearance, state: state)
                XCTAssertEqual(palette.background.alphaComponent, 1)
                XCTAssertEqual(palette.foreground.alphaComponent, 1)
                let background = try luminance(palette.background)
                let foreground = try luminance(palette.foreground)
                let contrast = (max(background, foreground) + 0.05) / (min(background, foreground) + 0.05)
                XCTAssertGreaterThanOrEqual(contrast, 7, "Text and vector arrow must remain legible over the opaque button surface")
            }
            let button = CaptionLatestButton()
            button.title = "Back to latest"
            button.apply(appearance: appearance)
            XCTAssertEqual(button.alphaValue, 1)
            XCTAssertEqual(button.appearance?.name, appearance == .light ? .aqua : .darkAqua)
            button.highlight(true)
            XCTAssertEqual(button.currentPalette.background, CaptionButtonPalette.colors(appearance: appearance, state: .pressed).background)
            XCTAssertEqual(button.fittingSize.height, 28)
            XCTAssertTrue(button.acceptsFirstMouse(for: nil))
        }
    }

    @MainActor func testHostedCaptionViewUpdatesGlassAndFontWithoutNewSpeech() async throws {
        try await withHostedView { view, settings, host in
            let originalHeight = try XCTUnwrap(view.rowFrameForTesting("one")).height
            settings.glassAppearance = .dark
            settings.englishFontSize = 42
            for _ in 0..<50 {
                host.layoutSubtreeIfNeeded()
                if view.buttonAppearanceForTesting == .dark,
                   (view.rowFrameForTesting("one")?.height ?? 0) > originalHeight { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(view.buttonAppearanceForTesting, .dark)
            XCTAssertGreaterThan(try XCTUnwrap(view.rowFrameForTesting("one")).height, originalHeight)
        }
    }

    @MainActor private func withHostedView(_ operation: @MainActor (CaptionHistoryView, OverlaySettings, NSHostingView<CaptionHistoryScrollContent>) async throws -> Void) async throws {
        let suite = "HoverCue.CaptionSettingsUpdates.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = OverlaySettings(defaults: defaults)
        settings.englishFontSize = 24; settings.glassAppearance = .light
        let host = NSHostingView(rootView: CaptionHistoryScrollContent(rows: [.init(id: "one", source: "Public text.")], generation: 1, settings: settings))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 240)
        host.layoutSubtreeIfNeeded()
        func find(_ parent: NSView) -> CaptionHistoryView? {
            if let result = parent as? CaptionHistoryView { return result }
            return parent.subviews.lazy.compactMap(find).first
        }
        let view = try XCTUnwrap(find(host))
        defer { view.shutdown(); window.contentView = nil; defaults.removePersistentDomain(forName: suite) }
        try await operation(view, settings, host)
    }
}

import AppKit
import SwiftUI
import XCTest
@testable import LocalDualCaption

final class CaptionHistoryScrollTests: XCTestCase {
    private func rows(_ range: Range<Int>) -> [CaptionHistoryRow] {
        range.map { .init(id: String($0), source: "Public sample \($0): a longer sentence that wraps onto several lines in the small caption window.",
                         translation: "公开示例\($0)：这是一条用于测试滚动和换行的合成字幕。") }
    }

    @MainActor private func withHistory(_ operation: @MainActor (CaptionHistoryView, OverlaySettings) async throws -> Void) async throws {
        let suite = "HoverCue.CaptionHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = OverlaySettings(defaults: defaults)
        settings.englishFontSize = 24; settings.chineseFontSize = 24
        let view = CaptionHistoryView()
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 220)
        defer { view.shutdown(); defaults.removePersistentDomain(forName: suite) }
        view.update(rows: rows(0..<10), generation: 1, settings: settings)
        try await operation(view, settings)
    }

    @MainActor func testStartsAtLatestAndReturnButtonResumesFollowing() async throws {
        try await withHistory { view, settings in
            XCTAssertGreaterThan(view.maximumOffsetForTesting, 0)
            XCTAssertEqual(view.offsetForTesting, view.maximumOffsetForTesting, accuracy: 0.5)
            XCTAssertFalse(view.indicatorVisibleForTesting)
            view.scrollForTesting(to: 0.25)
            XCTAssertFalse(view.followsLatest)
            XCTAssertTrue(view.footerVisibleForTesting)
            view.returnToLatest()
            XCTAssertTrue(view.followsLatest)
            XCTAssertFalse(view.footerVisibleForTesting)
            view.update(rows: self.rows(1..<11), generation: 1, settings: settings)
            XCTAssertEqual(view.offsetForTesting, view.maximumOffsetForTesting, accuracy: 0.5)
        }
    }

    @MainActor func testNewCaptionAndTranslationCompletionPreserveReadingAnchor() async throws {
        try await withHistory { view, settings in
            view.scrollForTesting(to: 0.5)
            let before = try XCTUnwrap(view.topAnchorForTesting)
            var updated = self.rows(1..<11)
            // Text above the viewport changes height when its translation arrives.
            updated[0].translation = String(repeating: "合成译文发生换行。", count: 15)
            view.update(rows: updated, generation: 1, settings: settings)
            let after = try XCTUnwrap(view.topAnchorForTesting)
            XCTAssertEqual(after.0, before.0)
            XCTAssertEqual(after.1, before.1, accuracy: 0.5)
            XCTAssertFalse(view.followsLatest)
        }
    }

    @MainActor func testExpiringViewedOldestCaptionStaysAtEarliestRetainedCaption() async throws {
        try await withHistory { view, settings in
            view.scrollForTesting(to: 0)
            view.update(rows: self.rows(1..<11), generation: 1, settings: settings)
            XCTAssertEqual(view.topAnchorForTesting?.0, "1")
            XCTAssertEqual(view.offsetForTesting, 0, accuracy: 0.5)
            XCTAssertFalse(view.followsLatest)
        }
    }

    @MainActor func testInterimAndNarrowerWindowKeepSameReadingAnchor() async throws {
        try await withHistory { view, settings in
            view.scrollForTesting(to: 0.4)
            let before = try XCTUnwrap(view.topAnchorForTesting)
            view.update(rows: self.rows(0..<10) + [.init(id: "interim", source: "Public interim text", isInterim: true)], generation: 1, settings: settings)
            XCTAssertEqual(view.retainedRowCountForTesting, 11)
            view.frame.size.width = 330
            view.needsLayout = true; view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.topAnchorForTesting?.0, before.0)
            XCTAssertFalse(view.followsLatest)
            XCTAssertGreaterThanOrEqual(view.buttonFrameForTesting.minY, view.viewportFrameForTesting.maxY)
            XCTAssertGreaterThanOrEqual(view.indicatorFrameForTesting.minX, view.viewportFrameForTesting.maxX)
        }
    }

    @MainActor func testGenerationResetDiscardsOldReadingPositionAndRowsStayBounded() async throws {
        try await withHistory { view, settings in
            view.scrollForTesting(to: 0.2)
            view.update(rows: self.rows(0..<100), generation: 2, settings: settings)
            XCTAssertLessThanOrEqual(view.retainedRowCountForTesting, 11)
            XCTAssertTrue(view.followsLatest)
            XCTAssertEqual(view.offsetForTesting, view.maximumOffsetForTesting, accuracy: 0.5)
            XCTAssertFalse(view.indicatorVisibleForTesting)
        }
    }

    @MainActor func testIndicatorFadesAfterInteractionAndShortContentNeedsNoIndicator() async throws {
        try await withHistory { view, settings in
            view.scrollForTesting(to: 0.4)
            XCTAssertTrue(view.indicatorVisibleForTesting)
            try await Task.sleep(for: .milliseconds(1300))
            XCTAssertFalse(view.indicatorVisibleForTesting)
            XCTAssertFalse(view.followsLatest, "Hiding the indicator must not force a return to live captions")
            view.update(rows: [.init(id: "only", source: "Short")], generation: 2, settings: settings)
            view.scrollForTesting(to: 0)
            XCTAssertFalse(view.indicatorVisibleForTesting)
        }
    }

    @MainActor func testPanelRoutesOnlyVisibleControlsAndKeepsBackgroundDragging() async throws {
        try await withHistory { view, _ in
            let container = CaptionGlassContainerView(glassView: NSGlassEffectView(), captionContentView: view)
            container.frame = NSRect(x: 0, y: 0, width: 500, height: 220)
            view.frame = container.bounds
            view.needsLayout = true; view.layoutSubtreeIfNeeded()
            XCTAssertTrue(container.hitTest(NSPoint(x: 50, y: 100)) === container)
            view.scrollForTesting(to: 0.4)
            let point = NSPoint(x: view.buttonFrameForTesting.midX, y: view.buttonFrameForTesting.midY)
            let control = try XCTUnwrap(view.interactiveControl(at: point))
            XCTAssertTrue(container.hitTest(container.convert(point, from: view)) === control)
            XCTAssertTrue(container.hitTest(NSPoint(x: 1, y: 100)) === container, "Edge dragging remains reserved for resizing")
        }
    }

    @MainActor func testWheelEventMovesContentAndSuspendsFollowingBeforeNewTextArrives() async throws {
        try await withHistory { view, settings in
            let container = CaptionGlassContainerView(glassView: NSGlassEffectView(), captionContentView: view)
            container.frame = NSRect(x: 0, y: 0, width: 500, height: 220)
            view.frame = container.bounds
            view.needsLayout = true; view.layoutSubtreeIfNeeded()
            let start = view.offsetForTesting
            let cgEvent = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 180, wheel2: 0, wheel3: 0))
            let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
            container.scrollWheel(with: event)
            XCTAssertLessThan(view.offsetForTesting, start)
            XCTAssertFalse(view.followsLatest)
            let anchor = try XCTUnwrap(view.topAnchorForTesting)
            view.update(rows: self.rows(1..<11), generation: 1, settings: settings)
            XCTAssertEqual(view.topAnchorForTesting?.0, anchor.0)
            XCTAssertTrue(view.indicatorVisibleForTesting)
        }
    }

    @MainActor func testVisibleIndicatorSupportsDirectPositioningAndAccessibleAdjustment() async throws {
        try await withHistory { view, _ in
            view.scrollForTesting(to: 0.3)
            let frame = view.indicatorFrameForTesting
            let control = try XCTUnwrap(view.interactiveControl(at: NSPoint(x: frame.midX, y: frame.midY)))
            let before = view.offsetForTesting
            XCTAssertTrue(control.accessibilityPerformIncrement())
            XCTAssertGreaterThan(view.offsetForTesting, before)
            control.setAccessibilityValue(NSNumber(value: 0.1))
            XCTAssertEqual(view.offsetForTesting / view.maximumOffsetForTesting, 0.1, accuracy: 0.01)
            XCTAssertFalse(view.followsLatest)
        }
    }
}

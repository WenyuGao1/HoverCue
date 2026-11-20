import AppKit
import SwiftUI
import XCTest
@testable import LocalDualCaption

final class CaptionFeedbackLayoutTests: XCTestCase {
    func testErrorSummaryKeepsFullDetailsOutOfToolbar() {
        let detail = String(repeating: "Simulated layout error. ", count: 100)
        let feedback = CaptionFeedback(status: .error(detail), notice: detail)
        XCTAssertEqual(feedback.compactStatus(in: .english), "Error")
        XCTAssertEqual(feedback.errorMessage, detail)
        XCTAssertNil(feedback.visibleNotice, "An identical notice should not repeat the full error.")
        let permission = CaptionFeedback(status: .error("Speech Recognition permission is not granted."))
        XCTAssertTrue(permission.needsPermission)
        XCTAssertEqual(permission.compactStatus(in: .simplifiedChinese), "需要授权")
    }

    @MainActor
    func testToolbarHeightDoesNotGrowForErrorsOrLongNoticesInAnyLanguage() throws {
        let suiteName = "HoverCue.LayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = OverlaySettings(defaults: defaults)
        let model = AppModel(settings: settings)
        let longMessage = String(repeating: "Simulated long error with details. ", count: 100)
        let states: [CaptionFeedback] = [
            CaptionFeedback(status: .stopped),
            CaptionFeedback(status: .error("Speech Recognition permission is not granted.")),
            CaptionFeedback(status: .error(longMessage), notice: longMessage + "Additional notice.")
        ]
        for language in AppLanguage.allCases {
            settings.appLanguage = language
            for width in [520.0, 800.0] {
                var baseline: CGFloat?
                for feedback in states {
                    let view = NSHostingView(rootView:
                        CaptionControlBar(model: model, settings: settings)
                            .environment(\.captionFeedbackFixture, feedback)
                            .environment(\.locale, language.locale)
                            .frame(width: width)
                    )
                    view.frame = NSRect(x: 0, y: 0, width: width, height: 160)
                    view.layoutSubtreeIfNeeded()
                    let height = view.fittingSize.height
                    XCTAssertGreaterThan(height, 0)
                    XCTAssertLessThan(height, 160, "The toolbar must leave room for page content.")
                    if let baseline {
                        XCTAssertEqual(height, baseline, accuracy: 1,
                                       "Error text must not resize the toolbar: \(language.rawValue), \(width)")
                    } else {
                        baseline = height
                    }
                }
            }
        }
    }
}

import CoreGraphics
import XCTest
@testable import Pibo

@MainActor
final class HomeSpeechBubbleLayoutTests: XCTestCase {
    func testReferenceCanvasPlacesTheBubbleAtItsAuthoredBottomEdge() {
        XCTAssertEqual(
            HomeSpeechBubbleLayout.frameHeight(
                in: CGSize(width: 393, height: 852)
            ),
            367,
            accuracy: 0.000_001
        )
    }

    func testFillScaleUsesTheDominantCanvasDimension() {
        XCTAssertEqual(
            HomeSpeechBubbleLayout.frameHeight(
                in: CGSize(width: 786, height: 852)
            ),
            308,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            HomeSpeechBubbleLayout.frameHeight(
                in: CGSize(width: 393, height: 1_704)
            ),
            734,
            accuracy: 0.000_001
        )
    }

    func testAnchorPlacesTheTailJustAboveTheContainerButBelowTopChrome() {
        let screen = CGSize(width: 393, height: 852)
        XCTAssertEqual(
            HomeSpeechBubbleLayout.bottom(anchorY: 400, screenSize: screen, safeTop: 59),
            394,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            HomeSpeechBubbleLayout.bottom(anchorY: 120, screenSize: screen, safeTop: 59),
            239,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            HomeSpeechBubbleLayout.bottom(anchorY: nil, screenSize: screen, safeTop: 59),
            367,
            accuracy: 0.000_001
        )
    }

    func testFrameHeightNeverBecomesNegativeOnAnExtremelyWideCanvas() {
        XCTAssertEqual(
            HomeSpeechBubbleLayout.frameHeight(
                in: CGSize(width: 2_000, height: 100)
            ),
            0,
            accuracy: 0.000_001
        )
    }
}

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
            317,
            accuracy: 0.000_001
        )
    }

    func testFillScaleUsesTheDominantCanvasDimension() {
        XCTAssertEqual(
            HomeSpeechBubbleLayout.frameHeight(
                in: CGSize(width: 786, height: 852)
            ),
            208,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            HomeSpeechBubbleLayout.frameHeight(
                in: CGSize(width: 393, height: 1_704)
            ),
            634,
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

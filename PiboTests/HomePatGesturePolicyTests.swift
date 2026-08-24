import XCTest
@testable import Pibo

final class HomePatGesturePolicyTests: XCTestCase {
    func testOnlySecondTapTriggersPatCommand() {
        XCTAssertFalse(HomePatGesturePolicy.accepts(tapCount: 1))
        XCTAssertTrue(HomePatGesturePolicy.accepts(tapCount: 2))
        XCTAssertFalse(HomePatGesturePolicy.accepts(tapCount: 3))
    }
}

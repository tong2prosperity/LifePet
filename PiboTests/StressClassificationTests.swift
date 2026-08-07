import XCTest
@testable import Pibo

@MainActor
final class StressClassificationTests: XCTestCase {
    /// A notification can only be considered after classification. Six baseline
    /// days therefore produce no tier, while the seventh enables personal scoring.
    func testColdStartHasNoClassifiableLevelForNotifications() {
        let sixDays = StressBaseline(meanLn: log(46), sdLn: 0.08, dayCount: 6, geoMean: 46)
        let sevenDays = StressBaseline(meanLn: log(46), sdLn: 0.08, dayCount: 7, geoMean: 46)

        XCTAssertNil(StressScore.anchor(rmssd: 30, baseline: sixDays))
        XCTAssertNil(StressModel.level(rmssd: 30, baseline: sixDays, restingHR: 60))
        XCTAssertNotNil(StressModel.level(rmssd: 30, baseline: sevenDays, restingHR: 60))
    }
}

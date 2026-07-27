import XCTest
@testable import Pibo

/// Pins the agreement between the widget's 心情 bar and the stress tier the
/// 压力卡 / notification show.
///
/// 心情 used to come from Apple's SDNN against a 7-day arithmetic mean, while
/// every other stress surface read Pibo's own RMSSD against the log-normal
/// personal baseline. Two metrics, two baselines, one word — the widget could
/// call the same moment "calm" while the card called it 超载, and neither number
/// could be reconciled to the other. Both now ride `StressScore.anchor`.
@MainActor
final class StressMoodProjectionTests: XCTestCase {

    func testMoodMirrorsTheStressAnchor() {
        XCTAssertEqual(StressScore.moodPoints(forAnchor: 0), 100)
        XCTAssertEqual(StressScore.moodPoints(forAnchor: 1), 0)
        XCTAssertEqual(StressScore.moodPoints(forAnchor: 0.5), 50)
    }

    func testMoodDecreasesMonotonicallyWithStress() {
        let scores = stride(from: 0.0, through: 1.0, by: 0.05)
        let moods = scores.map(StressScore.moodPoints(forAnchor:))
        XCTAssertEqual(moods, moods.sorted(by: >), "calmer must never read as a lower 心情")
    }

    func testOutOfRangeAnchorsStayOnTheBar() {
        XCTAssertEqual(StressScore.moodPoints(forAnchor: -0.5), 100)
        XCTAssertEqual(StressScore.moodPoints(forAnchor: 1.5), 0)
    }

    /// The load-bearing alignment. `derivePetState` turns 心情 < 30 into a *sick*
    /// pet on the widget; `tier(for:)` turns a score past 0.70 into 超载. Those
    /// two edges are the same edge, so the widget can never show a healthy Pibo
    /// for a reading the 压力卡 calls 超载 — nor a sick one for a milder tier.
    func testSickThresholdCoincidesWithTheOverloadTier() {
        XCTAssertEqual(StressScore.moodPoints(forAnchor: 0.70), 30)

        // Just inside 超载 → below the 生病 line.
        XCTAssertEqual(StressScore.tier(for: 0.71), .overload)
        XCTAssertLessThan(StressScore.moodPoints(forAnchor: 0.71), 30)

        // Just outside it → at or above the line, and not the worst tier.
        XCTAssertNotEqual(StressScore.tier(for: 0.69), .overload)
        XCTAssertGreaterThanOrEqual(StressScore.moodPoints(forAnchor: 0.69), 30)
    }

    /// A reading at the wearer's own normal (z = 0) scores 0.30 in `pibo-core`,
    /// which must land in 正常 and read as a comfortably mid 心情 — not a
    /// borderline one. Guards against a future rescale quietly making "average"
    /// look bad.
    func testPersonalNormalReadsAsAnUnremarkableMood() {
        let baseline = StressBaseline(meanLn: log(46), sdLn: 0.08, dayCount: 15, geoMean: 46)
        let anchor = try? XCTUnwrap(StressScore.anchor(rmssd: 46, baseline: baseline))

        XCTAssertEqual(anchor ?? -1, 0.30, accuracy: 0.01)
        XCTAssertEqual(StressScore.tier(for: anchor ?? 1), .normal)
        XCTAssertEqual(StressScore.moodPoints(forAnchor: anchor ?? 1), 70, accuracy: 1)
    }
}

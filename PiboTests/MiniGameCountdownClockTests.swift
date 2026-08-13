import XCTest
@testable import Pibo

@MainActor
final class MiniGameCountdownClockTests: XCTestCase {
    func testPauseAndResumePreserveElapsedTime() {
        var clock = MiniGameCountdownClock(duration: 10)

        clock.resume(at: 100)
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: 104), 4)

        clock.pause(at: 106)
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: 500), 6)

        clock.resume(at: 700)
        XCTAssertEqual(clock.elapsed(at: 703), 9)
        XCTAssertEqual(clock.secondsLeft(at: 703), 1)
    }

    func testElapsedTimeCapsAtDurationAndCannotResumeAfterCompletion() {
        var clock = MiniGameCountdownClock(duration: 10)

        clock.resume(at: 100)
        XCTAssertEqual(clock.elapsed(at: 120), 10)
        XCTAssertEqual(clock.secondsLeft(at: 120), 0)

        clock.pause(at: 120)
        clock.resume(at: 200)
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: 500), 10)
    }

    func testSecondsLeftRoundsPartialSecondsUp() {
        var clock = MiniGameCountdownClock(duration: 10)

        clock.resume(at: 100)

        XCTAssertEqual(clock.secondsLeft(at: 104.2), 6)
        XCTAssertEqual(clock.secondsLeft(at: 109.9), 1)
    }

    func testClockDoesNotAccumulateNegativeElapsedTime() {
        var clock = MiniGameCountdownClock(duration: 10)

        clock.resume(at: 100)

        XCTAssertEqual(clock.elapsed(at: 90), 0)
        XCTAssertEqual(clock.secondsLeft(at: 90), 10)
    }
}

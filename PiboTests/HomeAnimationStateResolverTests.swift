import PiboCore
import XCTest
@testable import Pibo

@MainActor
final class HomeAnimationStateResolverTests: XCTestCase {
    func testResolverMapsOnlyTheCoreStateToAmbientArtwork() {
        XCTAssertEqual(resolve(.dataUnknown).stateID, "pibo-state-stable-forest-idle")
        XCTAssertEqual(resolve(.stable).stateID, "pibo-state-stable-forest-idle")
        XCTAssertEqual(resolve(.waking).stateID, "pibo-state-waking-hammock-idle")
        XCTAssertEqual(resolve(.energetic).stateID, "pibo-event-activity-milestone-celebrate")
        XCTAssertEqual(resolve(.tired).stateID, "pibo-state-tired-forest-idle")
        XCTAssertTrue(["pibo-state-sleeping-hammock-idle-a", "pibo-state-sleeping-hammock-idle-b"].contains(resolve(.sleeping).stateID))
    }

    func testResolutionPreservesSemanticDecision() {
        let resolution = resolve(.tired)
        XCTAssertEqual(resolution.state, .tired)
        XCTAssertEqual(resolution.decision.cause, .insufficientSleep)
    }

    private func resolve(_ state: PiboActivityState) -> HomeAnimationStateResolver.Resolution {
        let decision = PiboCoreStateAdapter.Decision(
            state: state,
            cause: state == .tired ? .insufficientSleep : .normalRhythm,
            sleepStartMinute: 23 * 60 + 30,
            wakeMinute: 7 * 60 + 30,
            routineSource: .personalAverage,
            routineSampleCount: 7,
            routineRegularity: 85,
            routineShiftMinutes: 0
        )
        return HomeAnimationStateResolver.resolve(.init(
            decision: decision,
            sleepDayKey: 20_260_814
        ))
    }
}

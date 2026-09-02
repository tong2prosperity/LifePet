import PiboCore
import XCTest
@testable import Pibo

@MainActor
final class HomeAnimationStateResolverTests: XCTestCase {
    func testResolverMapsOnlyTheCoreStateToAmbientArtwork() {
        XCTAssertEqual(resolve(.dataUnknown).stateID, "pibo-state-stable-forest-idle")
        XCTAssertEqual(resolve(.stable).stateID, "pibo-state-stable-forest-idle")
        XCTAssertEqual(resolve(.waking).stateID, "pibo-state-waking-hammock-idle")
        XCTAssertEqual(resolve(.energetic).stateID, PiboAnimationResourceID.stable)
        XCTAssertEqual(resolve(.tired).stateID, "pibo-state-tired-forest-idle")
        XCTAssertTrue(["pibo-state-sleeping-hammock-idle-a", "pibo-state-sleeping-hammock-idle-b"].contains(resolve(.sleeping).stateID))
    }

    func testGroundSleepShipsWhileGenericGroundWakeStillFallsBack() {
        let semantic = resolve(.sleeping)
        XCTAssertEqual(
            PiboAnimationStateMap.presentedAmbientStateID(
                semanticStateID: semantic.stateID,
                state: semantic.state,
                hasHammock: false
            ),
            PiboAnimationResourceID.sleepingGroundA
        )
        XCTAssertTrue(PiboAnimationResourceID.sleepingHammock.contains(
            PiboAnimationStateMap.presentedAmbientStateID(
                semanticStateID: semantic.stateID,
                state: semantic.state,
                hasHammock: true
            )
        ))

        let waking = resolve(.waking)
        XCTAssertEqual(
            PiboAnimationStateMap.presentedAmbientStateID(
                semanticStateID: waking.stateID,
                state: waking.state,
                hasHammock: false
            ),
            PiboAnimationResourceID.stable
        )
    }

    func testInsufficientSleepUsesRecoveringGroundWakeWithoutChangingSemanticState() {
        let waking = resolve(
            .waking,
            pendingState: .tired,
            pendingCause: .insufficientSleep
        )
        XCTAssertEqual(waking.state, .waking)
        XCTAssertEqual(
            PiboAnimationStateMap.presentedAmbientStateID(
                semanticStateID: waking.stateID,
                state: waking.state,
                hasHammock: false,
                needsWakingRecovery: waking.decision.pendingState == .tired
                    && waking.decision.pendingCause == .insufficientSleep
            ),
            PiboAnimationResourceID.wakingGroundRecovering
        )
        XCTAssertEqual(
            PiboAnimationStateMap.presentedAmbientStateID(
                semanticStateID: waking.stateID,
                state: waking.state,
                hasHammock: true,
                needsWakingRecovery: true
            ),
            PiboAnimationResourceID.wakingHammock
        )
    }

    private func resolve(
        _ state: PiboActivityState,
        pendingState: PiboActivityState? = nil,
        pendingCause: PiboCoreStateCause? = nil
    ) -> HomeAnimationStateResolver.Resolution {
        let decision = PiboCoreStateAdapter.Decision(
            state: state,
            cause: state == .tired ? .insufficientSleep : .normalRhythm,
            pendingState: pendingState,
            pendingCause: pendingCause,
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

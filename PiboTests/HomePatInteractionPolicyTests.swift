import XCTest
@testable import Pibo

final class HomePatInteractionPolicyTests: XCTestCase {
    func testEveryShippedStateKeepsItsRestingClassification() {
        let sleepingStates = PiboAnimationResourceID.sleeping

        for stateID in PiboAnimationStateMap.available {
            let context = HomePatInteractionPolicy.stateContext(for: stateID)
            let expectedSleeping = sleepingStates.contains(stateID)
            let expectedResting = expectedSleeping
                || stateID == PiboAnimationResourceID.wakingHammock
                || stateID == PiboAnimationResourceID.wakingGroundRecovering

            XCTAssertEqual(context.sleeping, expectedSleeping, stateID)
            XCTAssertEqual(context.resting, expectedResting, stateID)
            XCTAssertEqual(context.countsTowardAngry, !expectedResting, stateID)
        }
    }

    func testAngryEntryUsesImmediateAuthoredContentAndReaction() {
        XCTAssertEqual(
            HomePatInteractionPolicy.speechRoute(
                sourceStateID: "pibo-state-stable-forest-idle",
                targetStateID: "angry",
                angryEntered: true
            ),
            .immediateAnimation(
                contentID: "animation.angry.enter",
                reaction: .angry
            )
        )
    }

    func testSleepingStatesUseImmediateProtectedNotice() {
        for stateID in PiboAnimationResourceID.sleeping {
            XCTAssertEqual(
                HomePatInteractionPolicy.speechRoute(
                    sourceStateID: stateID,
                    targetStateID: stateID,
                    angryEntered: false
                ),
                .immediateAnimation(
                    contentID: "animation.sleep.pat",
                    reaction: .protectedState
                )
            )
        }
    }

    func testAwakeStateConsumesSpeechPolicyBeforeShowingAuthoredLine() {
        XCTAssertEqual(
            HomePatInteractionPolicy.speechRoute(
                sourceStateID: "pibo-state-waking-hammock-idle",
                targetStateID: "pibo-state-waking-hammock-idle",
                angryEntered: false
            ),
            .conditionalAnimation(
                contentID: "animation.awake.pat",
                presentsWhenAllowed: true
            )
        )
    }

    func testEveryOrdinaryAndUnknownStateUsesResolvedSpeech() {
        let specialStates = PiboAnimationResourceID.sleeping.union([
            PiboAnimationResourceID.wakingHammock,
            PiboAnimationResourceID.wakingGroundRecovering,
            "angry",
        ])
        let ordinaryStates = PiboAnimationStateMap.available.subtracting(specialStates)

        for stateID in ordinaryStates.union(["future-state"]) {
            XCTAssertEqual(
                HomePatInteractionPolicy.speechRoute(
                    sourceStateID: stateID,
                    targetStateID: stateID,
                    angryEntered: false
                ),
                .resolvedSpeech
            )
        }
    }

    func testAngrySourceOrTargetWithoutEntryRemainsSilent() {
        XCTAssertEqual(
            HomePatInteractionPolicy.speechRoute(
                sourceStateID: "angry",
                targetStateID: "pibo-state-stable-forest-idle",
                angryEntered: false
            ),
            .silent
        )
        XCTAssertEqual(
            HomePatInteractionPolicy.speechRoute(
                sourceStateID: "pibo-state-stable-forest-idle",
                targetStateID: "angry",
                angryEntered: false
            ),
            .silent
        )
    }

    func testAnalyticsReactionValuesRemainStable() {
        XCTAssertEqual(HomePatInteractionPolicy.Reaction.angry.rawValue, "angry")
        XCTAssertEqual(
            HomePatInteractionPolicy.Reaction.protectedState.rawValue,
            "protected_state"
        )
        XCTAssertEqual(HomePatInteractionPolicy.Reaction.silent.rawValue, "silent")
        XCTAssertEqual(HomePatInteractionPolicy.Reaction.spoke.rawValue, "spoke")
        XCTAssertEqual(
            HomePatInteractionPolicy.conditionalReaction(shouldPresent: true),
            .protectedState
        )
        XCTAssertEqual(
            HomePatInteractionPolicy.conditionalReaction(shouldPresent: false),
            .silent
        )
        XCTAssertEqual(
            HomePatInteractionPolicy.resolvedSpeechReaction(hasSpeech: true),
            .spoke
        )
        XCTAssertEqual(
            HomePatInteractionPolicy.resolvedSpeechReaction(hasSpeech: false),
            .silent
        )
    }
}

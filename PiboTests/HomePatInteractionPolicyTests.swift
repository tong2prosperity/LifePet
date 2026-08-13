import XCTest
@testable import Pibo

final class HomePatInteractionPolicyTests: XCTestCase {
    func testEveryShippedStateKeepsItsRestingClassification() {
        let sleepingStates: Set<String> = ["sleep-1", "sleep-2"]

        for stateID in PiboAnimationStateMap.available {
            let context = HomePatInteractionPolicy.stateContext(for: stateID)
            let expectedSleeping = sleepingStates.contains(stateID)
            let expectedResting = expectedSleeping || stateID == "awake"

            XCTAssertEqual(context.sleeping, expectedSleeping, stateID)
            XCTAssertEqual(context.resting, expectedResting, stateID)
            XCTAssertEqual(context.countsTowardAngry, !expectedResting, stateID)
        }
    }

    func testAngryEntryUsesImmediateAuthoredContentAndReaction() {
        XCTAssertEqual(
            HomePatInteractionPolicy.speechRoute(
                sourceStateID: "default",
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
        for stateID in ["sleep-1", "sleep-2"] {
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
                sourceStateID: "awake",
                targetStateID: "awake",
                angryEntered: false
            ),
            .conditionalAnimation(
                contentID: "animation.awake.pat",
                presentsWhenAllowed: true
            )
        )
    }

    func testEveryOrdinaryAndUnknownStateUsesResolvedSpeech() {
        let specialStates: Set<String> = ["sleep-1", "sleep-2", "awake", "angry"]
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
                targetStateID: "default",
                angryEntered: false
            ),
            .silent
        )
        XCTAssertEqual(
            HomePatInteractionPolicy.speechRoute(
                sourceStateID: "default",
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

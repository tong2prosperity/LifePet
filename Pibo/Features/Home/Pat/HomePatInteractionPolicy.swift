enum HomePatInteractionPolicy {
    struct StateContext: Equatable {
        let sleeping: Bool
        let resting: Bool
        let countsTowardAngry: Bool
    }

    enum Reaction: String, Equatable {
        case angry
        case protectedState = "protected_state"
        case silent
        case spoke
    }

    enum SpeechRoute: Equatable {
        case immediateAnimation(contentID: String, reaction: Reaction)
        case conditionalAnimation(contentID: String, presentsWhenAllowed: Bool)
        case resolvedSpeech
        case silent
    }

    static func stateContext(for stateID: String) -> StateContext {
        let sleeping = PiboAnimationResourceID.sleeping.contains(stateID)
        let resting = sleeping
            || stateID == PiboAnimationResourceID.wakingHammock
            || stateID == PiboAnimationResourceID.wakingGroundRecovering
        return StateContext(
            sleeping: sleeping,
            resting: resting,
            countsTowardAngry: PiboCorePatAdapter.countsTowardAngry(
                restingState: resting
            )
        )
    }

    static func speechRoute(
        sourceStateID: String,
        targetStateID: String,
        angryEntered: Bool
    ) -> SpeechRoute {
        if let contentID = PiboCoreAnimationAdapter.patContentID(
            stateID: targetStateID,
            angryEntered: angryEntered
        ) {
            let isSleepNotice = contentID == "animation.sleep.pat"
            if angryEntered || isSleepNotice {
                return .immediateAnimation(
                    contentID: contentID,
                    reaction: angryEntered ? .angry : .protectedState
                )
            }
            return .conditionalAnimation(
                contentID: contentID,
                presentsWhenAllowed: contentID == "animation.awake.pat"
            )
        }
        guard sourceStateID != "angry", targetStateID != "angry" else {
            return .silent
        }
        return .resolvedSpeech
    }

    static func conditionalReaction(shouldPresent: Bool) -> Reaction {
        shouldPresent ? .protectedState : .silent
    }

    static func resolvedSpeechReaction(hasSpeech: Bool) -> Reaction {
        hasSpeech ? .spoke : .silent
    }
}

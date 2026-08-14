import PiboCore

/// Event animation policy layered over the single ambient state from Core.
/// This adapter never derives another health state.
enum PiboCoreAnimationAdapter {
    enum TransitionIntent: Equatable {
        case hardCut
        case bounceCut
    }

    static func ambientStateID(
        for state: PiboActivityState,
        sleepDayKey: Int64 = 0,
        postPluckSleep: Bool = false
    ) -> String {
        switch state {
        case .dataUnknown, .stable:
            PiboAnimationResourceID.stable
        case .sleeping:
            switch PiboCoreAnimation.sleepVariant(
                dayKey: sleepDayKey,
                postPluckSleep: postPluckSleep
            ) {
            case .sleep1: PiboAnimationResourceID.sleepingHammockA
            case .sleep2: PiboAnimationResourceID.sleepingHammockB
            }
        case .waking:
            PiboAnimationResourceID.wakingHammock
        case .energetic:
            // Temporary use of the closest shipped pose until the dedicated
            // energetic ambient artwork is added.
            PiboAnimationResourceID.activityMilestoneCelebrate
        case .tired:
            PiboAnimationResourceID.tired
        }
    }

    static func stepsCrossed(previous: Int, current: Int) -> Bool {
        PiboCoreAnimation.stepsCrossed(
            previous: UInt32(clamping: previous),
            current: UInt32(clamping: current)
        )
    }

    static func achievementContentID(
        kind: PiboAnimationAchievementKind,
        modal: Bool
    ) -> String? {
        let achievement: PiboCoreAnimationAchievement = switch kind {
        case .pigu: .pigu
        case .muscle: .muscle
        }
        return PiboCoreAnimation.contentKey(for: achievement, modal: modal).contentID
    }

    static func achievementPresentationAllowed(in stateID: String) -> Bool {
        !PiboAnimationResourceID.sleepingHammock.contains(stateID)
    }

    static func angryShouldStart(
        state: PiboActivityState,
        recentActualPatCount: Int,
        angryActive: Bool
    ) -> Bool {
        PiboCoreAnimation.angryShouldStart(
            ambientState: state.core,
            recentActualPatCount: recentActualPatCount,
            angryActive: angryActive
        )
    }

    static func patContentID(stateID: String, angryEntered: Bool) -> String? {
        PiboCoreAnimation.patContentKey(
            state: semanticState(for: stateID).core,
            angryEntered: angryEntered
        ).contentID
    }

    static func transitionIntent(
        stateID: String,
        angryEntered: Bool
    ) -> TransitionIntent {
        switch PiboCoreAnimation.transitionIntent(
            ambientState: semanticState(for: stateID).core,
            angryEntered: angryEntered
        ) {
        case .hardCut: .hardCut
        case .bounceCut: .bounceCut
        }
    }

    static func semanticState(for stateID: String) -> PiboActivityState {
        switch stateID {
        case PiboAnimationResourceID.sleepingHammockA,
             PiboAnimationResourceID.sleepingHammockB: .sleeping
        case PiboAnimationResourceID.wakingHammock: .waking
        case PiboAnimationResourceID.activityMilestoneCelebrate: .energetic
        case PiboAnimationResourceID.tired, "weak": .tired
        default: .stable
        }
    }
}

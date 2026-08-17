import PiboCore

/// Event animation policy layered over the single ambient state from Core.
/// This adapter never derives another health state.
enum PiboCoreAnimationAdapter {
    enum ContextualAction: String, Equatable, Sendable {
        case checkConnection
        case letSleep
        case morningGreeting
        case checkIn
        case play
        case rest

        var duration: Duration {
            switch self {
            case .checkIn: .milliseconds(360)
            case .checkConnection, .letSleep: .milliseconds(900)
            case .morningGreeting, .rest: .milliseconds(1_100)
            case .play: .milliseconds(1_300)
            }
        }
    }

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
            // The semantic state stays in Core, but the incomplete energetic
            // artwork is deliberately absent from the current App.
            PiboAnimationResourceID.stable
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

    static func contextualAction(for state: PiboActivityState) -> ContextualAction {
        switch PiboCoreAnimation.contextualAction(state: state.core) {
        case .checkConnection: .checkConnection
        case .letSleep: .letSleep
        case .morningGreeting: .morningGreeting
        case .checkIn: .checkIn
        case .play: .play
        case .rest: .rest
        }
    }

    static func contextualActionCountsTowardAngry(for state: PiboActivityState) -> Bool {
        PiboCoreAnimation.contextualActionCountsTowardAngry(state: state.core)
    }

    static func accessibilityLabel(for state: PiboActivityState) -> String {
        switch contextualAction(for: state) {
        case .checkConnection:
            AppLocalization.text("Pibo 暂时没有收到健康数据，点按可查看原因")
        case .letSleep:
            AppLocalization.text("Pibo 正在睡觉，点按可轻轻看一眼")
        case .morningGreeting:
            AppLocalization.text("Pibo 刚刚醒来，点按可和它说早安")
        case .checkIn:
            AppLocalization.text("Pibo 状态平稳，点按可摸一摸")
        case .play:
            AppLocalization.text("Pibo 精力充足，点按可和它玩一下")
        case .rest:
            AppLocalization.text("Pibo 当前疲惫，点按可让它休息")
        }
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
        !PiboAnimationResourceID.sleeping.contains(stateID)
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
        if PiboAnimationResourceID.sleeping.contains(stateID) { return .sleeping }
        if stateID == PiboAnimationResourceID.activityMilestoneCelebrate {
            return .energetic
        }
        return switch stateID {
        case PiboAnimationResourceID.wakingHammock,
             PiboAnimationResourceID.wakingGroundRecovering: .waking
        case PiboAnimationResourceID.tired, "weak": .tired
        default: .stable
        }
    }
}

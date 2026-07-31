import Foundation
import PiboCore

/// Converts app-domain state into the stable Rust animation decision.
///
/// The mapping itself lives in Core beside the six-state machine, because both
/// platforms have to agree on what Pibo is doing — the artwork and the playback
/// are each platform's business, the choice is not.
enum PiboCoreAnimationAdapter {
    enum TransitionIntent: Equatable {
        case hardCut
        case bounceCut
    }

    struct SleepReference: Equatable {
        let hours: Double
        let validNights: Int
        let hasPersonalBaseline: Bool
    }

    static func sleepReference(history: [Double]) -> SleepReference {
        let value = PiboCoreAnimation.sleepReference(history: history)
        return SleepReference(
            hours: value.hours,
            validNights: value.validNights,
            hasPersonalBaseline: value.hasPersonalBaseline
        )
    }

    static func completeAmbientStateID(
        localHour: Double,
        hasSleepData: Bool,
        sleepHours: Double,
        sleepReferenceHours: Double,
        hasActivityData: Bool,
        steps: Int,
        hasWorkoutToday: Bool,
        postPluckSleep: Bool,
        sleepDayKey: Int64,
        angryActive: Bool,
        hasEligibleRMSSD: Bool,
        stressBaselineDays: Int,
        stressZ: Double,
        rmssdAgeSeconds: Double,
        previousStressStateID: String
    ) -> String {
        let previous = PiboCoreAnimationState.allCases.first {
            $0.contentID == previousStressStateID
        } ?? .default
        return PiboCoreAnimation.ambientState(
            input: PiboCoreAnimationInput(
                localHour: localHour,
                hasSleepData: hasSleepData,
                sleepHours: sleepHours,
                sleepReferenceHours: sleepReferenceHours,
                hasActivityData: hasActivityData,
                steps: UInt32(clamping: steps),
                hasWorkoutToday: hasWorkoutToday,
                postPluckSleep: postPluckSleep,
                sleepDayKey: sleepDayKey,
                angryActive: angryActive,
                hasEligibleRMSSD: hasEligibleRMSSD,
                stressBaselineDays: UInt32(clamping: stressBaselineDays),
                stressZ: stressZ,
                rmssdAgeSeconds: rmssdAgeSeconds,
                previousStressState: previous
            )
        ).contentID
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

    /// Stress hysteresis survives states that merely cover it by priority.
    /// It resets only when Core reaches a state below the stress decision.
    static func nextStressMemoryStateID(
        decidedStateID: String,
        previousStressStateID: String
    ) -> String {
        switch decidedStateID {
        case "dive", "coolhide": decidedStateID
        case "sleep-1", "sleep-2", "angry", "weak", "tired", "boring":
            previousStressStateID
        default: "default"
        }
    }

    static func achievementPresentationAllowed(in stateID: String) -> Bool {
        stateID != "sleep-1" && stateID != "sleep-2"
    }

    /// App-owned persisted achievement poses sit above continuous health
    /// states, but never cover sleep or an active angry interval.
    static func stateIDByApplyingAchievementHold(
        to decidedStateID: String,
        held: PiboAnimationAchievementKind?
    ) -> String {
        guard decidedStateID != "sleep-1",
              decidedStateID != "sleep-2",
              decidedStateID != "angry",
              let held
        else { return decidedStateID }
        return held.rawValue
    }

    static func angryShouldStart(
        localHour: Double,
        recentActualPatCount: Int,
        angryActive: Bool
    ) -> Bool {
        PiboCoreAnimation.angryShouldStart(
            localHour: localHour,
            recentActualPatCount: recentActualPatCount,
            angryActive: angryActive
        )
    }

    static func patContentID(stateID: String, angryEntered: Bool) -> String? {
        guard let state = PiboCoreAnimationState.allCases.first(where: { $0.contentID == stateID }) else {
            return nil
        }
        return PiboCoreAnimation.patContentKey(state: state, angryEntered: angryEntered).contentID
    }

    static func transitionIntent(
        fromStateID: String,
        toStateID: String,
        angryEntered: Bool
    ) -> TransitionIntent {
        guard let from = PiboCoreAnimationState.allCases.first(where: {
            $0.contentID == fromStateID
        }), let to = PiboCoreAnimationState.allCases.first(where: {
            $0.contentID == toStateID
        }) else { return .hardCut }
        return switch PiboCoreAnimation.transitionIntent(
            from: from,
            to: to,
            angryEntered: angryEntered
        ) {
        case .hardCut: .hardCut
        case .bounceCut: .bounceCut
        }
    }
    /// The pose Pibo holds when nothing is being performed.
    ///
    /// `stressZ` is the personal-baseline z-score; pass `hasStressBaseline:
    /// false` while the baseline is still cold, because a zero with no history
    /// behind it is an absence of data rather than a calm day, and reading a
    /// mood off it would be inventing one.
    static func ambientStateID(
        for state: PiboActivityState,
        stressZ: Double = 0,
        hasStressBaseline: Bool = false,
        sleptWell: Bool = true,
        lowEnergyDays: UInt32 = 0
    ) -> String {
        PiboCoreAnimation.ambientState(
            activity: coreState(for: state),
            stressZ: stressZ,
            hasStressBaseline: hasStressBaseline,
            sleptWell: sleptWell,
            lowEnergyDays: lowEnergyDays
        ).contentID
    }

    /// Whether a finished workout earns the 秀肌肉 → 娇羞 performance.
    static func workoutCelebrationAllowed(
        for state: PiboActivityState,
        lowEnergyDays: UInt32 = 0
    ) -> Bool {
        PiboCoreAnimation.workoutCelebrationAllowed(
            activity: coreState(for: state),
            lowEnergyDays: lowEnergyDays
        )
    }

    private static func coreState(for state: PiboActivityState) -> PiboCoreActivityState {
        switch state {
        case .deepSleep: .deepSleep
        case .waking: .waking
        case .active: .active
        case .irritated: .irritated
        case .idle: .idle
        case .disturbed: .disturbed
        }
    }
}

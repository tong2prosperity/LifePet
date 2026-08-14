enum HomeAnimationStateResolver {
    struct Input {
        let localHour: Double
        let hasSleepData: Bool
        let sleepHours: Double
        let sleepReferenceHours: Double
        let hasActivityData: Bool
        let steps: Int
        let hasWorkoutToday: Bool
        let postPluckSleep: Bool
        let sleepDayKey: Int64
        let angryActive: Bool
        let hasEligibleRMSSD: Bool
        let stressBaselineDays: Int
        let stressZ: Double
        let rmssdAgeSeconds: Double
        let previousStressStateID: String
        let heldAchievement: PiboAnimationAchievementKind?
    }

    struct Resolution: Equatable {
        let stateID: String
        let nextStressStateID: String
    }

    /// Stress memory follows Core's ambient decision, while an app-owned
    /// achievement hold changes only the state presented on Home.
    static func resolve(_ input: Input) -> Resolution {
        let ambientStateID = PiboCoreAnimationAdapter.completeAmbientStateID(
            localHour: input.localHour,
            hasSleepData: input.hasSleepData,
            sleepHours: input.sleepHours,
            sleepReferenceHours: input.sleepReferenceHours,
            hasActivityData: input.hasActivityData,
            steps: input.steps,
            hasWorkoutToday: input.hasWorkoutToday,
            postPluckSleep: input.postPluckSleep,
            sleepDayKey: input.sleepDayKey,
            angryActive: input.angryActive,
            hasEligibleRMSSD: input.hasEligibleRMSSD,
            stressBaselineDays: input.stressBaselineDays,
            stressZ: input.stressZ,
            rmssdAgeSeconds: input.rmssdAgeSeconds,
            previousStressStateID: input.previousStressStateID
        )
        let nextStressStateID = PiboCoreAnimationAdapter.nextStressMemoryStateID(
            decidedStateID: ambientStateID,
            previousStressStateID: input.previousStressStateID
        )
        let stateID = PiboCoreAnimationAdapter.stateIDByApplyingAchievementHold(
            to: ambientStateID,
            held: input.heldAchievement
        )
        return Resolution(
            stateID: stateID,
            nextStressStateID: nextStressStateID
        )
    }
}

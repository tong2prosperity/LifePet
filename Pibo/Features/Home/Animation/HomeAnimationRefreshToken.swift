import Foundation

struct HomeAnimationRefreshToken: Equatable {
    let steps: Int
    let sleepHours: Double
    let hasWorkout: Bool
    let rmssd: Double?
    let historyRevision: Int
    let pendingAchievementID: UUID?
    let notificationPresentationRequestID: UUID?

    init(
        steps: Int,
        sleepHours: Double,
        hasWorkout: Bool,
        rmssd: Double?,
        historyRevision: Int,
        pendingAchievementID: UUID?,
        notificationPresentationRequestID: UUID?
    ) {
        self.steps = steps
        self.sleepHours = sleepHours
        self.hasWorkout = hasWorkout
        self.rmssd = rmssd
        self.historyRevision = historyRevision
        self.pendingAchievementID = pendingAchievementID
        self.notificationPresentationRequestID = notificationPresentationRequestID
    }

    init(store: PetStateStore, history: HealthHistoryStore) {
        self.init(
            steps: store.rawSteps,
            sleepHours: store.rawSleepHours,
            hasWorkout: store.hasWorkoutToday,
            rmssd: store.rmssd,
            historyRevision: history.revision,
            pendingAchievementID: store.animationExperience.pendingAchievement?.id,
            notificationPresentationRequestID: store.animationExperience
                .notificationPresentationRequestID
        )
    }

    func achievementChanges(
        from previous: HomeAnimationRefreshToken
    ) -> HomeAchievementPresentationPolicy.ObservedChanges {
        HomeAchievementPresentationPolicy.observedChanges(
            previousPendingAchievementID: previous.pendingAchievementID,
            pendingAchievementID: pendingAchievementID,
            previousNotificationPresentationRequestID: previous
                .notificationPresentationRequestID,
            notificationPresentationRequestID: notificationPresentationRequestID
        )
    }
}

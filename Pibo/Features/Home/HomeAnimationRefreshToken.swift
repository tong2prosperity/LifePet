import Foundation

struct HomeAnimationRefreshToken: Equatable {
    let steps: Int
    let sleepHours: Double
    let hasWorkout: Bool
    let rmssd: Double?
    let historyRevision: Int
    let pendingAchievementID: UUID?
    let notificationPresentationRequestID: UUID?

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

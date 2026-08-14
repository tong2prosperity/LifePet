import Foundation

struct HomeAchievementPresentationPolicy {
    struct ObservedChanges: Equatable {
        let pendingAchievementChanged: Bool
        let notificationPresentationRequested: Bool

        var shouldAttemptPresentation: Bool {
            pendingAchievementChanged || notificationPresentationRequested
        }
    }

    enum Reconciliation: Equatable {
        case unchanged
        case dismiss
        case replace(PiboAnimationAchievementPayload)

        func apply(to destination: inout HomeSheetDestination?) {
            switch self {
            case .unchanged:
                break
            case .dismiss:
                destination = nil
            case .replace(let payload):
                destination = .achievement(payload)
            }
        }
    }

    static func observedChanges(
        previousPendingAchievementID: UUID?,
        pendingAchievementID: UUID?,
        previousNotificationPresentationRequestID: UUID?,
        notificationPresentationRequestID: UUID?
    ) -> ObservedChanges {
        ObservedChanges(
            pendingAchievementChanged: previousPendingAchievementID
                != pendingAchievementID,
            notificationPresentationRequested: previousNotificationPresentationRequestID
                != notificationPresentationRequestID
        )
    }

    static func reconciliation(
        presentedAchievement: PiboAnimationAchievementPayload,
        pendingAchievement: PiboAnimationAchievementPayload?
    ) -> Reconciliation {
        guard let pendingAchievement else { return .dismiss }
        guard pendingAchievement.id != presentedAchievement.id else { return .unchanged }
        return .replace(pendingAchievement)
    }

    static func shouldDismissStaleFixture(
        presentedAchievementID: UUID,
        pendingAchievementID: UUID?,
        fixtureEnabled: Bool
    ) -> Bool {
        pendingAchievementID != presentedAchievementID && fixtureEnabled
    }

    static func shouldConfirm(
        presentedAchievementID: UUID,
        pendingAchievementID: UUID?
    ) -> Bool {
        pendingAchievementID == presentedAchievementID
    }

    static func consumesPendingWorkout(
        presentedAchievement: PiboAnimationAchievementPayload,
        pendingWorkoutID: @autoclosure () -> UUID?
    ) -> Bool {
        presentedAchievement.kind == .pigu
            && pendingWorkoutID() == presentedAchievement.id
    }
}

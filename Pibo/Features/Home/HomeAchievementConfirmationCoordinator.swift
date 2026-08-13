import Foundation

/// Preserves the confirmation order for Home's replaceable achievement slot.
/// Concrete store, debug, animation, and presentation effects stay injectable.
@MainActor
enum HomeAchievementConfirmationCoordinator {
    struct Handlers {
        let currentPendingAchievementID: () -> UUID?
        let dismissStaleFixture: () -> Void
        let confirmPending: () -> Void
        let currentPendingWorkoutID: () -> UUID?
        let consumePendingWorkout: () -> Void
        let applyDebugReward: () -> Void
        let refreshAnimationState: () -> Void
        let beginSheetDismissal: () -> Void
    }

    static func confirm(
        presentedAchievement: PiboAnimationAchievementPayload,
        handlers: Handlers
    ) {
        #if DEBUG
        confirm(
            presentedAchievement: presentedAchievement,
            staleFixtureEnabled: HomeDebugLaunchOptions.current.hasAchievementArgument,
            handlers: handlers
        )
        #else
        confirmCurrent(
            presentedAchievement: presentedAchievement,
            handlers: handlers
        )
        #endif
    }

    static func confirm(
        presentedAchievement: PiboAnimationAchievementPayload,
        staleFixtureEnabled: Bool,
        handlers: Handlers
    ) {
        if HomeAchievementPresentationPolicy.shouldDismissStaleFixture(
            presentedAchievementID: presentedAchievement.id,
            pendingAchievementID: handlers.currentPendingAchievementID(),
            fixtureEnabled: staleFixtureEnabled
        ) {
            handlers.dismissStaleFixture()
            return
        }
        confirmCurrent(
            presentedAchievement: presentedAchievement,
            handlers: handlers
        )
    }

    private static func confirmCurrent(
        presentedAchievement: PiboAnimationAchievementPayload,
        handlers: Handlers
    ) {
        guard HomeAchievementPresentationPolicy.shouldConfirm(
            presentedAchievementID: presentedAchievement.id,
            pendingAchievementID: handlers.currentPendingAchievementID()
        ) else { return }

        handlers.confirmPending()
        if HomeAchievementPresentationPolicy.consumesPendingWorkout(
            presentedAchievement: presentedAchievement,
            pendingWorkoutID: handlers.currentPendingWorkoutID()
        ) {
            handlers.consumePendingWorkout()
        }
        handlers.applyDebugReward()
        handlers.refreshAnimationState()
        handlers.beginSheetDismissal()
    }
}

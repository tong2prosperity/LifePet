import PiboCore

/// Owns Home's exclusive sheet flow and the priority of presentations that
/// were deferred while another surface covered the forest.
@MainActor
struct HomePresentationFlow {
    let presentation: HomePresentationState
    let store: PetStateStore
    let ornamentUnlocks: OrnamentUnlockStore
    let morningSleep: MorningSleepCoordinator
    let stressNotifier: StressNotifier
    let currentPolicy: () -> HomePresentationPolicy
    let currentAnimationStateID: () -> String
    let applyDebugReward: (PiboAnimationAchievementPayload) -> Void
    let refreshAnimationState: () -> Void
    let announceFirstRipeBo: () -> Void

    func presentAchievementIfPossible() {
        let policy = currentPolicy()
        var destination = presentation.activeSheet
        HomeAchievementPresentationCoordinator.presentIfPossible(
            policy: policy,
            animationStateID: currentAnimationStateID(),
            pendingAchievement: store.animationExperience.pendingAchievement,
            destination: &destination
        )
        presentation.activeSheet = destination
    }

    func reconcilePresentedAchievement() {
        var destination = presentation.activeSheet
        HomeAchievementPresentationCoordinator.reconcile(
            destination: &destination,
            pendingAchievement: store.animationExperience.pendingAchievement
        )
        presentation.activeSheet = destination
    }

    func confirm(_ payload: PiboAnimationAchievementPayload) {
        HomeAchievementConfirmationCoordinator.confirm(
            presentedAchievement: payload,
            handlers: .init(
                currentPendingAchievementID: {
                    store.animationExperience.pendingAchievement?.id
                },
                dismissStaleFixture: { presentation.activeSheet = nil },
                confirmPending: { _ = store.animationExperience.confirmPending() },
                currentPendingWorkoutID: { store.pendingWorkout?.id },
                consumePendingWorkout: { store.consumePendingWorkout() },
                applyDebugReward: { applyDebugReward(payload) },
                refreshAnimationState: refreshAnimationState,
                beginSheetDismissal: {
                    presentation.sheetDismissalInProgress = true
                    presentation.activeSheet = nil
                }
            )
        )
    }

    func presentMorningSleepIfPossible() {
        let policy = currentPolicy()
        var destination = presentation.activeSheet
        HomeMorningSleepPresentationCoordinator.presentIfPossible(
            policy: policy,
            sleepReviewGranted: ornamentUnlocks.grants(.sleepReview),
            // Re-evaluate at presentation time so a queued card cannot cross
            // midnight and consume the wrong wake day.
            consumablePresentation: morningSleep.consumablePresentation(),
            destination: &destination
        )
        presentation.activeSheet = destination
    }

    func presentStressCardIfPossible() {
        HomeStressCardPresentationCoordinator.presentIfPossible(
            policy: currentPolicy(),
            notifier: stressNotifier,
            presentation: presentation
        )
    }

    func resumePendingFlows() {
        HomePendingFlowCoordinator.resume(handlers: .init(
            clearSheetDismissal: {
                presentation.sheetDismissalInProgress = false
            },
            presentAchievement: presentAchievementIfPossible,
            sheetIsAbsent: { presentation.activeSheet == nil },
            presentMorningSleep: presentMorningSleepIfPossible,
            presentStressCard: presentStressCardIfPossible,
            announceFirstRipeBo: announceFirstRipeBo
        ))
    }
}

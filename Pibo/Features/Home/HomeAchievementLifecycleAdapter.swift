/// Connects Home's live presentation and store state to the focused
/// achievement coordinators. The coordinators continue to own eligibility,
/// lazy reads, reconciliation, and confirmation effect order.
@MainActor
struct HomeAchievementLifecycleAdapter {
    typealias SheetMutation = (_ update: (inout HomeSheetDestination?) -> Void) -> Void

    let store: PetStateStore
    let currentPolicy: () -> HomePresentationPolicy
    let currentAnimationStateID: () -> String
    let withSheet: SheetMutation
    let dismissSheet: () -> Void
    let applyDebugReward: (PiboAnimationAchievementPayload) -> Void
    let refreshAnimationState: () -> Void
    let beginSheetDismissal: () -> Void

    func presentIfPossible() {
        // Match Home's original evaluation order: policy reads `activeSheet`
        // before the coordinator receives exclusive inout access to that sheet.
        let policy = currentPolicy()
        withSheet { destination in
            HomeAchievementPresentationCoordinator.presentIfPossible(
                policy: policy,
                animationStateID: currentAnimationStateID(),
                pendingAchievement: store.animationExperience.pendingAchievement,
                destination: &destination
            )
        }
    }

    func reconcilePresentedAchievement() {
        withSheet { destination in
            HomeAchievementPresentationCoordinator.reconcile(
                destination: &destination,
                pendingAchievement: store.animationExperience.pendingAchievement
            )
        }
    }

    func confirm(_ payload: PiboAnimationAchievementPayload) {
        HomeAchievementConfirmationCoordinator.confirm(
            presentedAchievement: payload,
            handlers: .init(
                currentPendingAchievementID: {
                    store.animationExperience.pendingAchievement?.id
                },
                dismissStaleFixture: dismissSheet,
                confirmPending: { _ = store.animationExperience.confirmPending() },
                currentPendingWorkoutID: { store.pendingWorkout?.id },
                consumePendingWorkout: { store.consumePendingWorkout() },
                applyDebugReward: { applyDebugReward(payload) },
                refreshAnimationState: refreshAnimationState,
                beginSheetDismissal: beginSheetDismissal
            )
        )
    }
}

/// Coordinates achievement sheet mutations after presentation policy has
/// decided whether Home is currently eligible to show one.
@MainActor
enum HomeAchievementPresentationCoordinator {
    static func presentIfPossible(
        policy: HomePresentationPolicy,
        animationStateID: @autoclosure () -> String,
        pendingAchievement: @autoclosure () -> PiboAnimationAchievementPayload?,
        destination: inout HomeSheetDestination?
    ) {
        guard let payload = policy.pendingAchievement(
            animationStateID: animationStateID(),
            pendingAchievement: pendingAchievement()
        ) else { return }
        destination = .achievement(payload)
    }

    /// HealthKit can deliver a newer workout while an achievement sheet is
    /// already visible. Keep the sheet bound to the replaceable pending slot;
    /// otherwise its Confirm button targets an obsolete UUID and becomes an
    /// undismissable no-op because interactive dismissal is disabled.
    static func reconcile(
        destination: inout HomeSheetDestination?,
        pendingAchievement: @autoclosure () -> PiboAnimationAchievementPayload?
    ) {
        guard case .achievement(let presented) = destination else { return }
        let reconciliation = HomeAchievementPresentationPolicy.reconciliation(
            presentedAchievement: presented,
            pendingAchievement: pendingAchievement()
        )
        reconciliation.apply(to: &destination)
    }
}

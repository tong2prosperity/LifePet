/// Connects Home's live presentation state to the focused pending-flow
/// coordinators. Eligibility, mutation order, and retry priority remain owned
/// by those coordinators.
@MainActor
struct HomePendingPresentationAdapter {
    typealias SheetMutation = (_ update: (inout HomeSheetDestination?) -> Void) -> Void

    let currentPolicy: () -> HomePresentationPolicy
    let currentSleepReviewGranted: () -> Bool
    let currentMorningSleepPresentation: () -> MorningSleepPresentation?
    let withSheet: SheetMutation
    let currentPendingStressCardOpen: () -> Bool
    let stressHandlers: HomeStressCardPresentationCoordinator.Handlers
    let clearSheetDismissal: () -> Void
    let presentAchievement: () -> Void
    let sheetIsAbsent: () -> Bool
    let announceFirstRipeBo: () -> Void

    func presentMorningSleepIfPossible() {
        // Preserve Home's original evaluation order: policy is read before the
        // sheet receives exclusive inout access. Entitlement and presentation
        // stay lazy inside the coordinator.
        let policy = currentPolicy()
        withSheet { destination in
            HomeMorningSleepPresentationCoordinator.presentIfPossible(
                policy: policy,
                sleepReviewGranted: currentSleepReviewGranted(),
                consumablePresentation: currentMorningSleepPresentation(),
                destination: &destination
            )
        }
    }

    /// Keep a tapped stress-notification request raised until Home is free to
    /// open History. The coordinator preserves clear → focus → present order.
    func presentStressCardIfPossible() {
        HomeStressCardPresentationCoordinator.presentIfPossible(
            policy: currentPolicy(),
            pendingCardOpen: currentPendingStressCardOpen(),
            handlers: stressHandlers
        )
    }

    func resumePendingFlows() {
        HomePendingFlowCoordinator.resume(handlers: .init(
            clearSheetDismissal: clearSheetDismissal,
            presentAchievement: presentAchievement,
            sheetIsAbsent: sheetIsAbsent,
            presentMorningSleep: presentMorningSleepIfPossible,
            presentStressCard: presentStressCardIfPossible,
            announceFirstRipeBo: announceFirstRipeBo
        ))
    }
}

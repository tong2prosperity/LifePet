/// Coordinates the wake-card sheet mutation after Home's presentation policy
/// has re-validated both the entitlement and the queued sleep summary.
@MainActor
enum HomeMorningSleepPresentationCoordinator {
    static func presentIfPossible(
        policy: HomePresentationPolicy,
        sleepReviewGranted: @autoclosure () -> Bool,
        consumablePresentation: @autoclosure () -> MorningSleepPresentation?,
        destination: inout HomeSheetDestination?
    ) {
        let presentation = policy.morningSleepPresentation(
            sleepReviewGranted: sleepReviewGranted(),
            // Re-validated at the moment of presentation, not when it was
            // queued: a card queued late at night must not surface as "last
            // night" after midnight, nor consume the wrong wake-day.
            consumablePresentation: consumablePresentation()
        )
        guard let presentation else { return }
        destination = .morningSleep(presentation, consumesPending: true)
    }
}

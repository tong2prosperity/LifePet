/// Consumes a pending stress-notification route only after Home is free to open
/// History, then preserves the focus-before-presentation mutation order.
@MainActor
enum HomeStressCardPresentationCoordinator {
    struct Handlers {
        let clearPendingRequest: () -> Void
        let focusStressCard: () -> Void
        let presentHistory: () -> Void
    }

    static func presentIfPossible(
        policy: HomePresentationPolicy,
        notifier: StressNotifier,
        presentation: HomePresentationState
    ) {
        presentIfPossible(
            policy: policy,
            pendingCardOpen: notifier.pendingCardOpen,
            handlers: Handlers(
                clearPendingRequest: { notifier.pendingCardOpen = false },
                focusStressCard: { presentation.historyFocus = .stress },
                presentHistory: { presentation.showHistory = true }
            )
        )
    }

    static func presentIfPossible(
        policy: HomePresentationPolicy,
        pendingCardOpen: @autoclosure () -> Bool,
        handlers: Handlers
    ) {
        guard policy.shouldPresentStressCard(
            pendingCardOpen: pendingCardOpen()
        ) else { return }
        handlers.clearPendingRequest()
        handlers.focusStressCard()
        handlers.presentHistory()
    }
}

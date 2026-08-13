/// Sequences presentation retries after Home becomes visible again. Each flow
/// keeps its own eligibility policy; this coordinator owns only their existing
/// priority and the required live sheet-state reads between attempts.
/// Achievement confirmation goes first; once that slot is clear, the sleep card
/// gets the wake-up moment before lower-priority work.
@MainActor
enum HomePendingFlowCoordinator {
    struct Handlers {
        let clearSheetDismissal: () -> Void
        let presentAchievement: () -> Void
        let sheetIsAbsent: () -> Bool
        let presentMorningSleep: () -> Void
        let presentStressCard: () -> Void
        let announceFirstRipeBo: () -> Void
    }

    static func resume(handlers: Handlers) {
        handlers.clearSheetDismissal()
        handlers.presentAchievement()
        guard handlers.sheetIsAbsent() else { return }

        handlers.presentMorningSleep()
        handlers.presentStressCard()
        if handlers.sheetIsAbsent() {
            handlers.announceFirstRipeBo()
        }
    }
}

/// Resolves a released hair pull into either a ripe `bo` collection attempt or
/// Pibo's turn-away response, after preserving the interaction haptic.
@MainActor
enum HomeHairPullCoordinator {
    struct Handlers {
        let tap: () -> Void
        let hasRipeBo: () -> Bool
        let pluck: () -> Bool
        let playTurnAway: () -> Void
    }

    static func handle(
        ledger: BoLedgerStore,
        stageCommands: PiboStageCommandController,
        pluck: @escaping () -> Bool
    ) {
        handle(handlers: Handlers(
            tap: { LPHaptics.tap() },
            hasRipeBo: { ledger.hasRipeBo },
            pluck: pluck,
            playTurnAway: { stageCommands.playTurnAway() }
        ))
    }

    static func handle(handlers: Handlers) {
        handlers.tap()
        if handlers.hasRipeBo() {
            _ = handlers.pluck()
        } else {
            handlers.playTurnAway()
        }
    }
}

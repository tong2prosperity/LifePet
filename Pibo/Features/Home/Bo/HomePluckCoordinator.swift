import Foundation

/// Sequences one `bo` collection while keeping the ledger mutation ahead of
/// every presentation effect.
@MainActor
enum HomePluckCoordinator {
    struct Handlers {
        let makeEventID: () -> String
        let pluck: (_ eventID: String) -> Bool
        let currentBalance: () -> Int
        let trackPluck: (_ balance: Int, _ eventID: String) -> Void
        let playPluck: () -> Void
        let showCollectedMessage: () -> Void
        let cooperationEnabled: () -> Bool
        let lifetimeMinted: () -> Int
        let lifetimeCollected: () -> Int
        let observeBoProgress: (_ lifetimeMinted: Int, _ lifetimeCollected: Int) -> Void
        let presentFirstItemGuideIfEligible: () -> Void
    }

    static func run(
        ledger: BoLedgerStore,
        stageCommands: PiboStageCommandController,
        onboarding: OnboardingStateStore,
        show: @escaping (PiboSpeechLine) -> Void,
        presentFirstItemGuideIfEligible: @escaping () -> Void = {}
    ) -> Bool {
        run(handlers: .init(
            makeEventID: { "local-pluck-\(UUID().uuidString)" },
            pluck: { ledger.pluck(eventID: $0) },
            currentBalance: { ledger.balance },
            trackPluck: { balance, eventID in
                Analytics.track(
                    .pluck,
                    screen: "home",
                    ["balance": .int(balance), "event_id": .string(eventID)]
                )
            },
            playPluck: { stageCommands.playPluck() },
            showCollectedMessage: {
                show(.system(AppLocalization.narrative("home.bo.collected")))
            },
            cooperationEnabled: { PiboReleaseScope.temporaryCooperationOnboarding },
            lifetimeMinted: { ledger.lifetimeMinted },
            lifetimeCollected: { ledger.lifetimeCollected },
            observeBoProgress: { lifetimeMinted, lifetimeCollected in
                onboarding.observeBoProgress(
                    lifetimeMinted: lifetimeMinted,
                    lifetimeCollected: lifetimeCollected
                )
            },
            presentFirstItemGuideIfEligible: presentFirstItemGuideIfEligible
        ))
    }

    static func run(handlers: Handlers) -> Bool {
        let eventID = handlers.makeEventID()
        guard handlers.pluck(eventID) else { return false }

        let balance = handlers.currentBalance()
        handlers.trackPluck(balance, eventID)
        handlers.playPluck()
        handlers.showCollectedMessage()

        if handlers.cooperationEnabled() {
            let lifetimeMinted = handlers.lifetimeMinted()
            let lifetimeCollected = handlers.lifetimeCollected()
            handlers.observeBoProgress(lifetimeMinted, lifetimeCollected)
        }
        handlers.presentFirstItemGuideIfEligible()
        return true
    }
}

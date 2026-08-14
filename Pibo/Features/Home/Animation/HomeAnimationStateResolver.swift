enum HomeAnimationStateResolver {
    struct Input {
        let decision: PiboCoreStateAdapter.Decision
        let sleepDayKey: Int64
    }

    struct Resolution: Equatable {
        let state: PiboActivityState
        let stateID: String
        let decision: PiboCoreStateAdapter.Decision
    }

    static func resolve(_ input: Input) -> Resolution {
        Resolution(
            state: input.decision.state,
            stateID: PiboCoreAnimationAdapter.ambientStateID(
                for: input.decision.state,
                sleepDayKey: input.sleepDayKey
            ),
            decision: input.decision
        )
    }
}

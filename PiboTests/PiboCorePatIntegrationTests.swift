import PiboCore
import Testing
@testable import Pibo

@Test func corePatCooldownMatchesBubbleDuration() {
    #expect(PiboCorePatAdapter.interactionDurationSeconds == 3)
    #expect(!PiboCorePat.cooldownAllows(
        elapsedSinceLastAcceptedSeconds: 2.999,
        hasPreviousAcceptedTap: true
    ))
    #expect(PiboCorePat.cooldownAllows(
        elapsedSinceLastAcceptedSeconds: 3,
        hasPreviousAcceptedTap: true
    ))
}

@Test func corePatMapsSixStatesAndSubstatesToSemanticContexts() {
    #expect(PiboCorePat.context(
        state: .stable,
        behavior: .stableThinking,
        event: .none
    ) == .stableThinking)
    #expect(PiboCorePat.context(
        state: .energetic,
        behavior: .default,
        event: .workoutRun
    ) == .energeticWorkoutRun)
    #expect(PiboCorePat.context(
        state: .tired,
        behavior: .tiredResting,
        event: .none
    ) == .tiredResting)
    #expect(PiboCorePat.context(
        state: .waking,
        behavior: .wakingGreeted,
        event: .none
    ) == .wakingGreeted)
    #expect(PiboCorePat.context(
        state: .sleeping,
        behavior: .default,
        event: .none
    ) == .sleepingAsleep)
    #expect(PiboCorePat.context(
        state: .dataUnknown,
        behavior: .default,
        event: .none,
        dataUnknownReason: .authorization
    ) == .dataUnknownAuthorization)
}

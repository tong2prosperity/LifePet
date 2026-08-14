import Foundation
import PiboCore
import Testing
@testable import Pibo

@MainActor
struct HomeSpeechInputProviderTests {
    @Test func providerPreservesHomeStoreWiring() throws {
        let suite = "HomeSpeechInputProviderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PetStateStore(demoMode: true)
        let ledger = BoLedgerStore(
            defaults: defaults,
            persistenceKey: "test.ledger"
        )
        let onboarding = OnboardingStateStore(
            defaults: defaults,
            persistenceKey: "test.onboarding"
        )
        let animation = HomeAnimationPresentationController(stateID: "pibo-state-waking-hammock-idle")
        let provider = HomeSpeechInputProvider(
            store: store,
            boLedger: ledger,
            onboarding: onboarding,
            animationPresentation: animation
        )

        let expectedFacts = HomeSpeechInputResolver.facts(
            hasStepsData: store.hasStepsData,
            rawSteps: store.rawSteps,
            rawSleepHours: store.rawSleepHours,
            hasWorkoutToday: store.hasWorkoutToday,
            pendingBoCount: ledger.state.ripeCount,
            cooperationEnabled: PiboReleaseScope.temporaryCooperationOnboarding,
            connectionAccepted: onboarding.snapshot.connection == .accepted
        )
        #expect(provider.facts.hasSteps == expectedFacts.hasSteps)
        #expect(provider.facts.hasSleepDuration == expectedFacts.hasSleepDuration)
        #expect(provider.facts.hasWorkoutType == expectedFacts.hasWorkoutType)
        #expect(provider.facts.pendingBoCount == expectedFacts.pendingBoCount)
        #expect(provider.facts.connectionAccepted == expectedFacts.connectionAccepted)

        #expect(provider.values == HomeSpeechInputResolver.values(
            hasStepsData: store.hasStepsData,
            rawSteps: store.rawSteps,
            rawSleepHours: store.rawSleepHours,
            sleepDurationUnit: AppLocalization.text("小时")
        ))
        #expect(provider.idleContext == HomeIdleSpeechContextResolver.resolve(
            animationStateID: animation.stateID,
            hasRealHealthData: store.hasRealHealthData
        ))

        let expectedStage = PiboReleaseScope.temporaryCooperationOnboarding
            ? onboarding.eventProjection().speechStage
            : .unresponded
        #expect(provider.storyStage == expectedStage)
    }
}

import PiboCore

/// Adapts Home's live stores into the semantic inputs consumed by Core speech
/// resolution. Selection, budgets, and presentation remain with their existing
/// owners.
@MainActor
struct HomeSpeechInputProvider {
    let store: PetStateStore
    let boLedger: BoLedgerStore
    let onboarding: OnboardingStateStore
    let animationPresentation: HomeAnimationPresentationController

    var storyStage: PiboCoreStorySpeechStage {
        guard PiboReleaseScope.temporaryCooperationOnboarding else {
            return .unresponded
        }
        return onboarding.eventProjection().speechStage
    }

    var facts: PiboHomeSpeechFacts {
        HomeSpeechInputResolver.facts(
            hasStepsData: store.hasStepsData,
            rawSteps: store.rawSteps,
            rawSleepHours: store.rawSleepHours,
            hasWorkoutToday: store.hasWorkoutToday,
            pendingBoCount: boLedger.state.ripeCount,
            cooperationEnabled: PiboReleaseScope.temporaryCooperationOnboarding,
            connectionAccepted: onboarding.snapshot.connection == .accepted
        )
    }

    var values: [String: String] {
        HomeSpeechInputResolver.values(
            hasStepsData: store.hasStepsData,
            rawSteps: store.rawSteps,
            rawSleepHours: store.rawSleepHours,
            sleepDurationUnit: AppLocalization.text("小时")
        )
    }

    var idleContext: PiboCoreHomeSpeechContext? {
        HomeIdleSpeechContextResolver.resolve(
            animationStateID: animationPresentation.stateID,
            hasRealHealthData: store.hasRealHealthData
        )
    }
}

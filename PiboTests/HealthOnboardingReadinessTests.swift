import Testing
@testable import Pibo

@Suite("Health onboarding readiness")
struct HealthOnboardingReadinessTests {
    @Test("one observed bo-eligible source is enough")
    func acceptsAnyObservedBaselineInput() {
        let ready = HealthDataService.OnboardingReadiness(
            hasSleep: true,
            hasSteps: true,
            hasExercise: true
        )
        #expect(ready.isReady)

        #expect(HealthDataService.OnboardingReadiness(
            hasSleep: false,
            hasSteps: true,
            hasExercise: true
        ).isReady)
        #expect(HealthDataService.OnboardingReadiness(
            hasSleep: true,
            hasSteps: false,
            hasExercise: false
        ).isReady)
        #expect(HealthDataService.OnboardingReadiness(
            hasSleep: false,
            hasSteps: false,
            hasExercise: true
        ).isReady)
        #expect(!HealthDataService.OnboardingReadiness(
            hasSleep: false,
            hasSteps: false,
            hasExercise: false
        ).isReady)
    }
}

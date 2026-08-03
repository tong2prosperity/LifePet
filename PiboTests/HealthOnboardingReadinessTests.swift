import Testing
@testable import Pibo

@Suite("Health onboarding readiness")
struct HealthOnboardingReadinessTests {
    @Test("requires sleep, steps, and exercise together")
    func requiresEveryBaselineInput() {
        let ready = HealthDataService.OnboardingReadiness(
            hasSleep: true,
            hasSteps: true,
            hasExercise: true
        )
        #expect(ready.isReady)

        #expect(!HealthDataService.OnboardingReadiness(
            hasSleep: false,
            hasSteps: true,
            hasExercise: true
        ).isReady)
        #expect(!HealthDataService.OnboardingReadiness(
            hasSleep: true,
            hasSteps: false,
            hasExercise: true
        ).isReady)
        #expect(!HealthDataService.OnboardingReadiness(
            hasSleep: true,
            hasSteps: true,
            hasExercise: false
        ).isReady)
    }
}

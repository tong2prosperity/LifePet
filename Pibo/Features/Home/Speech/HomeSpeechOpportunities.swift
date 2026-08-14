/// Resolves the weather and first-ripe speech opportunities driven by Home.
@MainActor
struct HomeSpeechOpportunities {
    let presentation: HomeSpeechPresentationController
    let input: HomeSpeechInputProvider
    let speech: PiboSpeechService
    let currentPolicy: () -> HomePresentationPolicy
    let currentStageIsPaused: () -> Bool
    let currentWeather: () -> PiboWeather
    let currentHasRipeBo: () -> Bool

    func presentWeatherIfPossible(trigger: PiboSpeechTrigger) {
        HomeSpeechOpportunityCoordinator.presentWeatherIfPossible(
            trigger: trigger,
            stageIsPaused: currentStageIsPaused(),
            idleSpeechContext: input.idleContext,
            weather: currentWeather(),
            speech: speech,
            show: presentation.show
        )
    }

    /// Explain the first ripe `bo` once. Ripe items do not expire or block
    /// later accumulation.
    func announceFirstRipeBoIfNeeded() {
        HomeFirstRipeBoAnnouncementCoordinator.announceIfNeeded(
            policy: currentPolicy(),
            hasRipeBo: currentHasRipeBo(),
            speechIsAbsent: presentation.line == nil,
            idleSpeechContextAvailable: input.idleContext != nil,
            show: presentation.show
        )
    }
}

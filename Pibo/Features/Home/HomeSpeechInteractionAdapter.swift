/// Connects Home's live speech inputs to the focused opportunity and
/// presentation coordinators. Speech selection, budgets, animations, and
/// one-shot announcement effects remain with their existing owners.
@MainActor
struct HomeSpeechInteractionAdapter {
    let presentation: HomeSpeechPresentationController
    let input: HomeSpeechInputProvider
    let speech: PiboSpeechService
    let currentPolicy: () -> HomePresentationPolicy
    let currentStageIsPaused: () -> Bool
    let currentWeather: () -> PiboWeather
    let currentHasRipeBo: () -> Bool

    func dismiss() {
        presentation.dismiss()
    }

    func show(_ line: PiboSpeechLine) {
        presentation.show(line)
    }

    func show(_ resolved: PiboSpeech) {
        presentation.show(resolved)
    }

    func presentWeatherIfPossible(trigger: PiboSpeechTrigger) {
        HomeSpeechOpportunityCoordinator.presentWeatherIfPossible(
            trigger: trigger,
            stageIsPaused: currentStageIsPaused(),
            idleSpeechContext: input.idleContext,
            weather: currentWeather(),
            speech: speech,
            show: show
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
            show: show
        )
    }
}

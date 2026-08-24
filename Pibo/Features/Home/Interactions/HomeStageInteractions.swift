import PiboCore

/// Adapts Home's live services and presentation state to the interaction
/// coordinators used by the SpriteKit stage and direct `bo` investment flow.
/// Interaction policy and effect ordering remain in the focused coordinators.
@MainActor
struct HomeStageInteractions {
    let store: PetStateStore
    let history: HealthHistoryStore
    let animationPresentation: HomeAnimationPresentationController
    let stageCommands: PiboStageCommandController
    let contextualActions: HomeContextualActionCoordinator
    let speech: PiboSpeechService
    let ledger: BoLedgerStore
    let onboarding: OnboardingStateStore
    let ornamentUnlocks: OrnamentUnlockStore
    let ornamentLights: OrnamentLightStore
    let morningSleep: MorningSleepCoordinator
    let storyStage: () -> PiboCoreStorySpeechStage
    let speechFacts: () -> PiboHomeSpeechFacts
    let healthAvailability: () -> HealthDataService.DataAvailability
    let canPresentOrnament: () -> Bool
    let dismissSpeech: () -> Void
    let showAnimationLine: (PiboSpeechLine) -> Void
    let showResolvedSpeech: (PiboSpeech) -> Void
    let presentSheet: (HomeSheetDestination) -> Void

    var stageHandlers: HomeStageSurface.Handlers {
        HomeStageSurface.Handlers(
            pat: handlePat,
            sproutTouch: handleSproutTouch,
            ornamentLightTap: handleOrnamentLightTap,
            ornamentTap: handleOrnamentTap
        )
    }

    private func handlePat() {
        let input = HomePatInputProvider(
            store: store,
            history: history,
            animationPresentation: animationPresentation,
            healthAvailability: healthAvailability(),
            storyStage: storyStage()
        ).input()
        HomePatInteractionCoordinator.run(
            input: input,
            speech: speech,
            contextualActions: contextualActions,
            stageCommands: stageCommands,
            presentHealthStatus: { presentSheet(.healthDataStatus) },
            show: showAnimationLine
        )
    }

    private func handleSproutTouch() {
        stageCommands.playSproutTouch()
        guard ledger.hasRipeBo,
              canPresentOrnament(),
              let next = ornamentUnlocks.nextLocked
        else { return }
        dismissSpeech()
        LPHaptics.tap()
        presentSheet(.ornamentUnlock(next.id))
    }

    private func handleOrnamentLightTap(_ id: PiboOrnament.ID, index: Int) {
        // Lighting is deliberately reward-free and one-way until dawn.
        HomeOrnamentInteractionCoordinator.handleLightTap(
            ornamentID: id,
            index: index,
            unlocks: ornamentUnlocks,
            lights: ornamentLights
        )
    }

    private func handleOrnamentTap(_ id: PiboOrnament.ID) {
        HomeOrnamentInteractionCoordinator.handleTap(
            ornamentID: id,
            canPresent: canPresentOrnament,
            unlocks: ornamentUnlocks,
            morningSleep: morningSleep,
            history: history,
            dismissSpeech: dismissSpeech,
            present: presentSheet
        )
    }
}

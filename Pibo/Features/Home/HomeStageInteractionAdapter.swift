import PiboCore

/// Adapts Home's live services and presentation state to the interaction
/// coordinators used by the SpriteKit stage and `bo` collection controls.
/// Interaction policy and effect ordering remain in the focused coordinators.
@MainActor
struct HomeStageInteractionAdapter {
    let store: PetStateStore
    let history: HealthHistoryStore
    let animationPresentation: HomeAnimationPresentationController
    let stageCommands: PiboStageCommandController
    let speech: PiboSpeechService
    let ledger: BoLedgerStore
    let onboarding: OnboardingStateStore
    let ornamentUnlocks: OrnamentUnlockStore
    let ornamentLights: OrnamentLightStore
    let morningSleep: MorningSleepCoordinator
    let storyStage: () -> PiboCoreStorySpeechStage
    let speechFacts: () -> PiboHomeSpeechFacts
    let canPresentOrnament: () -> Bool
    let dismissSpeech: () -> Void
    let showAnimationLine: (PiboSpeechLine) -> Void
    let showResolvedSpeech: (PiboSpeech) -> Void
    let presentSheet: (HomeSheetDestination) -> Void

    var stageHandlers: HomeStageSurface.Handlers {
        HomeStageSurface.Handlers(
            pat: handlePat,
            hairPull: handleHairPull,
            ornamentLightTap: handleOrnamentLightTap,
            ornamentTap: handleOrnamentTap
        )
    }

    func collectBo() -> Bool {
        HomePluckCoordinator.run(
            ledger: ledger,
            stageCommands: stageCommands,
            onboarding: onboarding,
            show: showAnimationLine
        )
    }

    private func handlePat() {
        HomePatInteractionCoordinator.run(
            store: store,
            history: history,
            animationPresentation: animationPresentation,
            stageCommands: stageCommands,
            speech: speech,
            storyStage: storyStage,
            facts: speechFacts,
            neutralLegacyMode: {
                !PiboReleaseScope.temporaryCooperationOnboarding
            },
            showAnimationLine: showAnimationLine,
            showResolvedSpeech: showResolvedSpeech
        )
    }

    private func handleHairPull() {
        // A ripe pull collects; an unripe pull only plays the turn-away response.
        HomeHairPullCoordinator.handle(
            ledger: ledger,
            stageCommands: stageCommands,
            pluck: collectBo
        )
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

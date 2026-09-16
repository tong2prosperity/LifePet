import os
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
    let toggleStatusObserver: () -> Void
    let dismissSpeech: () -> Void
    let showAnimationLine: (PiboSpeechLine) -> Void
    let showResolvedSpeech: (PiboSpeech) -> Void
    let presentSheet: (HomeSheetDestination) -> Void

    var stageHandlers: HomeStageSurface.Handlers {
        HomeStageSurface.Handlers(
            pat: handlePat,
            sproutTouch: handleSproutTouch,
            ornamentLightTap: handleOrnamentLightTap,
            ornamentTap: handleOrnamentTap,
            shadowTap: {
                guard PiboReleaseScope.shadow else { return }
                presentSheet(.shadow(manifest: false))
            }
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
        animationPresentation.noteAttention()
        // Decision 049: the first guided pat uses the ordinary Core reaction,
        // advances the one-time Home guide, and never chases it with an
        // automatic "connect health" sheet.
        let isDailyGuidePat = onboarding.dailyHomeGuide == .pat
        if isDailyGuidePat { onboarding.acknowledgeDailyPat() }
        HomePatInteractionCoordinator.run(
            input: input,
            speech: speech,
            contextualActions: contextualActions,
            stageCommands: stageCommands,
            presentHealthStatus: {
                guard !isDailyGuidePat else { return }
                presentSheet(.healthDataStatus)
            },
            show: { line in
                if input.state == .stable { animationPresentation.stableThinking = false }
                showAnimationLine(line)
            }
        )
        animationPresentation.refreshExpression(behavior: input.state == .stable ? .default : speech.patBehavior(for: input))
    }

    /// Decision 048: touching the container only answers the finger. Ripe
    /// energy is collected by pulling it up into the balance; common objects
    /// are woken from their own grey form, spending only that balance.
    private func handleSproutTouch() {
        stageCommands.playSproutTouch()
    }

    /// Commits one pulled collection into the spendable balance.
    func collectBo() -> Bool {
        let before = ledger.availableBo
        guard ledger.collect() else { return false }
        BoMaturityNotifier.shared.collected(
            nextRipe: ledger.hasRipeBo,
            nextCycle: ledger.lifetimeCollected + 1
        )
        Analytics.track(.boCollect, screen: "home", [
            "balance": .int(ledger.availableBo),
            "remaining_ripe": .int(ledger.state.ripeCount),
        ])
        LPLog.bo.notice("pulled collection \(before, privacy: .public)→\(ledger.availableBo, privacy: .public)")
        return true
    }

    private func handleOrnamentLightTap(_ id: PiboOrnament.ID, index: Int) {
        guard PiboReleaseScope.allowsOrnament(id) else { return }
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
            dismissSpeech: dismissSpeech,
            toggleStatusObserver: toggleStatusObserver,
            present: presentSheet
        )
    }
}

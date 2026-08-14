#if DEBUG
import UIKit

/// Connects Home's developer-only controls and launch automation to its live
/// services. Debug rules, scheduling, and one-shot state remain with the
/// existing controller and control state.
@MainActor
struct HomeDebugInteractionAdapter {
    let automation: HomeDebugAutomationController
    let controls: HomeDebugControlsState
    let store: PetStateStore
    let history: HealthHistoryStore
    let presentation: HomeFeaturePresentationState
    let morningSleep: MorningSleepCoordinator
    let animationPresentation: HomeAnimationPresentationController
    let stageCommands: PiboStageCommandController
    let boProgressFeedback: BoProgressFeedbackStore
    let stressNotifier: StressNotifier
    let ledger: BoLedgerStore
    let currentMiniGamesEnabled: () -> Bool
    let sheetIsAbsent: () -> Bool
    let presentSheet: (HomeSheetDestination) -> Void
    let photoSaved: (UIImage?, String?, MealType?) -> Void
    let openBoPanel: () -> Void

    func applyWorkoutRewardIfMatching(
        _ payload: PiboAnimationAchievementPayload
    ) {
        automation.applyWorkoutRewardIfMatching(payload, ledger: ledger)
    }

    /// Follow the production-equivalent resolve → transition path used by the
    /// tuning panel and delayed launch automation.
    func selectAnimationState(_ stateID: String?) {
        controls.selectAnimationState(
            stateID,
            animationPresentation: animationPresentation,
            store: store,
            history: history,
            stageCommands: stageCommands
        )
    }

    func runLaunchAutomation() {
        automation.runLaunchAutomation(
            options: .current,
            miniGamesEnabled: currentMiniGamesEnabled(),
            store: store,
            presentation: presentation,
            morningSleep: morningSleep,
            animationPresentation: animationPresentation,
            stageCommands: stageCommands,
            boProgressFeedback: boProgressFeedback,
            stressNotifier: stressNotifier,
            sheetIsAbsent: sheetIsAbsent,
            presentSheet: presentSheet,
            selectAnimationState: selectAnimationState,
            photoSaved: photoSaved,
            openBoPanel: openBoPanel
        )
    }

    /// Close Settings first so Home is visible when the real workout event is
    /// injected. The controller preserves the navigation delay.
    func simulateWorkout() {
        automation.simulateWorkout(store: store, presentation: presentation)
    }

    /// Exercise the full saved-photo path without camera hardware.
    func simulateMeal(_ meal: MealType) {
        HomeDebugAutomationController.simulateMeal(
            meal,
            photoSaved: photoSaved
        )
    }
}
#endif

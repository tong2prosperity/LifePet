#if DEBUG
import Observation

/// Owns the mutable controls exposed by Home's developer-only tuning panel.
/// Keeping these values together prevents production Home composition from
/// accumulating one state property per debug toggle.
@MainActor
@Observable
final class HomeDebugControlsState {
    var tuning: StageRenderTuning
    var isPanelExpanded: Bool
    var usesBounceCut: Bool
    var playsAchievementCombo: Bool

    init(
        tuning: StageRenderTuning = .standard,
        isPanelExpanded: Bool = !HomeDebugLaunchOptions.current.hidesTuningPanel,
        usesBounceCut: Bool = false,
        playsAchievementCombo: Bool = false
    ) {
        self.tuning = tuning
        self.isPanelExpanded = isPanelExpanded
        self.usesBounceCut = usesBounceCut
        self.playsAchievementCombo = playsAchievementCombo
    }

    /// Resolves the selected semantic state before issuing the one-shot stage
    /// transition. A rejected selection must not emit a command.
    func selectAnimationState(
        _ stateID: String?,
        animationPresentation: HomeAnimationPresentationController,
        store: PetStateStore,
        history: HealthHistoryStore,
        stageCommands: PiboStageCommandController
    ) {
        selectAnimationState(
            stateID,
            resolve: { stateID, usesBounceCut in
                animationPresentation.selectDebugState(
                    stateID,
                    usesBounceCut: usesBounceCut,
                    store: store,
                    history: history
                )
            },
            transition: {
                stageCommands.transitionAnimation(to: $0, intent: .bounceCut)
            }
        )
    }

    /// Closure-based seam used to verify ordering without a live SpriteKit
    /// scene. It follows the same resolve-then-transition path as Home.
    func selectAnimationState(
        _ stateID: String?,
        resolve: (String?, Bool) -> String?,
        transition: (String) -> Void
    ) {
        guard let target = resolve(stateID, usesBounceCut) else { return }
        transition(target)
    }
}
#endif

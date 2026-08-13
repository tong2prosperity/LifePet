import SwiftUI

#if DEBUG
/// Hosts Home's developer-only forest and animation controls. All mutable state
/// remains owned by `HomeView`; this view only adapts it to `ForestTuningPanel`.
@MainActor
struct HomeDebugControlsOverlay: View {
    @Binding var tuning: StageRenderTuning
    @Binding var isExpanded: Bool
    @Binding var usesBounceCut: Bool
    @Binding var playsAchievementCombo: Bool

    let store: PetStateStore
    let animationPresentation: HomeAnimationPresentationController
    let stageCommands: PiboStageCommandController
    let onSelectAnimationState: (String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ForestTuningPanel(
                    tuning: $tuning,
                    isExpanded: $isExpanded,
                    forcedHour: Binding(
                        get: { store.debugForestHour },
                        set: { store.debugForestHour = $0 }
                    ),
                    forcedAnimationStateID: Binding(
                        get: { animationPresentation.forcedStateID },
                        set: { animationPresentation.forcedStateID = $0 }
                    ),
                    coreAnimationStateID: animationPresentation.coreStateID,
                    presentedAnimationStateID: animationPresentation.stateID,
                    usesBounceCut: $usesBounceCut,
                    playsAchievementCombo: Binding(
                        get: { playsAchievementCombo },
                        set: {
                            playsAchievementCombo = $0
                            stageCommands.setPlaysAchievementCombo($0)
                        }
                    ),
                    onSelectAnimationState: onSelectAnimationState,
                    onReplayAnimation: { stageCommands.replayAnimationIntro() }
                )
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LP.Spacing.l)
        .padding(.top, 118)
    }
}
#endif

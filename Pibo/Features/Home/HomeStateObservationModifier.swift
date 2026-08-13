import SwiftUI

/// Keeps Home's state-change listeners together without owning any observed
/// state. Values and effects remain supplied by `HomeView`.
@MainActor
struct HomeStateObservationModifier: ViewModifier {
    let animationRefreshToken: HomeAnimationRefreshToken
    let morningSleepPresentationID: String?
    let scenePhase: ScenePhase
    let pendingStressCardOpen: Bool
    let hasRipeBo: Bool
    let animationStateID: String
    let sproutPhase: SproutFlowPhase
    let handlers: HomeStateObservationCoordinator.Handlers

    func body(content: Content) -> some View {
        content
            .onChange(of: animationRefreshToken) { oldValue, newValue in
                HomeStateObservationCoordinator.animationTokenChanged(
                    from: oldValue,
                    to: newValue,
                    handlers: handlers
                )
            }
            .onChange(of: morningSleepPresentationID) { _, _ in
                handlers.presentMorningSleep()
            }
            .onChange(of: scenePhase) { _, phase in
                HomeStateObservationCoordinator.scenePhaseChanged(
                    isActive: phase == .active,
                    handlers: handlers
                )
            }
            .onChange(of: pendingStressCardOpen) { _, _ in
                handlers.presentStressCard()
            }
            .onChange(of: hasRipeBo) { _, isRipe in
                HomeStateObservationCoordinator.ripeBoChanged(
                    isRipe,
                    handlers: handlers
                )
            }
            .onChange(of: animationStateID) { _, _ in
                HomeStateObservationCoordinator.animationStateChanged(
                    handlers: handlers
                )
            }
            .onChange(of: sproutPhase) { _, phase in
                HomeStateObservationCoordinator.sproutPhaseChanged(
                    phase,
                    handlers: handlers
                )
            }
    }
}

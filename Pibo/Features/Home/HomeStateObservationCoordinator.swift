/// Preserves the conditional effect order for Home's state-change observers.
/// SwiftUI observation stays in `HomeStateObservationModifier`; this type keeps
/// the reactions independently testable.
@MainActor
enum HomeStateObservationCoordinator {
    struct Handlers {
        let refreshAnimation: () -> Void
        let reconcileAchievement: () -> Void
        let presentAchievement: () -> Void
        let refreshOrnamentLights: () -> Void
        let presentMorningSleep: () -> Void
        let presentStressCard: () -> Void
        let currentHasRipeBo: () -> Bool
        let announceFirstRipeBo: () -> Void
        let resumePendingFlows: () -> Void
    }

    static func animationTokenChanged(
        from previous: HomeAnimationRefreshToken,
        to current: HomeAnimationRefreshToken,
        handlers: Handlers
    ) {
        handlers.refreshAnimation()
        let changes = current.achievementChanges(from: previous)
        if changes.pendingAchievementChanged {
            handlers.reconcileAchievement()
        }
        if changes.shouldAttemptPresentation {
            handlers.presentAchievement()
        }
    }

    static func scenePhaseChanged(
        isActive: Bool,
        handlers: Handlers
    ) {
        guard isActive else { return }
        handlers.refreshAnimation()
        handlers.refreshOrnamentLights()
        handlers.presentAchievement()
        handlers.presentMorningSleep()
    }

    static func ripeBoChanged(_ isRipe: Bool, handlers: Handlers) {
        if isRipe { handlers.announceFirstRipeBo() }
    }

    static func animationStateChanged(
        handlers: Handlers
    ) {
        if handlers.currentHasRipeBo() {
            handlers.announceFirstRipeBo()
        }
    }

    static func sproutPhaseChanged(
        _ phase: SproutFlowPhase,
        handlers: Handlers
    ) {
        if phase == .idle { handlers.resumePendingFlows() }
    }
}

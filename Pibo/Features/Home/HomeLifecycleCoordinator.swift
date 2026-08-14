/// Preserves the ordered effects performed when Home enters the hierarchy.
/// SwiftUI lifecycle observation remains in `HomeLifecycleModifier`.
@MainActor
enum HomeLifecycleCoordinator {
    struct Handlers {
        let activateWeather: () -> Void
        let cacheGreeting: () -> Void
        let cacheDayLabel: () -> Void
        let speakForEnteredWeather: () -> Void
        let refreshAnimation: () -> Void
        let runDebugAutomation: () -> Void
        let presentAchievement: () -> Void
        let startSoundscape: () -> Void
        let presentMorningSleep: () -> Void
        let presentStressCard: () -> Void
        let announceFirstRipeBo: () -> Void
    }

    static func appeared(
        hasRipeBo: Bool,
        handlers: Handlers
    ) {
        handlers.activateWeather()
        handlers.cacheGreeting()
        handlers.cacheDayLabel()
        handlers.speakForEnteredWeather()
        handlers.refreshAnimation()
        handlers.runDebugAutomation()
        handlers.presentAchievement()
        handlers.startSoundscape()
        handlers.presentMorningSleep()
        handlers.presentStressCard()
        if hasRipeBo {
            handlers.announceFirstRipeBo()
        }
    }
}

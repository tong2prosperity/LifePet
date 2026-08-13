import Foundation

/// Owns the ordered side effects of the Settings "reset" action while each
/// store remains responsible for resetting its own state.
@MainActor
enum HomeResetCoordinator {
    struct Handlers {
        let trackReset: () -> Void
        let resetSpeechHistory: () -> Void
        let resetPetState: () -> Void
        let resetBoLedger: () -> Void
        let resetOnboarding: () -> Void
        let resetOrnamentUnlocks: () -> Void
        let resetOrnamentLights: () -> Void
        let clearFirstRipeAnnouncement: () -> Void
    }

    static func run(
        speech: PiboSpeechService,
        store: PetStateStore,
        boLedger: BoLedgerStore,
        onboarding: OnboardingStateStore,
        ornamentUnlocks: OrnamentUnlockStore,
        ornamentLights: OrnamentLightStore,
        defaults: UserDefaults = .standard
    ) {
        run(handlers: Handlers(
            trackReset: { Analytics.track(.reset, screen: "settings") },
            resetSpeechHistory: { speech.resetHistory() },
            resetPetState: { store.reset() },
            resetBoLedger: { boLedger.reset() },
            resetOnboarding: { onboarding.reset() },
            resetOrnamentUnlocks: { ornamentUnlocks.reset() },
            resetOrnamentLights: { ornamentLights.reset() },
            clearFirstRipeAnnouncement: {
                clearFirstRipeAnnouncement(in: defaults)
            }
        ))
    }

    static func run(handlers: Handlers) {
        handlers.trackReset()
        handlers.resetSpeechHistory()
        handlers.resetPetState()
        handlers.resetBoLedger()
        handlers.resetOnboarding()
        handlers.resetOrnamentUnlocks()
        handlers.resetOrnamentLights()
        handlers.clearFirstRipeAnnouncement()
    }

    static func clearFirstRipeAnnouncement(in defaults: UserDefaults) {
        defaults.removeObject(
            forKey: PiboPersistenceKeys.Defaults.boFirstRipeNotified
        )
    }
}

import PiboCore

/// Owns Home's ornament tap choreography. The overloads that accept services
/// are the production boundary; handler-based overloads keep ordering testable.
@MainActor
enum HomeOrnamentInteractionCoordinator {
    struct TapHandlers {
        let feedback: () -> Void
        let dismissSpeech: () -> Void
        let presentMorningSleep: (MorningSleepPresentation) -> Void
        let presentStatus: (CommonItemStatusModel) -> Void
    }

    struct LightTapHandlers {
        let light: (_ ornamentID: PiboOrnament.ID, _ index: Int) -> Bool
        let feedback: () -> Void
        let track: (_ ornamentID: PiboOrnament.ID, _ index: Int) -> Void
    }

    static func handleTap(
        ornamentID: PiboOrnament.ID,
        canPresent: () -> Bool,
        unlocks: OrnamentUnlockStore,
        morningSleep: MorningSleepCoordinator,
        history: HealthHistoryStore,
        dismissSpeech: @escaping () -> Void,
        present: @escaping (HomeSheetDestination) -> Void
    ) {
        handleTap(
            ornamentID: ornamentID,
            canPresent: canPresent,
            sleepReviewGranted: { unlocks.grants(.sleepReview) },
            latestSleepReview: { morningSleep.latestReviewPresentation() },
            recoveryStatusGranted: { unlocks.grants(.recoveryStatus) },
            recoveryCalibration: { history.recoveryCalibrationState() },
            handlers: TapHandlers(
                feedback: { LPHaptics.tap() },
                dismissSpeech: dismissSpeech,
                presentMorningSleep: {
                    present(.morningSleep($0, consumesPending: false))
                },
                presentStatus: { present(.commonItemStatus($0)) }
            )
        )
    }

    static func handleLightTap(
        ornamentID: PiboOrnament.ID,
        index: Int,
        unlocks: OrnamentUnlockStore,
        lights: OrnamentLightStore
    ) {
        handleLightTap(
            ornamentID: ornamentID,
            index: index,
            lightingGranted: { unlocks.grants(.lanternLighting) },
            handlers: LightTapHandlers(
                light: { lights.light($0, index: $1) },
                feedback: { LPHaptics.tap() },
                track: { id, index in
                    Analytics.track(
                        .ornamentLight,
                        screen: "home",
                        ["ornament": .string(id.rawValue), "index": .int(index)]
                    )
                }
            )
        )
    }

    static func handleTap(
        ornamentID: PiboOrnament.ID,
        canPresent: () -> Bool,
        sleepReviewGranted: () -> Bool,
        latestSleepReview: () -> MorningSleepPresentation?,
        recoveryStatusGranted: () -> Bool,
        recoveryCalibration: () -> RecoveryCalibrationState,
        handlers: TapHandlers
    ) {
        guard canPresent() else { return }

        handlers.feedback()
        handlers.dismissSpeech()

        let action = HomeOrnamentInteractionResolver.resolve(
            ornamentID: ornamentID,
            sleepReviewGranted: sleepReviewGranted(),
            latestSleepReview: latestSleepReview(),
            recoveryStatusGranted: recoveryStatusGranted(),
            recoveryCalibration: recoveryCalibration()
        )
        switch action {
        case .none:
            break
        case .presentMorningSleep(let presentation):
            handlers.presentMorningSleep(presentation)
        case .presentStatus(let model):
            handlers.presentStatus(model)
        }
    }

    static func handleLightTap(
        ornamentID: PiboOrnament.ID,
        index: Int,
        lightingGranted: () -> Bool,
        handlers: LightTapHandlers
    ) {
        guard ornamentID == .lantern,
              lightingGranted(),
              let placement = PiboOrnament.ornament(.lantern)?.placement,
              placement.lights.indices.contains(index)
        else { return }
        guard handlers.light(ornamentID, index) else { return }

        handlers.feedback()
        handlers.track(ornamentID, index)
    }
}

/// Owns the side-effect sequence that dismisses Home's collected-energy pop.
/// Sprout choreography remains in `HomeSproutFlowController`.
@MainActor
enum HomeEnergyCollectionCoordinator {
    struct Handlers {
        let tap: () -> Void
        let trackCollected: () -> Void
        let consumePendingWorkout: () -> Void
        let finishPop: () -> Void
    }

    static func dismissPop(
        store: PetStateStore,
        flow: HomeSproutFlowController
    ) {
        dismissPop(handlers: Handlers(
            tap: { LPHaptics.tap() },
            trackCollected: {
                Analytics.track(
                    .energyCollected,
                    screen: "home",
                    ["sprouted": .bool(store.growthStage == .sprouted)]
                )
            },
            consumePendingWorkout: { store.consumePendingWorkout() },
            finishPop: { flow.finishPop() }
        ))
    }

    static func dismissPop(handlers: Handlers) {
        handlers.tap()
        handlers.trackCollected()
        // 发芽只讲「收集到能量」。运动完成的成果表演归成果卡片，`pigu` 不在主场景
        // 出现 —— 这里曾经接着演一遍首页剧本，等于同一件事演两次。
        handlers.consumePendingWorkout()
        handlers.finishPop()
    }
}

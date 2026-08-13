import Foundation

#if DEBUG
@MainActor
enum HomeDebugLaunchAutomation {
    struct Handlers {
        let setForestHour: (Double?) -> Void
        let simulateLunch: () -> Void
        let openGames: () -> Void
        let openHistory: () -> Void
        let showMorningSleep: () -> Void
        let presentAchievementIfAvailable: (PiboAnimationAchievementPayload) -> Void
        let bounceToAnimationState: (String) -> Void
        let selectAnimationState: (String) -> Void
        let enqueueBoProgress: (BoProgressMilestone) -> Void
        let openBoPanel: () -> Void
        let openStressCard: () -> Void
    }

    struct Scheduler {
        let schedule: (
            _ delay: Duration,
            _ skipsWhenCancelled: Bool,
            _ action: @escaping @MainActor () -> Void
        ) -> Void

        static let live = Scheduler { delay, skipsWhenCancelled, action in
            Task { @MainActor in
                try? await Task.sleep(for: delay)
                guard !skipsWhenCancelled || !Task.isCancelled else { return }
                action()
            }
        }
    }

    static func run(
        options: HomeDebugLaunchOptions,
        miniGamesEnabled: @autoclosure () -> Bool,
        gamesAlreadyOpened: inout Bool,
        historyAlreadyOpened: inout Bool,
        handlers: Handlers,
        scheduler: Scheduler = .live
    ) {
        if case .value(let hour)? = options.forestHourOverride {
            handlers.setForestHour(hour)
        }
        if options.simulatesMeal {
            scheduler.schedule(.seconds(1), false, handlers.simulateLunch)
        }
        if miniGamesEnabled(), !gamesAlreadyOpened, options.opensGames {
            gamesAlreadyOpened = true
            scheduler.schedule(.milliseconds(350), false, handlers.openGames)
        }
        if !historyAlreadyOpened, options.opensHistory {
            historyAlreadyOpened = true
            scheduler.schedule(.milliseconds(350), false, handlers.openHistory)
        }
        if options.showsMorningSleep {
            handlers.showMorningSleep()
        }
        if let kind = options.achievementKind {
            let payload = PiboAnimationAchievementPayload(
                id: UUID(),
                kind: kind,
                occurredAt: .now,
                workoutLabel: kind == .pigu ? "跑步" : nil,
                workoutDurationMinutes: kind == .pigu ? 30 : nil
            )
            scheduler.schedule(.milliseconds(350), false) {
                handlers.presentAchievementIfAvailable(payload)
            }
        }
        if let target = options.bounceTargetStateID {
            scheduler.schedule(.seconds(2), true) {
                handlers.bounceToAnimationState(target)
            }
        }
        if let target = options.selectedStateIDAfterDelay {
            scheduler.schedule(.seconds(3), true) {
                handlers.selectAnimationState(target)
            }
        }
        if let milestone = options.boProgressMilestone {
            handlers.enqueueBoProgress(milestone)
        }
        if options.opensBoPanel {
            scheduler.schedule(.milliseconds(500), false, handlers.openBoPanel)
        }
        if options.opensStressCard {
            handlers.openStressCard()
        }
    }
}
#endif

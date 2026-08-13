import Foundation
import XCTest
@testable import Pibo

#if DEBUG
@MainActor
final class HomeDebugLaunchAutomationTests: XCTestCase {
    func testNoOptionsScheduleOrPerformNothing() {
        let recorder = Recorder()
        var gamesOpened = false
        var historyOpened = false

        HomeDebugLaunchAutomation.run(
            options: HomeDebugLaunchOptions(arguments: ["Pibo"]),
            miniGamesEnabled: true,
            gamesAlreadyOpened: &gamesOpened,
            historyAlreadyOpened: &historyOpened,
            handlers: recorder.handlers,
            scheduler: recorder.scheduler
        )

        XCTAssertFalse(gamesOpened)
        XCTAssertFalse(historyOpened)
        XCTAssertEqual(recorder.events, [])
        XCTAssertEqual(recorder.scheduled.count, 0)
    }

    func testAllOptionsPreserveImmediateAndScheduledActionOrder() {
        let recorder = Recorder()
        var gamesOpened = false
        var historyOpened = false
        let options = HomeDebugLaunchOptions(arguments: [
            "Pibo",
            "-PiboForestHour=6.5",
            "-PiboSimulateMeal",
            "-PiboOpenGames",
            "-PiboOpenHistory",
            "-PiboShowMorningSleep",
            "-PiboShowAchievement=pigu",
            "-PiboBounceTo=angry",
            "-PiboSelectStateAfter=dive",
            "-PiboBoProgress=75",
            "-PiboOpenBoPanel",
            "-PiboOpenStressCard",
        ])

        HomeDebugLaunchAutomation.run(
            options: options,
            miniGamesEnabled: true,
            gamesAlreadyOpened: &gamesOpened,
            historyAlreadyOpened: &historyOpened,
            handlers: recorder.handlers,
            scheduler: recorder.scheduler
        )

        XCTAssertTrue(gamesOpened)
        XCTAssertTrue(historyOpened)
        XCTAssertEqual(
            recorder.events,
            ["forest:6.5", "morning", "progress:75", "stress"]
        )
        XCTAssertEqual(
            recorder.scheduled.map(\.delay),
            [
                .seconds(1), .milliseconds(350), .milliseconds(350),
                .milliseconds(350), .seconds(2), .seconds(3), .milliseconds(500),
            ]
        )
        XCTAssertEqual(
            recorder.scheduled.map(\.skipsWhenCancelled),
            [false, false, false, false, true, true, false]
        )

        recorder.performScheduledActions()
        XCTAssertEqual(
            recorder.events,
            [
                "forest:6.5", "morning", "progress:75", "stress",
                "meal", "games", "history", "achievement:pigu:跑步:30",
                "bounce:angry", "select:dive", "bo-panel",
            ]
        )
    }

    func testGamesAndHistoryOneShotGatesDoNotScheduleOrMutateAgain() {
        let recorder = Recorder()
        var gamesOpened = true
        var historyOpened = true
        let options = HomeDebugLaunchOptions(arguments: [
            "-PiboOpenGames",
            "-PiboOpenHistory",
        ])

        HomeDebugLaunchAutomation.run(
            options: options,
            miniGamesEnabled: true,
            gamesAlreadyOpened: &gamesOpened,
            historyAlreadyOpened: &historyOpened,
            handlers: recorder.handlers,
            scheduler: recorder.scheduler
        )

        XCTAssertTrue(gamesOpened)
        XCTAssertTrue(historyOpened)
        XCTAssertEqual(recorder.scheduled.count, 0)
    }

    func testDisabledMiniGamesStayUnopenedWhileHistoryStillSchedules() {
        let recorder = Recorder()
        var gamesOpened = false
        var historyOpened = false
        let options = HomeDebugLaunchOptions(arguments: [
            "-PiboOpenGames",
            "-PiboOpenHistory",
        ])

        HomeDebugLaunchAutomation.run(
            options: options,
            miniGamesEnabled: false,
            gamesAlreadyOpened: &gamesOpened,
            historyAlreadyOpened: &historyOpened,
            handlers: recorder.handlers,
            scheduler: recorder.scheduler
        )

        XCTAssertFalse(gamesOpened)
        XCTAssertTrue(historyOpened)
        XCTAssertEqual(recorder.scheduled.map(\.delay), [.milliseconds(350)])
        recorder.performScheduledActions()
        XCTAssertEqual(recorder.events, ["history"])
    }

    func testMiniGamesAvailabilityIsReadAfterEarlierLaunchWork() {
        let recorder = Recorder()
        var gamesOpened = false
        var historyOpened = false
        let options = HomeDebugLaunchOptions(arguments: [
            "-PiboForestHour=6.5",
            "-PiboSimulateMeal",
        ])

        HomeDebugLaunchAutomation.run(
            options: options,
            miniGamesEnabled: recorder.readMiniGamesEnabled(),
            gamesAlreadyOpened: &gamesOpened,
            historyAlreadyOpened: &historyOpened,
            handlers: recorder.handlers,
            scheduler: recorder.scheduler
        )

        XCTAssertEqual(recorder.events, ["forest:6.5", "mini-games-enabled"])
        XCTAssertEqual(recorder.scheduled.map(\.delay), [.seconds(1)])
    }
}

@MainActor
private final class Recorder {
    struct Scheduled {
        let delay: Duration
        let skipsWhenCancelled: Bool
        let action: @MainActor () -> Void
    }

    var events: [String] = []
    var scheduled: [Scheduled] = []

    var handlers: HomeDebugLaunchAutomation.Handlers {
        .init(
            setForestHour: { [self] hour in events.append("forest:\(hour ?? -1)") },
            simulateLunch: { [self] in events.append("meal") },
            openGames: { [self] in events.append("games") },
            openHistory: { [self] in events.append("history") },
            showMorningSleep: { [self] in events.append("morning") },
            presentAchievementIfAvailable: { [self] payload in
                events.append(
                    "achievement:\(payload.kind.rawValue):"
                        + "\(payload.workoutLabel ?? "nil"):"
                        + "\(payload.workoutDurationMinutes ?? -1)"
                )
            },
            bounceToAnimationState: { [self] in events.append("bounce:\($0)") },
            selectAnimationState: { [self] in events.append("select:\($0)") },
            enqueueBoProgress: { [self] in events.append("progress:\($0.rawValue)") },
            openBoPanel: { [self] in events.append("bo-panel") },
            openStressCard: { [self] in events.append("stress") }
        )
    }

    var scheduler: HomeDebugLaunchAutomation.Scheduler {
        .init { [self] delay, skipsWhenCancelled, action in
            scheduled.append(.init(
                delay: delay,
                skipsWhenCancelled: skipsWhenCancelled,
                action: action
            ))
        }
    }

    func performScheduledActions() {
        scheduled.forEach { $0.action() }
    }

    func readMiniGamesEnabled() -> Bool {
        events.append("mini-games-enabled")
        return true
    }
}
#endif

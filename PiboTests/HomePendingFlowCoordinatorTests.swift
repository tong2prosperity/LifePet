import XCTest
@testable import Pibo

@MainActor
final class HomePendingFlowCoordinatorTests: XCTestCase {
    func testAchievementSheetStopsEveryLowerPriorityAttempt() {
        let recorder = Recorder(sheetReads: [false])

        HomePendingFlowCoordinator.resume(handlers: recorder.handlers)

        XCTAssertEqual(recorder.events, [
            "clear-dismissal",
            "achievement",
            "sheet",
        ])
    }

    func testMorningSheetStillAllowsStressAttemptBeforeBlockingAnnouncement() {
        let recorder = Recorder(sheetReads: [true, false])

        HomePendingFlowCoordinator.resume(handlers: recorder.handlers)

        XCTAssertEqual(recorder.events, [
            "clear-dismissal",
            "achievement",
            "sheet",
            "morning-sleep",
            "stress-card",
            "sheet",
        ])
    }

    func testUnoccupiedHomeAttemptsEveryFlowInExistingPriorityOrder() {
        let recorder = Recorder(sheetReads: [true, true])

        HomePendingFlowCoordinator.resume(handlers: recorder.handlers)

        XCTAssertEqual(recorder.events, [
            "clear-dismissal",
            "achievement",
            "sheet",
            "morning-sleep",
            "stress-card",
            "sheet",
            "first-ripe-bo",
        ])
    }

    func testSheetStateIsReadAgainAfterLowerPriorityAttempts() {
        let recorder = Recorder(sheetReads: [true, false])

        HomePendingFlowCoordinator.resume(handlers: recorder.handlers)

        XCTAssertEqual(recorder.sheetReadCount, 2)
    }
}

@MainActor
private final class Recorder {
    private(set) var events: [String] = []
    private(set) var sheetReadCount = 0
    private var sheetReads: [Bool]

    init(sheetReads: [Bool]) {
        self.sheetReads = sheetReads
    }

    var handlers: HomePendingFlowCoordinator.Handlers {
        HomePendingFlowCoordinator.Handlers(
            clearSheetDismissal: { self.events.append("clear-dismissal") },
            presentAchievement: { self.events.append("achievement") },
            sheetIsAbsent: {
                self.events.append("sheet")
                self.sheetReadCount += 1
                return self.sheetReads.removeFirst()
            },
            presentMorningSleep: { self.events.append("morning-sleep") },
            presentStressCard: { self.events.append("stress-card") },
            announceFirstRipeBo: { self.events.append("first-ripe-bo") }
        )
    }
}

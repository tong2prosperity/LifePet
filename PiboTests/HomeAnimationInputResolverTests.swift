import Foundation
import PiboCore
import XCTest
@testable import Pibo

@MainActor
final class HomeAnimationInputResolverTests: XCTestCase {
    func testSleepHistoryWindowStartsFortyDaysAgoAndEndsYesterday() throws {
        let calendar = calendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 14,
            hour: 15,
            minute: 30
        )))

        let window = HomeAnimationInputResolver.sleepHistoryWindow(
            at: now,
            calendar: calendar
        )

        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: window.start),
            DateComponents(year: 2026, month: 7, day: 5)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: window.end),
            DateComponents(year: 2026, month: 8, day: 13)
        )
    }

    func testResolvePreservesEveryPlatformMapping() throws {
        let calendar = calendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 14,
            hour: 15,
            minute: 30,
            second: 45
        )))
        let measuredAt = now.addingTimeInterval(-120)
        let baseline = StressBaseline(
            meanLn: log(50),
            sdLn: 0.2,
            dayCount: 9,
            geoMean: 50
        )
        let retainedNights = Array(repeating: 7.0, count: 28)
        let sleepHistoryTotals: [TimeInterval] = [-1, 6 * 3_600]
            + retainedNights.map { $0 * 3_600 }

        let input = HomeAnimationInputResolver.resolve(
            at: now,
            calendar: calendar,
            sleepHistoryTotals: sleepHistoryTotals,
            localHour: 15.5125,
            rawSleepHours: 7.25,
            hasStepsData: true,
            rawSteps: 4_321,
            hasWorkoutToday: true,
            angryActive: true,
            rmssd: 50,
            rmssdMeasuredAt: measuredAt,
            rmssdInterpretationEligible: true,
            stressBaseline: baseline,
            previousStressStateID: "dive",
            heldAchievement: .muscle
        )

        XCTAssertEqual(input.localHour, 15.5125, accuracy: 0.000_001)
        XCTAssertTrue(input.hasSleepData)
        XCTAssertEqual(input.sleepHours, 7.25)
        XCTAssertEqual(
            input.sleepReferenceHours,
            PiboCoreAnimationAdapter.sleepReference(history: retainedNights).hours
        )
        XCTAssertTrue(input.hasActivityData)
        XCTAssertEqual(input.steps, 4_321)
        XCTAssertTrue(input.hasWorkoutToday)
        XCTAssertFalse(input.postPluckSleep)
        XCTAssertEqual(input.sleepDayKey, 20_260_814)
        XCTAssertTrue(input.angryActive)
        XCTAssertTrue(input.hasEligibleRMSSD)
        XCTAssertEqual(input.stressBaselineDays, 9)
        XCTAssertEqual(input.stressZ, 0, accuracy: 0.000_001)
        XCTAssertEqual(input.rmssdAgeSeconds, 120)
        XCTAssertEqual(input.previousStressStateID, "dive")
        XCTAssertEqual(input.heldAchievement, PiboAnimationAchievementKind.muscle)
    }

    func testMissingRmssdKeepsInterpretationEligibilityLazy() {
        var eligibilityRead = false

        let input = HomeAnimationInputResolver.resolve(
            at: Date(timeIntervalSince1970: 0),
            calendar: calendar(),
            sleepHistoryTotals: [],
            localHour: 8,
            rawSleepHours: 0,
            hasStepsData: false,
            rawSteps: 0,
            hasWorkoutToday: false,
            angryActive: false,
            rmssd: nil,
            rmssdMeasuredAt: nil,
            rmssdInterpretationEligible: read(&eligibilityRead, value: true),
            stressBaseline: nil,
            previousStressStateID: "default",
            heldAchievement: nil
        )

        XCTAssertFalse(input.hasEligibleRMSSD)
        XCTAssertFalse(eligibilityRead)
        XCTAssertEqual(input.rmssdAgeSeconds, .greatestFiniteMagnitude)
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func read<T>(_ didRead: inout Bool, value: T) -> T {
        didRead = true
        return value
    }
}

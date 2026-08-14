import Foundation
import PiboCore
import XCTest
@testable import Pibo

@MainActor
final class HomeAnimationInputResolverTests: XCTestCase {
    func testSleepHistoryWindowCoversRecentFourteenWakeDays() throws {
        let calendar = calendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 14, hour: 15, minute: 30
        )))
        let window = HomeAnimationInputResolver.sleepHistoryWindow(
            at: now,
            calendar: calendar
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: window.start),
            DateComponents(year: 2026, month: 8, day: 1)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: window.end),
            DateComponents(year: 2026, month: 8, day: 14)
        )
    }

    func testOnlyCompletePairedMainSleepBecomesRoutineInput() throws {
        let calendar = calendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 14, hour: 12
        )))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 13, hour: 23, minute: 30
        )))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 14, hour: 7, minute: 30
        )))
        let complete = HealthDayRecord(
            date: calendar.startOfDay(for: now),
            sleepTotal: 8 * 3_600,
            sleepStart: start,
            sleepEnd: end
        )
        let incomplete = HealthDayRecord(
            date: calendar.date(byAdding: .day, value: -1, to: now)!,
            sleepTotal: 7 * 3_600,
            sleepStart: start,
            sleepEnd: nil
        )

        let nights = HomeAnimationInputResolver.nights(
            from: [incomplete, complete],
            at: now,
            calendar: calendar
        )
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[0].bedtimeMinutes, 23 * 60 + 30)
        XCTAssertEqual(nights[0].wakeMinutes, 7 * 60 + 30)
        XCTAssertEqual(nights[0].dayOffset, 0)
    }

    func testResolveUsesCoreDecisionWithoutASecondAnimationMachine() {
        let input = HomeAnimationInputResolver.resolve(
            at: Date(timeIntervalSince1970: 12 * 3_600),
            calendar: utcCalendar(),
            records: [],
            hasActivityData: true,
            steps: 10_000,
            lastWorkoutEndedAt: nil
        )
        XCTAssertEqual(input.decision.state, .energetic)
        XCTAssertEqual(input.sleepDayKey, 19_700_101)
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

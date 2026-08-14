import Foundation
import PiboCore
import Testing
@testable import Pibo

@Test func rustSingleStateRulesDriveTheAppDomain() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let noon = calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 14,
        hour: 12
    ))!
    let night = PiboCoreSleepWeeklyNight(
        totalSeconds: 7 * 3_600,
        deepSeconds: 0,
        remSeconds: 0,
        awakeSeconds: 0,
        bedtimeMinutes: 0,
        wakeMinutes: 480,
        dayOffset: 0
    )

    let stable = PiboCoreStateAdapter.decide(
        at: noon,
        calendar: calendar,
        hasActivityData: true,
        steps: 2_000,
        lastWorkoutEndedAt: nil,
        nights: [night]
    )
    #expect(stable.state == .stable)

    let energetic = PiboCoreStateAdapter.decide(
        at: noon,
        calendar: calendar,
        hasActivityData: true,
        steps: 2_000,
        lastWorkoutEndedAt: noon.addingTimeInterval(-60),
        nights: []
    )
    #expect(energetic.state == .energetic)
    #expect(energetic.cause == .recentWorkout)
}

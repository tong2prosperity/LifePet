import Testing
@testable import Pibo

@Test func rustActivityRulesDriveTheAppDomain() {
    #expect(PiboCoreActivityAdapter.state(
        localHour: 23,
        recentPatCount: 0,
        postPluckSleep: false,
        hasRealHealthData: true,
        steps: 12_000,
        hasWorkoutToday: true,
        sleepHours: 8
    ) == .deepSleep)
    #expect(PiboCoreActivityAdapter.state(
        localHour: 14,
        recentPatCount: 3,
        postPluckSleep: false,
        hasRealHealthData: true,
        steps: 5_000,
        hasWorkoutToday: false,
        sleepHours: 7
    ) == .disturbed)
    #expect(PiboCoreActivityAdapter.state(
        localHour: 14,
        recentPatCount: 0,
        postPluckSleep: false,
        hasRealHealthData: true,
        steps: 2_000,
        hasWorkoutToday: false,
        sleepHours: 7
    ) == .irritated)
}


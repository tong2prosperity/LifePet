import Testing
@testable import Pibo

@Test func rustPluckRulesDriveTheAppDomain() {
    #expect(PiboCorePluckAdapter.windowOpen(localHour: 22))
    #expect(PiboCorePluckAdapter.windowOpen(localHour: 1.5))
    #expect(!PiboCorePluckAdapter.windowOpen(localHour: 2))
    #expect(PiboCorePluckAdapter.grade(
        sleepHours: 7,
        steps: 500,
        hasWorkoutToday: true
    ) == .good)
    #expect(PiboCorePluckAdapter.grade(
        sleepHours: 7,
        steps: 3_000,
        hasWorkoutToday: false
    ) == .fair)
    #expect(PiboCorePluckAdapter.grade(
        sleepHours: 5,
        steps: 10_000,
        hasWorkoutToday: true
    ) == .poor)
}


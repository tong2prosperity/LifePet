import Testing
@testable import Pibo

@Test func rustWorkoutMetricsDriveHistory() {
    let run = PiboCoreWorkoutAdapter.metrics(durationSeconds: 1_500, distanceMeters: 5_000)
    #expect(run.durationMinutes == 25)
    #expect(run.paceMinutesPerKilometer == 5)
    #expect(PiboCoreWorkoutAdapter.metrics(
        durationSeconds: 119.9,
        distanceMeters: 0
    ).durationMinutes == 1)
    #expect(PiboCoreWorkoutAdapter.metrics(
        durationSeconds: 1_500,
        distanceMeters: 50
    ).paceMinutesPerKilometer == nil)
}

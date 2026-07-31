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

@Test func rustWorkoutEventPolicyDrivesHomeCollection() {
    let short = PiboCoreWorkoutAdapter.eventPolicy(durationSeconds: 20, ageSeconds: 299.999)
    #expect(short.durationMinutes == 1)
    #expect(short.vitalityGain == 1)
    #expect(short.isFresh)

    let long = PiboCoreWorkoutAdapter.eventPolicy(durationSeconds: 7_200, ageSeconds: 300)
    #expect(long.durationMinutes == 120)
    #expect(long.vitalityGain == 60)
    #expect(!long.isFresh)
}

@Test func workoutFreshnessDependsOnAgeRatherThanHealthKitAnchorHistory() {
    // The acquisition layer can label the first anchored query historical,
    // but a workout that ended seconds ago still belongs to direct-open UX.
    let fresh = PiboCoreWorkoutAdapter.eventPolicy(
        durationSeconds: 1_800,
        ageSeconds: 30
    )
    let stale = PiboCoreWorkoutAdapter.eventPolicy(
        durationSeconds: 1_800,
        ageSeconds: 301
    )
    #expect(PiboCoreWorkoutAdapter.achievementShouldQueue(
        policy: fresh,
        occurredToday: true
    ))
    #expect(!PiboCoreWorkoutAdapter.achievementShouldQueue(
        policy: stale,
        occurredToday: true
    ))
    #expect(!PiboCoreWorkoutAdapter.achievementShouldQueue(
        policy: fresh,
        occurredToday: false
    ))
}

@Test func rustPendingWorkoutPolicyDrivesRestorationAndLiveActivityExpiry() {
    let maxAge = PiboCoreWorkoutAdapter.pendingWorkoutMaxAgeSeconds
    #expect(maxAge == 86_400)
    #expect(PiboCoreWorkoutAdapter.pendingWorkoutIsRestorable(
        ageSeconds: maxAge,
        sameDay: true
    ))
    #expect(PiboCoreWorkoutAdapter.pendingWorkoutIsRestorable(
        ageSeconds: maxAge + 0.001,
        sameDay: true
    ))
    #expect(!PiboCoreWorkoutAdapter.pendingWorkoutIsRestorable(
        ageSeconds: 60,
        sameDay: false
    ))
}

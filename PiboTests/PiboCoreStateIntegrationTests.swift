import Foundation
import PiboCore
import Testing
@testable import Pibo

@Test func rustLifecycleRulesDriveTheAppDomain() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let noon = calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 14,
        hour: 12
    ))!

    let stable = PiboCoreStateAdapter.resolve(
        snapshot: PiboCoreStatePolicy.initialSnapshot(),
        at: noon,
        calendar: calendar,
        hasActivityData: true,
        lastWorkoutEndedAt: nil,
        activityMilestoneReachedAt: nil,
        nights: []
    )
    #expect(stable.decision.state == .stable)

    let energetic = PiboCoreStateAdapter.resolve(
        snapshot: stable.snapshot,
        at: noon,
        calendar: calendar,
        hasActivityData: true,
        lastWorkoutEndedAt: noon.addingTimeInterval(-60),
        activityMilestoneReachedAt: nil,
        nights: []
    )
    #expect(energetic.decision.state == .energetic)
    #expect(energetic.decision.cause == .recentWorkout)

    let later = PiboCoreStateAdapter.resolve(
        snapshot: energetic.snapshot,
        at: noon.addingTimeInterval(4 * 3_600),
        calendar: calendar,
        hasActivityData: true,
        lastWorkoutEndedAt: noon.addingTimeInterval(-60),
        activityMilestoneReachedAt: nil,
        nights: []
    )
    #expect(later.decision.state == .energetic)

    let coldLaunchWithOldWorkout = PiboCoreStateAdapter.resolve(
        snapshot: PiboCoreStatePolicy.initialSnapshot(),
        at: noon,
        calendar: calendar,
        hasActivityData: true,
        lastWorkoutEndedAt: noon.addingTimeInterval(-4 * 3_600),
        activityMilestoneReachedAt: nil,
        nights: []
    )
    #expect(coldLaunchWithOldWorkout.decision.state == .stable)
}

@Test func lifecycleSnapshotPersistsAcrossLaunches() throws {
    let suite = "PiboStateLifecyclePersistence.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let snapshot = PiboCoreStatePolicy.reduce(
        PiboCoreStatePolicy.initialSnapshot(),
        event: .workoutCompleted,
        occurredAt: 100
    ).snapshot
    PiboStateLifecyclePersistence.save(snapshot, to: defaults)
    #expect(PiboStateLifecyclePersistence.load(from: defaults) == snapshot)
    PiboStateLifecyclePersistence.reset(in: defaults)
    #expect(PiboStateLifecyclePersistence.load(from: defaults).eventAt == nil)
}

@Test func insufficientSleepDuringWakeWindowSelectsGroundRecoveryBehavior() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let wakeDay = calendar.date(from: DateComponents(
        year: 2026, month: 8, day: 16
    ))!
    let resolution = PiboCoreStateAdapter.resolve(
        snapshot: PiboCoreStatePolicy.initialSnapshot(),
        at: wakeDay.addingTimeInterval(8 * 3_600 + 30 * 60),
        calendar: calendar,
        hasActivityData: true,
        lastWorkoutEndedAt: nil,
        activityMilestoneReachedAt: nil,
        nights: [PiboCoreSleepWeeklyNight(
            totalSeconds: 4 * 3_600,
            deepSeconds: 0,
            remSeconds: 0,
            awakeSeconds: 0,
            bedtimeMinutes: 4 * 60,
            wakeMinutes: 8 * 60,
            dayOffset: 0
        )]
    )

    #expect(resolution.decision.state == .waking)
    #expect(resolution.decision.pendingState == .tired)
    #expect(resolution.decision.pendingCause == .insufficientSleep)
    #expect(PiboAnimationStateMap.presentedAmbientStateID(
        semanticStateID: PiboCoreAnimationAdapter.ambientStateID(for: resolution.decision.state),
        state: resolution.decision.state,
        hasHammock: false,
        needsWakingRecovery: true
    ) == PiboAnimationResourceID.wakingGroundRecovering)
}

@Test func lateCurrentNightCorrectsTheFinishedWakeWindowAfterRoutineChanges() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let wakeDay = calendar.date(from: DateComponents(
        year: 2026, month: 8, day: 14
    ))!
    let beforeSleepArrives = PiboCoreStateAdapter.resolve(
        snapshot: PiboCoreStatePolicy.initialSnapshot(),
        at: wakeDay.addingTimeInterval(8 * 3_600 + 40 * 60),
        calendar: calendar,
        hasActivityData: false,
        lastWorkoutEndedAt: nil,
        activityMilestoneReachedAt: nil,
        nights: []
    )
    #expect(beforeSleepArrives.decision.state == .dataUnknown)
    #expect(beforeSleepArrives.snapshot.wakeStartedAt != nil)

    let otherHealthArrivesFirst = PiboCoreStateAdapter.resolve(
        snapshot: beforeSleepArrives.snapshot,
        at: wakeDay.addingTimeInterval(8 * 3_600 + 50 * 60),
        calendar: calendar,
        hasActivityData: true,
        lastWorkoutEndedAt: nil,
        activityMilestoneReachedAt: nil,
        nights: []
    )
    #expect(otherHealthArrivesFirst.decision.state == .stable)
    #expect(otherHealthArrivesFirst.snapshot.wakeStartedAt != nil)

    let corrected = PiboCoreStateAdapter.resolve(
        snapshot: otherHealthArrivesFirst.snapshot,
        at: wakeDay.addingTimeInterval(9 * 3_600),
        calendar: calendar,
        hasActivityData: true,
        lastWorkoutEndedAt: nil,
        activityMilestoneReachedAt: nil,
        nights: [PiboCoreSleepWeeklyNight(
            totalSeconds: 4 * 3_600,
            deepSeconds: 0,
            remSeconds: 0,
            awakeSeconds: 0,
            bedtimeMinutes: 4 * 60,
            wakeMinutes: 8 * 60,
            dayOffset: 0
        )]
    )
    #expect(corrected.decision.state == .tired)
    #expect(corrected.decision.cause == .insufficientSleep)
}

@Test func workoutInterruptionCannotBeOverwrittenByLateSleepData() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let wakeDay = calendar.date(from: DateComponents(
        year: 2026, month: 8, day: 14
    ))!
    let workoutAt = wakeDay.addingTimeInterval(7 * 3_600 + 45 * 60)
    let interrupted = PiboCoreStateAdapter.resolve(
        snapshot: PiboCoreStatePolicy.initialSnapshot(),
        at: wakeDay.addingTimeInterval(8 * 3_600),
        calendar: calendar,
        hasActivityData: true,
        lastWorkoutEndedAt: workoutAt,
        activityMilestoneReachedAt: nil,
        nights: []
    )
    #expect(interrupted.decision.state == .energetic)
    #expect(interrupted.snapshot.wakeStartedAt == nil)

    let lateSleep = PiboCoreStateAdapter.resolve(
        snapshot: interrupted.snapshot,
        at: wakeDay.addingTimeInterval(9 * 3_600),
        calendar: calendar,
        hasActivityData: true,
        lastWorkoutEndedAt: workoutAt,
        activityMilestoneReachedAt: nil,
        nights: [PiboCoreSleepWeeklyNight(
            totalSeconds: 4 * 3_600,
            deepSeconds: 0,
            remSeconds: 0,
            awakeSeconds: 0,
            bedtimeMinutes: 4 * 60,
            wakeMinutes: 8 * 60,
            dayOffset: 0
        )]
    )
    #expect(lateSleep.decision.state == .energetic)
}

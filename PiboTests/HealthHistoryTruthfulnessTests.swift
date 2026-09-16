import Foundation
import SwiftData
import Testing
@testable import Pibo

/// Recorded flags, no zero-writes, monotonic today steps, cached stages, and
/// the page's day model (no fabricated hourly data, no future dates).
@MainActor
struct HealthHistoryTruthfulnessTests {
    /// Held for the whole test: a discarded `ModelContainer` invalidates the
    /// store's context and crashes on the first fetch.
    private let container: ModelContainer
    private let defaults: UserDefaults
    private let store: HealthHistoryStore

    init() throws {
        let suite = "pibo.tests.history-truth.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        container = try ModelContainer(
            for: HealthDayRecord.self, WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = HealthHistoryStore(
            context: container.mainContext,
            provenanceDefaults: defaults,
            syntheticDaysKey: "test.synthetic-days",
            syntheticWorkoutIDsKey: "test.synthetic-workouts"
        )
    }

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }
    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: today)! }

    @Test func emptyQueryResultDoesNotCreateAnAllZeroDay() throws {
        store.ingest([HealthDayValues(date: yesterday)])
        #expect(store.record(on: yesterday) == nil)
    }

    @Test func aFirstRealZeroIsRecordedAndShownAsZero() throws {
        store.ingest([HealthDayValues(date: yesterday, steps: 0, stepsRecorded: true)])
        let record = try #require(store.record(on: yesterday))
        #expect(record.stepsRecorded == true)
        #expect(record.recordedSteps == 0)
        #expect(record.recordedActiveEnergy == nil)
        #expect(record.activeEnergyRecorded == nil)
    }

    @Test func legacyRowsCountPositiveValuesButNotAmbiguousZeros() {
        let record = HealthDayRecord(date: yesterday, steps: 5_000, activeEnergy: 0, exerciseMinutes: 0)
        #expect(record.recordedSteps == 5_000)
        #expect(record.recordedActiveEnergy == nil)
        #expect(record.recordedExerciseMinutes == nil)
        #expect(record.recordedStandMinutes == nil)
    }

    @Test func missingMetricsNeverOverwriteRecordedValues() throws {
        store.ingest([HealthDayValues(
            date: yesterday, steps: 6_000, activeEnergy: 300,
            stepsRecorded: true, activeEnergyRecorded: true
        )])
        // A later partial read (e.g. only sleep arrived) must not zero them.
        store.ingest([HealthDayValues(date: yesterday, sleepTotal: 7 * 3_600)])
        let record = try #require(store.record(on: yesterday))
        #expect(record.steps == 6_000)
        #expect(record.activeEnergy == 300)
        #expect(record.sleepTotal == 7 * 3_600)
    }

    @Test func todayStepsOnlyMoveForward() throws {
        store.ingest([HealthDayValues(date: today, steps: 4_200, stepsRecorded: true)])
        store.ingest([HealthDayValues(date: today, steps: 3_900, stepsRecorded: true)])
        #expect(store.record(on: today)?.steps == 4_200)
        store.ingest([HealthDayValues(date: today, steps: 4_800, stepsRecorded: true)])
        #expect(store.record(on: today)?.steps == 4_800)
    }

    @Test func pastDayStepsFollowTheProvider() throws {
        store.ingest([HealthDayValues(date: yesterday, steps: 4_200, stepsRecorded: true)])
        store.ingest([HealthDayValues(date: yesterday, steps: 3_900, stepsRecorded: true)])
        #expect(store.record(on: yesterday)?.steps == 3_900)
    }

    @Test func emptyStageResponseKeepsCachedStagesOfTheSameNight() throws {
        let start = yesterday.addingTimeInterval(-60 * 60)
        let end = yesterday.addingTimeInterval(6 * 60 * 60)
        let segments = [
            SleepSegmentValue(start: start, end: start.addingTimeInterval(3 * 3_600), stage: .core),
            SleepSegmentValue(start: start.addingTimeInterval(3 * 3_600), end: end, stage: .deep),
        ]
        store.ingest([HealthDayValues(
            date: yesterday, sleepTotal: 7 * 3_600, sleepStart: start, sleepEnd: end,
            sleepSegments: segments
        )])
        store.ingest([HealthDayValues(
            date: yesterday, sleepTotal: 7 * 3_600, sleepStart: start, sleepEnd: end,
            sleepSegments: []
        )])
        #expect(store.record(on: yesterday)?.sleepSegments == segments)

        // A non-empty later response still replaces the cache.
        let replacement = [SleepSegmentValue(start: start, end: end, stage: .core)]
        store.ingest([HealthDayValues(
            date: yesterday, sleepTotal: 7 * 3_600, sleepStart: start, sleepEnd: end,
            sleepSegments: replacement
        )])
        #expect(store.record(on: yesterday)?.sleepSegments == replacement)
    }

    @Test func inBedDurationMustBePhysical() {
        #expect(HealthDataService.isPhysicalInBedDuration(8 * 3_600))
        #expect(!HealthDataService.isPhysicalInBedDuration(0))
        #expect(!HealthDataService.isPhysicalInBedDuration(-5))
        #expect(!HealthDataService.isPhysicalInBedDuration(25 * 3_600))
        #expect(!HealthDataService.isPhysicalInBedDuration(.infinity))
    }

    // MARK: Day model

    @Test func aggregateOnlyStepsNeverGetHourlyColumns() {
        let record = HealthDayRecord(date: yesterday, steps: 7_000)
        let day = HistoryDayDisplay.make(date: yesterday, record: record)
        #expect(day.steps == 7_000)
        #expect(day.hourlySteps == nil)
        #expect(HistoryStepsCard.columns(steps: day.steps, hourlySteps: day.hourlySteps) == [7_000])
        #expect(HistoryStepsCard.columns(steps: nil, hourlySteps: nil).isEmpty)
        #expect(HistoryStepsCard.columns(steps: 0, hourlySteps: nil).isEmpty)
    }

    @Test func realHourlyStepsCoverTheWholeLocalDay() {
        var hourly = Array(repeating: 0, count: 24)
        hourly[23] = 480
        hourly[2] = 30
        let record = HealthDayRecord(date: yesterday, steps: 510, hourlySteps: hourly)
        let day = HistoryDayDisplay.make(date: yesterday, record: record)
        let columns = HistoryStepsCard.columns(steps: day.steps, hourlySteps: day.hourlySteps)
        #expect(columns.count == 24)
        #expect(columns[23] == 480)
        #expect(HistoryStepsCard.hourLabel(23) == "23:00-24:00")
        #expect(HistoryStepsCard.hourLabel(0) == "00:00-01:00")
    }

    @Test func missingDayReadsAsUnrecordedAcrossTheBoard() {
        let day = HistoryDayDisplay.make(date: yesterday, record: nil)
        #expect(day.steps == nil)
        #expect(day.activeEnergy == nil)
        #expect(day.exerciseMinutes == nil)
        #expect(day.standHours == nil)
        #expect(day.heartRate == nil)
        #expect(day.sleep.total == 0)
        #expect(!day.hasAnyActivity)
    }

    @Test func sleepCardRangeUsesRecordedFallAsleepAndWakeTimes() {
        let record = HealthDayRecord(date: yesterday)
        let asleep = yesterday.addingTimeInterval(-3 * 3_600)
        let woke = yesterday.addingTimeInterval(5 * 3_600)
        record.sleepTotal = 6 * 3_600      // net sleep < span
        record.sleepStart = asleep
        record.sleepEnd = woke
        let day = HistoryDayDisplay.make(date: yesterday, record: record)
        #expect(day.sleep.start == asleep)
        #expect(day.sleep.end == woke)
        #expect(day.sleep.end != asleep.addingTimeInterval(6 * 3_600))
    }

    @Test func todayRMSSDUsesOnlyTodayDatedReadings() {
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let stale = calendar.date(byAdding: .day, value: -1, to: now)!
        #expect(HistoryDayDisplay.rmssd(
            day: todayStart, dailyMedian: nil, latest: 55, latestMeasuredAt: stale, now: now
        ) == nil)
        #expect(HistoryDayDisplay.rmssd(
            day: todayStart, dailyMedian: nil, latest: 55, latestMeasuredAt: now, now: now
        ) == 55)
        #expect(HistoryDayDisplay.rmssd(
            day: todayStart, dailyMedian: 48, latest: 55, latestMeasuredAt: now, now: now
        ) == 48)
        // A past day never takes the live reading.
        #expect(HistoryDayDisplay.rmssd(
            day: calendar.startOfDay(for: stale), dailyMedian: nil, latest: 55,
            latestMeasuredAt: stale, now: now
        ) == nil)
    }

    @Test func dateBarNeverMovesIntoTheFuture() {
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        #expect(HistoryDateNavigation.shifted(todayStart, by: 1, now: now) == nil)
        #expect(!HistoryDateNavigation.canGoForward(todayStart, now: now))
        let back = HistoryDateNavigation.shifted(todayStart, by: -1, now: now)
        #expect(back == calendar.date(byAdding: .day, value: -1, to: todayStart))
        #expect(HistoryDateNavigation.canGoForward(back!, now: now))
        let future = calendar.date(byAdding: .day, value: 5, to: now)!
        #expect(HistoryDateNavigation.clamped(future, now: now) == todayStart)
    }

    @Test func statusFooterNeverInfersDenialFromMissingData() {
        let text = HistoryDataStatusText.text(authState: .granted, availability: .noReadableData)
        #expect(!text.contains("授权"))
        let denied = HistoryDataStatusText.text(authState: .denied, availability: .needsAuthorization)
        #expect(denied.contains("未获授权"))
    }

    @Test func activityWaterSilencesOnlyTheMissingColumn() {
        let intensities = HistoryActivityCard.dropIntensities(
            kcal: 400, exerciseMinutes: nil, standHours: nil,
            moveGoal: 0, exerciseGoal: 0, standGoal: 0
        )
        #expect(intensities.count == 3)
        #expect(intensities[0] > 0)
        #expect(intensities[1] == 0)
        #expect(intensities[2] == 0)
    }
}

import Foundation
import CoreGraphics
import HealthKit
import SwiftData
import Testing
@testable import Pibo

@MainActor
struct PiboWidgetSyncTests {
    private let petID = UUID()
    private let calendar = Calendar.current
    private var day: Date { calendar.startOfDay(for: .now) }
    private var noon: Date { day.addingTimeInterval(12 * 3600) }
    private var pixel: PiboCompanionPixelState {
        .init(level: 8, bodyStage: 2, leafStage: 3, accessoryMask: 7, form: 0,
              formStuck: false, balance: 4, wishes: [], finds: [], thought: false)
    }

    private func base() -> PiboWidgetSnapshot {
        var result = PetStateWidgetBridge.metadataSnapshot(
            petName: "Pibo", dayCount: 8, activityState: .stable, petID: petID, now: noon)
        result.pixel = pixel
        return result
    }

    private func update(_ metric: HealthActivityUpdate.Metric, _ amount: Double?, at: Date,
                        retaining previous: PiboWidgetSnapshot?, now: Date? = nil) -> PiboWidgetSnapshot? {
        PetStateWidgetBridge.activityUpdateSnapshot(
            .init(metric: metric, value: amount, dayStart: calendar.startOfDay(for: at), asOf: at),
            petName: "Pibo", dayCount: 8, activityState: .stable, petID: petID,
            retaining: previous, now: now ?? noon, calendar: calendar)
    }

    @Test func independentBackgroundMetricsMergeWithoutErasingAppearance() throws {
        let energy = try #require(update(.activeEnergy, 120, at: noon.addingTimeInterval(-10), retaining: base()))
        let exercise = try #require(update(.exerciseMinutes, 18, at: noon.addingTimeInterval(-20), retaining: energy))
        let duration = try #require(update(.standMinutes, 90, at: noon, retaining: exercise))
        let stand = try #require(update(.standHours, 11, at: noon, retaining: duration))
        #expect(stand.activeEnergy == 120)
        #expect(stand.exerciseMinutes == 18)
        #expect(stand.standMinutes == 90)
        #expect(stand.standHours == 11)
        #expect(stand.activityUpdatedAt == noon)
        #expect(stand.pixel == pixel)
        #expect(stand.petID == petID)
    }

    @Test func missingQuantityAndMeasuredZeroAreDifferent() throws {
        let first = try #require(update(.activeEnergy, 100, at: noon.addingTimeInterval(-10), retaining: base()))
        let missing = try #require(update(.activeEnergy, nil, at: noon, retaining: first))
        #expect(missing.activeEnergy == nil)
        #expect(missing.activeEnergyText == "--")
        #expect(missing.moveProgress == nil)
        let zero = try #require(update(.activeEnergy, 0, at: noon.addingTimeInterval(1), retaining: missing,
                                      now: noon.addingTimeInterval(1)))
        #expect(zero.activeEnergy == 0)
        #expect(zero.activeEnergyText == "0")
    }

    @Test func lateResponsesCannotRewindAnExplicitlyQueriedMetric() throws {
        let current = try #require(update(.activeEnergy, 150, at: noon, retaining: base()))
        #expect(update(.activeEnergy, 90, at: noon.addingTimeInterval(-60), retaining: current) == nil)
        let row = HealthDayRecord(date: day, activeEnergy: 90, updatedAt: noon.addingTimeInterval(30))
        row.activeEnergyObservedAt = noon.addingTimeInterval(-60)
        let merged = PetStateWidgetBridge.activitySnapshot(petName: "Pibo", dayCount: 8,
            activityState: .stable, record: row, retaining: current, petID: petID)
        #expect(merged.activeEnergy == 150)
        #expect(merged.activeEnergyUpdatedAt == noon)
    }

    @Test func unrelatedLegacyRowEditCannotResurrectUnavailableMetric() throws {
        let current = try #require(update(.activeEnergy, nil, at: noon, retaining: base()))
        let row = HealthDayRecord(date: day, activeEnergy: 90, updatedAt: noon.addingTimeInterval(60))
        let merged = PetStateWidgetBridge.activitySnapshot(petName: "Pibo", dayCount: 8,
            activityState: .stable, record: row, retaining: current, petID: petID)
        #expect(merged.activeEnergy == nil)
        #expect(merged.activeEnergyUpdatedAt == noon)
    }

    @Test func nextDayClearsYesterdayAndRejectsItsDelayedCallback() throws {
        var yesterday = base()
        let oldDay = try #require(calendar.date(byAdding: .day, value: -1, to: day))
        yesterday.activityDayStart = oldDay
        yesterday.activityUpdatedAt = oldDay.addingTimeInterval(20 * 3600)
        yesterday.activeEnergy = 300
        yesterday.exerciseMinutes = 20
        yesterday.moveGoal = 600
        yesterday.standHours = 11
        yesterday.standHoursUpdatedAt = yesterday.activityUpdatedAt
        let today = try #require(update(.standHours, 0, at: noon, retaining: yesterday))
        #expect(today.activeEnergy == nil)
        #expect(today.exerciseMinutes == nil)
        #expect(today.moveGoal == nil)
        #expect(today.standHours == 0)
        #expect(today.pixel == pixel)
        #expect(update(.activeEnergy, 500, at: oldDay.addingTimeInterval(23 * 3600), retaining: today) == nil)
    }

    @Test func identityChangeClearsPreviousPetsFactsEvenWhenNamesMatch() {
        var old = base()
        old.activeEnergy = 300
        let next = PetStateWidgetBridge.metadataSnapshot(petName: "Pibo", dayCount: 1,
            activityState: .dataUnknown, petID: UUID(), retaining: old, now: noon)
        #expect(next.pixel == nil)
        #expect(next.activeEnergy == nil)
        #expect(next.activityUpdatedAt == nil)
        let same = PetStateWidgetBridge.metadataSnapshot(petName: "New name", dayCount: 9,
            activityState: .stable, petID: petID, retaining: old, now: noon.addingTimeInterval(60))
        #expect(same.pixel == pixel)
        #expect(same.activeEnergy == 300)
        #expect(same.activityUpdatedAt == old.updatedAt)
    }

    @Test func timeZoneChangeAcceptsTheNewDayWindowAndRejectsOldZoneCallbacks() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(tokyo.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 10)))
        let oldBoundary = tokyo.startOfDay(for: now)
        let newBoundary = newYork.startOfDay(for: now)
        #expect(newBoundary < oldBoundary)
        var previous = base()
        previous.activityDayStart = oldBoundary
        previous.activeEnergy = 100
        previous.exerciseMinutes = 10
        previous.activeEnergyUpdatedAt = now.addingTimeInterval(-60)
        let incoming = HealthActivityUpdate(metric: .activeEnergy, value: 250,
                                           dayStart: newBoundary, asOf: now)
        let next = try #require(PetStateWidgetBridge.activityUpdateSnapshot(incoming,
            petName: "Pibo", dayCount: 8, activityState: .stable, petID: petID,
            retaining: previous, now: now, calendar: newYork))
        #expect(next.activityDayStart == newBoundary)
        #expect(next.activeEnergy == 250)
        #expect(next.exerciseMinutes == nil, "different daily windows must not be mixed")
        #expect(next.pixel == previous.pixel)
        let delayed = HealthActivityUpdate(metric: .exerciseMinutes, value: 20,
                                          dayStart: oldBoundary, asOf: now)
        #expect(PetStateWidgetBridge.activityUpdateSnapshot(delayed,
            petName: "Pibo", dayCount: 8, activityState: .stable, petID: petID,
            retaining: next, now: now, calendar: newYork) == nil)
    }

    @Test func knownGoalsNeverFabricateMissingFacts() {
        let row = HealthDayRecord(date: day, moveGoal: 600, exerciseGoal: 30, standGoal: 12)
        let value = PetStateWidgetBridge.activitySnapshot(petName: "Pibo", dayCount: 8,
            activityState: .stable, record: row)
        #expect(value.moveProgress == nil)
        #expect(value.exerciseProgress == nil)
        #expect(value.standProgress == nil)
    }

    @Test func invalidOrFutureLiveQuantityIsRejected() {
        #expect(update(.activeEnergy, .nan, at: noon, retaining: base()) == nil)
        #expect(update(.activeEnergy, -1, at: noon, retaining: base()) == nil)
        #expect(update(.exerciseMinutes, Double(Int.max), at: noon, retaining: base()) == nil)
        #expect(update(.standMinutes, .infinity, at: noon, retaining: base()) == nil)
        #expect(update(.standHours, .infinity, at: noon, retaining: base()) == nil)
        #expect(update(.standHours, 1.5, at: noon, retaining: base()) == nil)
        #expect(update(.activeEnergy, 5, at: noon.addingTimeInterval(60), retaining: base()) == nil)
    }

    @Test func reloadsTrackVisibleChangesRatherThanQuerySeconds() throws {
        let first = try #require(update(.activeEnergy, 100, at: noon, retaining: base()))
        let seconds = try #require(update(.activeEnergy, 100, at: noon.addingTimeInterval(10), retaining: first,
                                         now: noon.addingTimeInterval(10)))
        #expect(!seconds.needsReload(comparedTo: first))
        let minute = try #require(update(.activeEnergy, 100, at: noon.addingTimeInterval(60), retaining: seconds,
                                        now: noon.addingTimeInterval(60)))
        #expect(minute.needsReload(comparedTo: seconds))
        let changed = try #require(update(.activeEnergy, 101, at: noon.addingTimeInterval(10), retaining: first,
                                         now: noon.addingTimeInterval(10)))
        #expect(changed.needsReload(comparedTo: first))
    }

    @Test func timelineClearsDailyFactsAtLocalMidnightIncludingDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let now = start.addingTimeInterval(60)
        let midnight = try #require(PiboWidgetTimeline.dates(from: now, calendar: calendar).last)
        #expect(midnight.timeIntervalSince(start) == 23 * 3600)
        #expect(calendar.component(.hour, from: midnight) == 0)
        var stored = base()
        stored.activeEnergy = 100
        stored.activityDayStart = start
        stored.activityUpdatedAt = now
        let displayed = stored.activitySnapshotForDisplay(at: midnight, calendar: calendar)
        #expect(displayed.activeEnergy == nil)
        #expect(displayed.activityStatus(at: midnight, calendar: calendar) == "等待今日同步")
        #expect(displayed.pixel == stored.pixel)
        #expect(stored.activeEnergy == 100, "rendering must not mutate the stored payload")
    }

    @Test func storageRoundTripIsReadOnlyOnCorruptionAndFailsWithoutGroup() throws {
        let suite = "pibo.tests.widget-sync.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let value = base()
        #expect(PiboWidgetSnapshotStore.save(value, to: defaults))
        #expect(PiboWidgetSnapshotStore.load(from: defaults) == value)
        let corrupted = Data("invalid".utf8)
        defaults.set(corrupted, forKey: PiboWidgetConstants.snapshotKey)
        #expect(PiboWidgetSnapshotStore.load(from: defaults).activeEnergy == nil)
        #expect(defaults.data(forKey: PiboWidgetConstants.snapshotKey) == corrupted)
        #expect(!PiboWidgetSnapshotStore.save(value, to: nil))
        #expect(PiboWidgetSnapshotStore.load(from: nil).activeEnergy == nil)
    }

    @Test func numberFormattingHandlesUnknownZeroAndLargeValues() {
        var value = base()
        #expect(value.activeEnergyText == "--")
        #expect(value.exerciseMinutesText == "--")
        #expect(value.standHoursText == "--")
        value.activeEnergy = 0
        value.exerciseMinutes = 0
        value.standHours = 0
        #expect(value.activeEnergyText == "0")
        #expect(value.exerciseMinutesText == "0")
        #expect(value.standHoursText == "0")
        value.activeEnergy = Double.greatestFiniteMagnitude
        #expect(!value.activeEnergyText.isEmpty)
        value.activeEnergy = .infinity
        #expect(value.activeEnergyText == "--")
    }

    @Test func healthKitIdentifiersMapOnlyWidgetMetrics() {
        #expect(HealthActivityUpdate.metric(for: .activeEnergyBurned) == .activeEnergy)
        #expect(HealthActivityUpdate.metric(for: .appleExerciseTime) == .exerciseMinutes)
        #expect(HealthActivityUpdate.metric(for: .appleStandTime) == .standMinutes)
        #expect(HealthActivityUpdate.metric(for: .stepCount) == nil)
    }

    @Test func appleStandSummaryUsesCountUnitsIncludingZero() {
        let summary = HKActivitySummary()
        summary.appleStandHours = HKQuantity(unit: .count(), doubleValue: 11)
        summary.standHoursGoal = HKQuantity(unit: .count(), doubleValue: 12)
        let value = HealthDataService.DayActivitySummary(summary)
        #expect(value.standHours == 11)
        #expect(value.standGoal == 12)
        summary.appleStandHours = HKQuantity(unit: .count(), doubleValue: 0)
        #expect(HealthDataService.DayActivitySummary(summary).standHours == 0)
    }

    @Test func standingDurationCannotReplaceTheRingCountOrItsProgress() throws {
        var previous = base()
        previous.activityDayStart = day
        previous.standGoal = 12
        let ring = try #require(update(.standHours, 11, at: noon, retaining: previous))
        let progress = try #require(ring.standProgress)
        let duration = try #require(update(.standMinutes, 90, at: noon.addingTimeInterval(10), retaining: ring,
                                          now: noon.addingTimeInterval(10)))
        #expect(duration.standHoursText == "11")
        #expect(duration.standHoursUpdatedAt == noon)
        #expect(duration.standProgress == progress)

        let missing = try #require(update(.standHours, nil, at: noon.addingTimeInterval(20), retaining: duration,
                                         now: noon.addingTimeInterval(20)))
        #expect(missing.standMinutes == 90)
        #expect(missing.standHoursText == "--")
        #expect(missing.standProgress == nil)
        #expect(update(.standHours, 10, at: noon.addingTimeInterval(-1), retaining: missing) == nil)

        let row = HealthDayRecord(date: day, standMinutes: 90, updatedAt: noon.addingTimeInterval(60))
        row.standHours = 11
        row.standHoursObservedAt = noon
        let merged = PetStateWidgetBridge.activitySnapshot(petName: "Pibo", dayCount: 8,
            activityState: .stable, record: row, retaining: missing, petID: petID)
        #expect(merged.standHours == nil, "an older history summary must not resurrect an unavailable live count")
    }

    @Test func liveStandSummaryCarriesItsActualGoal() throws {
        let value = try #require(PetStateWidgetBridge.activityUpdateSnapshot(
            .init(metric: .standHours, value: 11, dayStart: day, asOf: noon, goal: 12),
            petName: "Pibo", dayCount: 8, activityState: .stable, petID: petID,
            retaining: base(), now: noon))
        #expect(value.standHours == 11)
        #expect(value.standGoal == 12)
        #expect(value.standProgress != nil)
    }

    @Test func legacyWidgetCacheDiscardsConvertedHoursButKeepsRealFacts() throws {
        let suite = "pibo.tests.widget-stand-migration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = base()
        legacy.activeEnergy = 120
        legacy.standMinutes = 90
        legacy.standHours = 1
        legacy.standProgress = 1.5 / 12
        #expect(PiboWidgetSnapshotStore.save(legacy, to: defaults))
        let migrated = PiboWidgetSnapshotStore.load(from: defaults)
        #expect(migrated.standHours == nil)
        #expect(migrated.standProgress == nil)
        #expect(migrated.standMinutes == 90)
        #expect(migrated.activeEnergy == 120)
        #expect(migrated.pixel == pixel)
        let corrected = try #require(update(.standHours, 11, at: noon, retaining: migrated))
        #expect(PiboWidgetSnapshotStore.save(corrected, to: defaults))
        #expect(PiboWidgetSnapshotStore.load(from: defaults).standHours == 11)
    }

    @Test func widgetRendersPersistedGrowthAndFormRatherThanDefaultCharacter() throws {
        var value = base()
        let fallback = try #require(PiboPixelCompanionArt.image(look: .init(stateID: value.stateTag), reduceMotion: true))
        let grown = try #require(PiboPixelCompanionArt.image(look: value.pixelLook, reduceMotion: true))
        let originalBytes = try #require(fallback.dataProvider?.data) as Data
        let grownBytes = try #require(grown.dataProvider?.data) as Data
        #expect(grownBytes != originalBytes)
        value.pixel?.form = 1
        let transformed = try #require(PiboPixelCompanionArt.image(look: value.pixelLook, reduceMotion: true))
        let transformedBytes = try #require(transformed.dataProvider?.data) as Data
        #expect(transformedBytes != grownBytes)
    }

    @Test func historyKeepsPerMetricAcquisitionTimesWhenQueriesFinishOutOfOrder() throws {
        let container = try ModelContainer(for: HealthDayRecord.self, WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let suite = "pibo.tests.widget-history.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HealthHistoryStore(context: container.mainContext, provenanceDefaults: defaults,
            syntheticDaysKey: "synthetic-days", syntheticWorkoutIDsKey: "synthetic-workouts")
        store.ingest([HealthDayValues(date: day, activityObservedAt: noon, activeEnergy: 300,
                                      activeEnergyRecorded: true)])
        store.ingest([HealthDayValues(date: day, activityObservedAt: noon.addingTimeInterval(-60),
                                      activeEnergy: 100, exerciseMinutes: 10,
                                      activeEnergyRecorded: true, exerciseRecorded: true)])
        let row = try #require(store.record(on: day))
        #expect(row.activeEnergy == 300)
        #expect(row.activeEnergyObservedAt == noon)
        #expect(row.exerciseMinutes == 10)
        #expect(row.exerciseObservedAt == noon.addingTimeInterval(-60))
        store.ingest([HealthDayValues(date: day, sleepTotal: 7 * 3600)])
        #expect(row.activeEnergyObservedAt == noon)
        #expect(row.exerciseObservedAt == noon.addingTimeInterval(-60))
        // A newer provider correction is allowed to reduce the total.
        store.ingest([HealthDayValues(date: day, activityObservedAt: noon.addingTimeInterval(60),
                                      activeEnergy: 250, activeEnergyRecorded: true)])
        #expect(row.activeEnergy == 250)
    }
}

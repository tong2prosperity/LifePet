import Foundation
import PiboCore
import SwiftData
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct PiboCoreWellnessIntegrationTests {
    @Test func missingPlatformInputsRemainMissing() {
        let day = Calendar.current.startOfDay(for: .now)
        let record = HealthDayRecord(date: day)
        record.sleepTotal = 8 * 3_600
        record.sleepStart = day.addingTimeInterval(-8 * 3_600)
        record.sleepEnd = day

        let report = PiboCoreWellnessAdapter.report(current: record, history: [])

        #expect(report.sleep.score != nil)
        #expect(report.activity.score == nil)
        #expect(report.recovery.hrvScore == nil)
        #expect(report.recovery.heartRateScore == nil)
        #expect(report.recovery.temperatureScore == nil)
        #expect(report.recovery.trainingScore == nil)
    }

    @Test func instrumentDoesNotPresentUnobservedTrainingLoadsAsZero() throws {
        let day = Calendar.current.startOfDay(for: .now)
        let record = HealthDayRecord(date: day)
        let report = PiboCoreWellnessAdapter.report(current: record, history: [])
        let snapshot = DailyWellnessSnapshot(report: report, generatedAt: .now)

        #expect(snapshot.acuteTrainingObservedDays == 0)
        #expect(snapshot.chronicTrainingObservedDays == 0)

        record.wellnessPayload = try JSONEncoder().encode(snapshot)
        let presentation = WellnessInstrumentData(record: record)
        #expect(presentation.acuteTrainingLoad == nil)
        #expect(presentation.chronicTrainingLoad == nil)
        #expect(presentation.trainingBalanceStatus == nil)

        let persistedPayload = try #require(record.wellnessPayload)
        var legacyObject = try #require(
            JSONSerialization.jsonObject(with: persistedPayload) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "acuteTrainingObservedDays")
        legacyObject.removeValue(forKey: "chronicTrainingObservedDays")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacySnapshot = try JSONDecoder().decode(DailyWellnessSnapshot.self, from: legacyData)
        #expect(legacySnapshot.acuteTrainingObservedDays == nil)
        #expect(legacySnapshot.chronicTrainingObservedDays == nil)
    }

    @Test func workoutLoadPrefersAppleEffortAndPersistsRawEvidence() throws {
        let day = Calendar.current.startOfDay(for: .now)
        let start = day.addingTimeInterval(7 * 3_600)
        let workout = WorkoutValues(
            id: UUID(),
            kind: .run,
            start: start,
            end: start.addingTimeInterval(3_600),
            duration: 3_600,
            energyKcal: 600,
            distanceMeters: 10_000,
            averageHeartRate: 150,
            minimumHeartRate: 90,
            maximumHeartRate: 190,
            effortScore: 8,
            effortIsEstimated: false
        )
        let result = try #require(PiboCoreWellnessAdapter.trainingLoad(
            workout: workout,
            restingHeartRate: 60
        ))
        #expect(result.source == .effort)

        let container = try ModelContainer(
            for: HealthDayRecord.self, WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let suite = "PiboCoreWellnessIntegrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = HealthHistoryStore(
            context: container.mainContext,
            provenanceDefaults: defaults,
            syntheticDaysKey: "test.synthetic-days",
            syntheticWorkoutIDsKey: "test.synthetic-workouts"
        )
        history.ingest([HealthDayValues(date: day, restingHR: 60)])
        history.ingestWorkouts([workout])

        let stored = try #require(history.workouts(on: day).first)
        #expect(stored.averageHeartRate == 150)
        #expect(stored.maximumHeartRate == 190)
        #expect(stored.effortScore == 8)
        #expect(stored.effortIsEstimated == false)
        #expect(stored.trainingLoad == result.load)
        #expect(history.record(on: day)?.trainingLoad == result.load)
    }

    @Test func verifiedHistoryProducesVersionedSnapshotsButSyntheticHistoryDoesNot() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let container = try ModelContainer(
            for: HealthDayRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let suite = "PiboCoreWellnessHistory.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = HealthHistoryStore(
            context: container.mainContext,
            provenanceDefaults: defaults,
            syntheticDaysKey: "test.synthetic-days",
            syntheticWorkoutIDsKey: "test.synthetic-workouts"
        )

        let syntheticDay = try #require(cal.date(byAdding: .day, value: -9, to: today))
        history.upsert(day: syntheticDay, origin: .synthetic) {
            $0.sleepTotal = 8 * 3_600
            $0.steps = 12_000
            $0.wellnessPayload = Data([0x01])
        }

        for offset in stride(from: -7, through: 0, by: 1) {
            let day = try #require(cal.date(byAdding: .day, value: offset, to: today))
            let sleepStart = day.addingTimeInterval(-8 * 3_600)
            history.ingest([HealthDayValues(
                date: day,
                steps: 8_000,
                exerciseMinutes: 30,
                standMinutes: 600,
                restingHR: 58,
                hrv: 45,
                sleepTotal: 8 * 3_600,
                sleepDeep: 90 * 60,
                sleepREM: 100 * 60,
                sleepStart: sleepStart,
                sleepEnd: day,
                mindfulMinutes: 10
            )])
        }

        history.recomputeWellness(now: today.addingTimeInterval(12 * 3_600))

        #expect(history.record(on: syntheticDay)?.wellnessPayload == nil)
        let snapshot = try #require(history.record(on: today)?.wellnessSnapshot)
        #expect(snapshot.algorithmVersion == PiboCoreWellness.algorithmVersion)
        #expect(snapshot.sleepScore != nil)
        #expect(snapshot.activityScore != nil)
        #expect(snapshot.restorativeMinutes == 10)
        #expect(snapshot.resilienceScore != nil)
        #expect(snapshot.resilienceObservedDays == 8)

        let encoded = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(DailyWellnessSnapshot.self, from: encoded) == snapshot)
    }
}

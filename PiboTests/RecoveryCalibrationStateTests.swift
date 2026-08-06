import Foundation
import SwiftData
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct RecoveryCalibrationStateTests {
    @Test func onlyVerifiedRawInputsAdvanceRecoveryCalibration() throws {
        let container = try ModelContainer(
            for: HealthDayRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let suite = "RecoveryCalibrationStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = HealthHistoryStore(
            context: container.mainContext,
            provenanceDefaults: defaults,
            syntheticDaysKey: "test.synthetic-days",
            syntheticWorkoutIDsKey: "test.synthetic-workouts"
        )
        let today = Calendar.current.startOfDay(for: .now)

        let projectionOnly = HealthDayRecord(date: today)
        projectionOnly.wellnessPayload = Data([0x01, 0x02])
        projectionOnly.recoveryIndexScore = 88
        container.mainContext.insert(projectionOnly)
        try container.mainContext.save()
        #expect(history.recoveryCalibrationState(now: today) == .waitingForData)

        history.ingest([HealthDayValues(date: today, hrv: 42)])
        #expect(history.recoveryCalibrationState(now: today) == .calibrating)
    }

    @Test func syntheticHealthNeverCountsAsRecoveryEvidence() throws {
        let container = try ModelContainer(
            for: HealthDayRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let suite = "RecoveryCalibrationSynthetic.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = HealthHistoryStore(
            context: container.mainContext,
            provenanceDefaults: defaults,
            syntheticDaysKey: "test.synthetic-days",
            syntheticWorkoutIDsKey: "test.synthetic-workouts"
        )
        let today = Calendar.current.startOfDay(for: .now)
        history.upsert(day: today, origin: .synthetic) {
            $0.sleepTotal = 8 * 3_600
            $0.hrv = 50
        }

        #expect(history.recoveryCalibrationState(now: today) == .waitingForData)
    }
}

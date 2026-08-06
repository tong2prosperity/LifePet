import Foundation

/// The recovery algorithm is not a shipped product contract yet. This state
/// reports only whether any verified raw inputs have arrived; it never exposes
/// or derives a score from wellness, pressure, or resilience projections.
enum RecoveryCalibrationState: Equatable, Sendable {
    case waitingForData
    case calibrating
}

extension HealthHistoryStore {
    func recoveryCalibrationState(now: Date = .now) -> RecoveryCalibrationState {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let hasRawInput = verifiedHealthRecords(from: start, to: today).contains { record in
            record.sleepTotal > 0
                || record.hrv > 0
                || record.overnightHRV != nil
                || record.restingHR > 0
                || record.sleepingHeartRateAverage != nil
                || record.workoutCount > 0
                || record.workoutMinutes > 0
        }
        return hasRawInput ? .calibrating : .waitingForData
    }
}

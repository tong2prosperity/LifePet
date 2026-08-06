import Foundation
import SwiftData

/// One completed workout (`HKWorkout`), persisted for the 运动记录 card on the
/// 历史数据页. Keyed by the HK sample UUID so re-backfills upsert in place
/// instead of duplicating the same run.
///
/// The live "today snapshot" pipeline only knows the *latest* workout
/// (`PetStateStore.pendingWorkout`); the per-day list the card renders needs the
/// full set, so these rows are backfilled by `HealthDataService.fetchWorkoutHistory`
/// (today included) and read back per day via `HealthHistoryStore`.
@Model
final class WorkoutRecord {
    /// `HKWorkout.uuid` — the upsert key.
    @Attribute(.unique) var id: UUID
    /// `startOfDay(of: start)` — the day-bucket query key.
    var day: Date
    /// `HealthEvent.WorkoutKind.rawValue`.
    var kindRaw: String
    var start: Date
    var end: Date
    var duration: TimeInterval        // seconds
    var energyKcal: Double
    var distanceMeters: Double         // walking + running, 0 when unavailable
    var averageHeartRate: Double?
    var minimumHeartRate: Double?
    var maximumHeartRate: Double?
    /// Apple Workout Effort, 1...10. `effortIsEstimated` keeps the provider's
    /// measured/estimated distinction while Core uses the same numeric input.
    var effortScore: Double?
    var effortIsEstimated = false
    var trainingLoad: Double?
    var updatedAt: Date

    init(id: UUID, day: Date, kindRaw: String, start: Date, end: Date,
         duration: TimeInterval, energyKcal: Double, distanceMeters: Double,
         updatedAt: Date = .now) {
        self.id = id
        self.day = day
        self.kindRaw = kindRaw
        self.start = start
        self.end = end
        self.duration = duration
        self.energyKcal = energyKcal
        self.distanceMeters = distanceMeters
        self.averageHeartRate = nil
        self.minimumHeartRate = nil
        self.maximumHeartRate = nil
        self.effortScore = nil
        self.effortIsEstimated = false
        self.trainingLoad = nil
        self.updatedAt = updatedAt
    }
}

extension WorkoutRecord {
    var kind: HealthEvent.WorkoutKind { HealthEvent.WorkoutKind(rawValue: kindRaw) ?? .other }
    var durationMinutes: Int {
        PiboCoreWorkoutAdapter.metrics(
            durationSeconds: duration,
            distanceMeters: distanceMeters
        ).durationMinutes
    }

    /// 平均配速 in minutes-per-kilometer. `nil` when there's no usable distance
    /// (strength / yoga / mindful sessions) — the card hides the column then.
    var paceMinPerKm: Double? {
        PiboCoreWorkoutAdapter.metrics(
            durationSeconds: duration,
            distanceMeters: distanceMeters
        ).paceMinutesPerKilometer
    }

    /// `07:00-07:52` time-range label (24h, locale-stable).
    var timeRangeText: String {
        let f = WorkoutRecord.rangeFormatter
        return "\(f.string(from: start))-\(f.string(from: end))"
    }

    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}

/// Sendable transport produced by the off-actor HK workout fetch and ingested
/// into `WorkoutRecord` on the main actor (mirrors `HealthDayValues`).
struct WorkoutValues: Sendable {
    var id: UUID
    var kind: HealthEvent.WorkoutKind
    var start: Date
    var end: Date
    var duration: TimeInterval
    var energyKcal: Double
    var distanceMeters: Double
    var averageHeartRate: Double? = nil
    var minimumHeartRate: Double? = nil
    var maximumHeartRate: Double? = nil
    var effortScore: Double? = nil
    var effortIsEstimated = false
    var trainingLoad: Double? = nil
}

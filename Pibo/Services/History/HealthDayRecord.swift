import Foundation
import SwiftData

/// Sleep stage of one night segment, persisted raw so the codable layout stays
/// stable across refactors. Display mapping: 眼动 = rem, 浅睡 = core (incl. HK
/// "unspecified"), 深睡 = deep.
enum SleepStage: Int, Codable, Sendable {
    case awake = 0
    case rem = 1
    case core = 2
    case deep = 3
}

/// One contiguous sleep segment of a night (HK `sleepAnalysis` samples, adjacent
/// same-stage samples merged). Feeds the 睡眠 card's cloud illustration: x = time
/// within the night, y = stage band, cloud size = duration.
struct SleepSegmentValue: Codable, Sendable, Equatable {
    var start: Date
    var end: Date
    var stageRaw: Int

    init(start: Date, end: Date, stage: SleepStage) {
        self.start = start
        self.end = end
        self.stageRaw = stage.rawValue
    }

    var stage: SleepStage { SleepStage(rawValue: stageRaw) ?? .core }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// One day's **complete** HealthKit-readable snapshot, persisted in-app via
/// SwiftData. One row per day (`date` = `startOfDay`, unique).
///
/// Storage policy (per product direction 2026-06-09): persist the *full* set of
/// metrics we can read from HealthKit — not just what any one screen shows — so
/// the 上滑数据二楼 (and future views) can render history offline without
/// re-querying HK. The UI then reads only the subset it displays (see the
/// `displayed-subset` computed helpers + `PiboHistoryView`).
///
/// Today's row is kept in sync from the live `RawMetrics` on every reconcile;
/// past rows are backfilled once by `HealthHistoryFetcher` (daily-bucketed HK
/// statistics) and thereafter only re-touched if HK reports edits.
@Model
final class HealthDayRecord {
    /// `Calendar.current.startOfDay(for:)` — the unique key for the day.
    @Attribute(.unique) var date: Date

    // — Activity (cumulative for the day) —
    var steps: Int
    /// Per-hour step counts (index = hour 0–23, local calendar). Empty for rows
    /// written before this field existed; the 今日脚步 grass falls back to the
    /// day-total pattern then.
    var hourlySteps: [Int] = []
    var activeEnergy: Double          // kcal
    var exerciseMinutes: Int
    var standMinutes: Int
    var distanceMeters: Double        // walking + running
    var flightsClimbed: Int
    /// Apple Activity ring goals for the day (`HKActivitySummary`). 0 = unknown /
    /// unset → the 活动 card falls back to a sensible default. Move = kcal,
    /// exercise = min, stand = hours.
    var moveGoal: Double = 0
    var exerciseGoal: Int = 0
    var standGoal: Int = 0

    // — Heart —
    var restingHR: Double             // bpm
    var heartRateAvg: Double          // bpm, daily average
    var heartRateMin: Double
    var heartRateMax: Double
    var hrv: Double                   // SDNN ms, daily average
    var oxygenSaturation: Double      // SpO2 fraction 0–1, daily average

    // — Sleep (last night, attributed to this wake-day) —
    var sleepTotal: TimeInterval
    var sleepDeep: TimeInterval
    var sleepREM: TimeInterval
    var sleepCore: TimeInterval
    var sleepAwake: TimeInterval
    var sleepStart: Date?
    var sleepEnd: Date?
    /// The night's stage segments in time order (adjacent same-stage merged).
    /// Empty for rows written before this field existed; the 睡眠 card falls
    /// back to total-derived clouds then.
    var sleepSegments: [SleepSegmentValue] = []

    // — Mind / workouts —
    var mindfulMinutes: Int
    var workoutCount: Int
    var workoutMinutes: Int
    var workoutEnergy: Double         // kcal

    /// Wall-clock of the most recent write.
    var updatedAt: Date

    init(date: Date,
         steps: Int = 0, hourlySteps: [Int] = [], activeEnergy: Double = 0, exerciseMinutes: Int = 0,
         standMinutes: Int = 0, distanceMeters: Double = 0, flightsClimbed: Int = 0,
         moveGoal: Double = 0, exerciseGoal: Int = 0, standGoal: Int = 0,
         restingHR: Double = 0, heartRateAvg: Double = 0, heartRateMin: Double = 0,
         heartRateMax: Double = 0, hrv: Double = 0, oxygenSaturation: Double = 0,
         sleepTotal: TimeInterval = 0, sleepDeep: TimeInterval = 0, sleepREM: TimeInterval = 0,
         sleepCore: TimeInterval = 0, sleepAwake: TimeInterval = 0,
         sleepStart: Date? = nil, sleepEnd: Date? = nil, sleepSegments: [SleepSegmentValue] = [],
         mindfulMinutes: Int = 0, workoutCount: Int = 0, workoutMinutes: Int = 0,
         workoutEnergy: Double = 0, updatedAt: Date = .distantPast) {
        self.date = date
        self.steps = steps
        self.hourlySteps = hourlySteps
        self.sleepSegments = sleepSegments
        self.activeEnergy = activeEnergy
        self.exerciseMinutes = exerciseMinutes
        self.standMinutes = standMinutes
        self.distanceMeters = distanceMeters
        self.flightsClimbed = flightsClimbed
        self.moveGoal = moveGoal
        self.exerciseGoal = exerciseGoal
        self.standGoal = standGoal
        self.restingHR = restingHR
        self.heartRateAvg = heartRateAvg
        self.heartRateMin = heartRateMin
        self.heartRateMax = heartRateMax
        self.hrv = hrv
        self.oxygenSaturation = oxygenSaturation
        self.sleepTotal = sleepTotal
        self.sleepDeep = sleepDeep
        self.sleepREM = sleepREM
        self.sleepCore = sleepCore
        self.sleepAwake = sleepAwake
        self.sleepStart = sleepStart
        self.sleepEnd = sleepEnd
        self.mindfulMinutes = mindfulMinutes
        self.workoutCount = workoutCount
        self.workoutMinutes = workoutMinutes
        self.workoutEnergy = workoutEnergy
        self.updatedAt = updatedAt
    }
}

// MARK: - Displayed subset (what the 二楼 actually renders)

extension HealthDayRecord {
    /// Has any signal worth showing (filters all-zero placeholder days).
    var hasData: Bool {
        steps > 0 || sleepTotal > 0 || activeEnergy > 0 || exerciseMinutes > 0
    }

    /// 深睡 share, 0–100. 0 when no sleep recorded.
    var deepSleepPercent: Int {
        sleepTotal > 0 ? Int((sleepDeep / sleepTotal) * 100) : 0
    }

    /// 今日能量 0–5 — derived from sleep + movement (proxy until the real model).
    var energyScore: Int {
        var s = 0
        if steps >= 8000 { s += 2 } else if steps >= 4000 { s += 1 }
        if sleepTotal >= 7 * 3600 { s += 2 } else if sleepTotal >= 6 * 3600 { s += 1 }
        if exerciseMinutes >= 30 { s += 1 }
        return min(5, s)
    }

    /// Heat-map intensity 0–4 from the day's step count.
    var activityLevel: Int {
        switch steps {
        case 0:        return 0
        case ..<3000:  return 1
        case ..<6000:  return 2
        case ..<10000: return 3
        default:       return 4
        }
    }
}

import Foundation

/// Plain transport of one day's HealthKit values (Sendable) — produced by
/// `HealthHistoryFetcher` off the main actor, ingested into SwiftData here.
struct HealthDayValues: Sendable {
    var date: Date
    var steps = 0
    var hourlySteps: [Int] = []
    var activeEnergy = 0.0
    var exerciseMinutes = 0
    var standMinutes = 0
    var distanceMeters = 0.0
    var flightsClimbed = 0
    var moveGoal = 0.0          // Apple Move ring goal, kcal (0 = unknown)
    var exerciseGoal = 0        // Exercise ring goal, min
    var standGoal = 0           // Stand ring goal, hours
    /// Set only when HealthKit returned a statistic for the metric on this day
    /// (a real 0 included). `nil` keeps the pre-flag meaning: positive values
    /// are treated as recorded, zeros are not.
    var stepsRecorded: Bool?
    var activeEnergyRecorded: Bool?
    var exerciseRecorded: Bool?
    var standRecorded: Bool?
    var restingHR = 0.0
    var heartRateAvg = 0.0
    var heartRateMin = 0.0
    var heartRateMax = 0.0
    var hrv = 0.0
    var oxygenSaturation = 0.0
    var sleepTotal: TimeInterval = 0
    var sleepDeep: TimeInterval = 0
    var sleepREM: TimeInterval = 0
    var sleepCore: TimeInterval = 0
    var sleepAwake: TimeInterval = 0
    var sleepStart: Date?
    var sleepEnd: Date?
    var sleepInBed: TimeInterval?
    var sleepAwakeningCount: Int?
    var sleepLatency: TimeInterval?
    var sleepSegments: [SleepSegmentValue] = []
    var overnightHRV: Double?
    var sleepingHeartRateAverage: Double?
    var sleepingHeartRateMinimum: Double?
    var sleepingWristTemperature: Double?
    var sleepingRespiratoryRate: Double?
    var sleepingOxygenSaturation: Double?
    var sleepingBreathingDisturbances: Double?
    var vo2Max: Double?
    var recoveryIndexScore: Double?
    var mindfulMinutes = 0
    var workoutCount = 0
    var workoutMinutes = 0
    var workoutEnergy = 0.0

    var stepsArrived: Bool { stepsRecorded ?? (steps > 0) }
    var activeEnergyArrived: Bool { activeEnergyRecorded ?? (activeEnergy > 0) }
    var exerciseArrived: Bool { exerciseRecorded ?? (exerciseMinutes > 0) }
    var standArrived: Bool { standRecorded ?? (standMinutes > 0) }

    /// An empty HealthKit response must never create an all-zero day. A first
    /// real 0 (flagged) is still evidence and does persist.
    var hasPersistableData: Bool {
        stepsArrived || activeEnergyArrived || exerciseArrived || standArrived
            || hourlySteps.count == 24
            || steps > 0 || activeEnergy > 0 || exerciseMinutes > 0 || standMinutes > 0
            || distanceMeters > 0 || flightsClimbed > 0 || moveGoal > 0
            || exerciseGoal > 0 || standGoal > 0 || restingHR > 0
            || heartRateAvg > 0 || heartRateMin > 0 || heartRateMax > 0
            || hrv > 0 || oxygenSaturation > 0 || sleepTotal > 0
            || sleepInBed != nil || overnightHRV != nil
            || sleepingHeartRateAverage != nil || sleepingWristTemperature != nil
            || sleepingRespiratoryRate != nil || sleepingOxygenSaturation != nil
            || sleepingBreathingDisturbances != nil || vo2Max != nil
            || mindfulMinutes > 0 || workoutCount > 0 || workoutMinutes > 0
            || workoutEnergy > 0
    }
}

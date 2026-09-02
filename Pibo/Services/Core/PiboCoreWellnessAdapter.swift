import Foundation
import PiboCore

/// Platform-model translation only. All windows, weights, thresholds and
/// missing-data policy remain in `pibo-core`.
enum PiboCoreWellnessAdapter {
    struct ResilienceDay: Sendable {
        let daysBeforeCurrent: Int
        let recoveryScore: Double?
        let stressScore: Double?
        let restorativeMinutes: Double?
    }

    static func observation(
        for record: HealthDayRecord,
        relativeTo currentDay: Date,
        calendar: Calendar = .current
    ) -> PiboCoreWellnessDailyObservation {
        let hrv = measured(record.overnightHRV) ?? measured(record.hrv)
        let inBed = record.sleepInBed.map { $0 / 60 }
            ?? (record.sleepAwake > 0 ? (record.sleepTotal + record.sleepAwake) / 60 : nil)
        let awakenings = record.sleepAwakeningCount ?? measuredAwakenings(record.sleepSegments)
        return PiboCoreWellnessDailyObservation(
            daysBeforeCurrent: calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: record.date),
                to: calendar.startOfDay(for: currentDay)
            ).day ?? 0,
            sleepMinutes: measured(record.sleepTotal).map { $0 / 60 },
            timeInBedMinutes: inBed,
            sleepOnsetLocalMinute: record.sleepStart.map { minuteOfDay($0, calendar: calendar) },
            wakeLocalMinute: record.sleepEnd.map { minuteOfDay($0, calendar: calendar) },
            awakenings: awakenings,
            deepSleepMinutes: measured(record.sleepTotal).map { _ in record.sleepDeep / 60 },
            remSleepMinutes: measured(record.sleepTotal).map { _ in record.sleepREM / 60 },
            napMinutes: nil,
            hrvMilliseconds: hrv,
            hrvKind: hrv == nil ? .unknown : .sdnn,
            restingHeartRateBPM: measured(record.restingHR),
            sleepingHeartRateBPM: measured(record.sleepingHeartRateAverage),
            skinTemperatureCelsius: measured(record.sleepingWristTemperature),
            steps: measured(record.steps).map(Double.init),
            activeMinutes: measured(record.exerciseMinutes).map(Double.init),
            activeHours: measured(record.standMinutes).map { Double($0) / 60 },
            trainingLoad: record.trainingLoad
        )
    }

    static func report(
        current: HealthDayRecord,
        history: [HealthDayRecord],
        calendar: Calendar = .current
    ) -> PiboCoreWellnessReport {
        PiboCoreWellness.report(
            current: observation(for: current, relativeTo: current.date, calendar: calendar),
            history: history.map {
                observation(for: $0, relativeTo: current.date, calendar: calendar)
            }
        )
    }

    static func readiness(
        current: HealthDayRecord,
        history: [HealthDayRecord],
        calendar: Calendar = .current
    ) -> PiboCoreWellnessReadinessResult {
        PiboCoreWellness.readiness(
            current: observation(for: current, relativeTo: current.date, calendar: calendar),
            history: history.map {
                observation(for: $0, relativeTo: current.date, calendar: calendar)
            }
        )
    }

    static func trainingLoad(
        workout: WorkoutValues,
        restingHeartRate: Double?
    ) -> PiboCoreWellnessTrainingSessionResult? {
        PiboCoreWellness.trainingSessionLoad(PiboCoreWellnessTrainingSessionInput(
            durationMinutes: workout.duration / 60,
            effortScore: workout.effortScore,
            averageHeartRateBPM: workout.averageHeartRate,
            maximumHeartRateBPM: workout.maximumHeartRate,
            restingHeartRateBPM: measured(restingHeartRate),
            activeEnergyKilocalories: workout.energyKcal > 0 ? workout.energyKcal : nil
        ))
    }

    static func recoveryIndex(
        heartRates: [(date: Date, value: Double)],
        sleepStart: Date,
        sleepDuration: TimeInterval
    ) -> PiboCoreWellnessRecoveryIndexResult? {
        PiboCoreWellness.recoveryIndex(
            samples: heartRates.map {
                PiboCoreWellnessNocturnalHeartRateSample(
                    minutesSinceSleepOnset: $0.date.timeIntervalSince(sleepStart) / 60,
                    beatsPerMinute: $0.value
                )
            },
            sleepDurationMinutes: sleepDuration / 60
        )
    }

    /// The first iOS acquisition path only classifies explicit HealthKit
    /// mindfulness sessions. Core still owns the restorative classification;
    /// ordinary inactivity is never assumed to be restorative.
    static func restorativeTime(
        mindfulMinutes: Int
    ) -> PiboCoreWellnessRestorativeTimeResult? {
        guard mindfulMinutes > 0 else { return nil }
        return PiboCoreWellness.restorativeTime(intervals: [
            PiboCoreWellnessRestorativeInterval(
                durationMinutes: Double(mindfulMinutes),
                isMoving: false,
                isMindful: true
            ),
        ])
    }

    static func resilience(
        days: [ResilienceDay]
    ) -> PiboCoreWellnessResilienceResult? {
        PiboCoreWellness.resilience(days: days.map {
            PiboCoreWellnessResilienceDay(
                daysBeforeCurrent: $0.daysBeforeCurrent,
                recoveryScore: $0.recoveryScore,
                stressScore: $0.stressScore,
                restorativeMinutes: $0.restorativeMinutes
            )
        })
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Double {
        let values = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double((values.hour ?? 0) * 60 + (values.minute ?? 0))
            + Double(values.second ?? 0) / 60
    }

    private static func measured(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func measured(_ value: Int) -> Int? {
        value > 0 ? value : nil
    }

    private static func measuredAwakenings(_ segments: [SleepSegmentValue]) -> Int? {
        guard !segments.isEmpty else { return nil }
        return segments.lazy.filter { $0.stage == .awake }.count
    }
}

import Foundation
import HealthKit
import os

/// Daily-bucketed historical backfill for the 上滑数据二楼. Separate from the
/// live "today snapshot" pipeline: this runs once (and on reconcile) to fill the
/// SwiftData `HealthDayRecord` history with the last N days of HK data.
///
/// Cumulative metrics use one `HKStatisticsCollectionQuery` each (1-day buckets);
/// heart metrics use discrete-average/min/max; sleep is bucketed per night and
/// attributed to its wake-day. Distance/flights live in the model schema but are
/// not yet in the auth set, so they stay 0 until added to `HealthMetric`.
extension HealthDataService {

    /// Read the last `days` days of HK data as one row per day. Off-MainActor work
    /// is the HK queries themselves; the returned values are plain `Sendable`.
    func fetchDailyHistory(days: Int = 35) async -> [HealthDayValues] {
        guard authState == .granted, HKHealthStore.isHealthDataAvailable() else { return [] }
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -days, to: today) else { return [] }

        var byDay: [Date: HealthDayValues] = [:]
        func mutate(_ day: Date, _ f: (inout HealthDayValues) -> Void) {
            let k = cal.startOfDay(for: day)
            var v = byDay[k] ?? HealthDayValues(date: k)
            f(&v)
            byDay[k] = v
        }

        await collectSum(.stepCount, unit: .count(), start: start, anchor: today) { d, v in mutate(d) { $0.steps = Int(v) } }
        await collectSum(.activeEnergyBurned, unit: .kilocalorie(), start: start, anchor: today) { d, v in mutate(d) { $0.activeEnergy = v } }
        await collectSum(.appleExerciseTime, unit: .minute(), start: start, anchor: today) { d, v in mutate(d) { $0.exerciseMinutes = Int(v) } }
        await collectSum(.appleStandTime, unit: .minute(), start: start, anchor: today) { d, v in mutate(d) { $0.standMinutes = Int(v) } }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        await collectAvg(.restingHeartRate, unit: bpm, start: start, anchor: today) { d, v in mutate(d) { $0.restingHR = v } }
        await collectAvg(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: start, anchor: today) { d, v in mutate(d) { $0.hrv = v } }
        await collectAvg(.oxygenSaturation, unit: .percent(), start: start, anchor: today) { d, v in mutate(d) { $0.oxygenSaturation = v } }
        await collectHeartRate(start: start, anchor: today) { d, avg, lo, hi in
            mutate(d) { $0.heartRateAvg = avg; $0.heartRateMin = lo; $0.heartRateMax = hi }
        }

        await collectSleep(start: start, now: now) { d, total, deep, rem, core, awake, sStart, sEnd in
            mutate(d) {
                $0.sleepTotal = total; $0.sleepDeep = deep; $0.sleepREM = rem
                $0.sleepCore = core; $0.sleepAwake = awake; $0.sleepStart = sStart; $0.sleepEnd = sEnd
            }
        }

        LPLog.healthKit.notice("History backfill: \(byDay.count, privacy: .public) day buckets over \(days, privacy: .public)d")
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// Read the last `days` of completed `HKWorkout`s as per-workout detail for
    /// the 运动记录 card (type / time range / duration / energy / distance →
    /// pace). Separate from the live `postWorkouts` delta path, which only
    /// surfaces the *latest* workout for the 发芽 flow.
    func fetchWorkoutHistory(days: Int = 35) async -> [WorkoutValues] {
        guard authState == .granted, HKHealthStore.isHealthDataAvailable() else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -days, to: today) else { return [] }
        let predicate = HKSamplePredicate.workout(
            HKQuery.predicateForSamples(withStart: start, end: nil))
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate)])
        do {
            let workouts = try await descriptor.result(for: store)
            let energyType = HKQuantityType(.activeEnergyBurned)
            let distanceType = HKQuantityType(.distanceWalkingRunning)
            let out: [WorkoutValues] = workouts.map { w in
                let kcal = w.statistics(for: energyType)?
                    .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                let dist = w.statistics(for: distanceType)?
                    .sumQuantity()?.doubleValue(for: .meter()) ?? 0
                return WorkoutValues(
                    id: w.uuid, kind: Self.bucket(w.workoutActivityType),
                    start: w.startDate, end: w.endDate, duration: w.duration,
                    energyKcal: kcal, distanceMeters: dist)
            }
            LPLog.workout.notice("Workout history: \(out.count, privacy: .public) over \(days, privacy: .public)d")
            return out
        } catch {
            LPLog.workout.error("fetchWorkoutHistory: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Collection helpers

    private func collectSum(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                            start: Date, anchor: Date,
                            emit: @escaping (Date, Double) -> Void) async {
        let type = HKQuantityType(id)
        let predicate = HKSamplePredicate.quantitySample(
            type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: Date()))
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate, options: .cumulativeSum,
            anchorDate: anchor, intervalComponents: DateComponents(day: 1))
        do {
            let collection = try await descriptor.result(for: store)
            collection.enumerateStatistics(from: start, to: Date()) { stat, _ in
                if let q = stat.sumQuantity() { emit(stat.startDate, q.doubleValue(for: unit)) }
            }
        } catch {
            LPLog.healthKit.error("collectSum \(id.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func collectAvg(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                            start: Date, anchor: Date,
                            emit: @escaping (Date, Double) -> Void) async {
        let type = HKQuantityType(id)
        let predicate = HKSamplePredicate.quantitySample(
            type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: Date()))
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate, options: .discreteAverage,
            anchorDate: anchor, intervalComponents: DateComponents(day: 1))
        do {
            let collection = try await descriptor.result(for: store)
            collection.enumerateStatistics(from: start, to: Date()) { stat, _ in
                if let q = stat.averageQuantity() { emit(stat.startDate, q.doubleValue(for: unit)) }
            }
        } catch {
            LPLog.healthKit.error("collectAvg \(id.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func collectHeartRate(start: Date, anchor: Date,
                                  emit: @escaping (Date, Double, Double, Double) -> Void) async {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let type = HKQuantityType(.heartRate)
        let predicate = HKSamplePredicate.quantitySample(
            type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: Date()))
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate, options: [.discreteAverage, .discreteMin, .discreteMax],
            anchorDate: anchor, intervalComponents: DateComponents(day: 1))
        do {
            let collection = try await descriptor.result(for: store)
            collection.enumerateStatistics(from: start, to: Date()) { stat, _ in
                let avg = stat.averageQuantity()?.doubleValue(for: bpm) ?? 0
                let lo = stat.minimumQuantity()?.doubleValue(for: bpm) ?? 0
                let hi = stat.maximumQuantity()?.doubleValue(for: bpm) ?? 0
                if avg > 0 { emit(stat.startDate, avg, lo, hi) }
            }
        } catch {
            LPLog.healthKit.error("collectHeartRate: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sleep bucketed per night, attributed to the wake-day (`startOfDay` of the
    /// session's end). Prefers stage samples; falls back to legacy `.asleep` only
    /// on days with no stage data (avoids the multi-source double count).
    private func collectSleep(start: Date, now: Date,
                              emit: @escaping (Date, TimeInterval, TimeInterval, TimeInterval, TimeInterval, TimeInterval, Date?, Date?) -> Void) async {
        let predicate = HKSamplePredicate.categorySample(
            type: HKCategoryType(.sleepAnalysis),
            predicate: HKQuery.predicateForSamples(withStart: start, end: now))
        let descriptor = HKSampleQueryDescriptor(predicates: [predicate],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        do {
            let samples = try await descriptor.result(for: store)
            let cal = Calendar.current
            var byDay: [Date: [HKCategorySample]] = [:]
            for s in samples { byDay[cal.startOfDay(for: s.endDate), default: []].append(s) }

            for (day, daySamples) in byDay {
                let hasStages = daySamples.contains { isStage(HKCategoryValueSleepAnalysis(rawValue: $0.value)) }
                var total: TimeInterval = 0, deep: TimeInterval = 0, rem: TimeInterval = 0
                var core: TimeInterval = 0, awake: TimeInterval = 0
                var minStart: Date?, maxEnd: Date?
                for s in daySamples {
                    let v = HKCategoryValueSleepAnalysis(rawValue: s.value)
                    let dur = s.endDate.timeIntervalSince(s.startDate)
                    var asleep = true
                    switch v {
                    case .some(.asleepDeep):        deep += dur;  total += dur
                    case .some(.asleepREM):         rem += dur;   total += dur
                    case .some(.asleepCore):        core += dur;  total += dur
                    case .some(.asleepUnspecified): total += dur
                    case .some(.asleep):            if hasStages { asleep = false } else { total += dur }
                    default:                        asleep = false; if v == .some(.awake) { awake += dur }
                    }
                    if asleep {
                        minStart = min(minStart ?? s.startDate, s.startDate)
                        maxEnd = max(maxEnd ?? s.endDate, s.endDate)
                    }
                }
                if total > 0 { emit(day, total, deep, rem, core, awake, minStart, maxEnd) }
            }
        } catch {
            LPLog.healthKit.error("collectSleep: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func isStage(_ v: HKCategoryValueSleepAnalysis?) -> Bool {
        switch v {
        case .some(.asleepCore), .some(.asleepDeep), .some(.asleepREM), .some(.asleepUnspecified): return true
        default: return false
        }
    }
}

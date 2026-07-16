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
        await collectHourlySteps(start: start, anchor: today) { d, hourly in mutate(d) { $0.hourlySteps = hourly } }
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

        await collectSleep(start: start, now: now) { d, night in
            mutate(d) {
                $0.sleepTotal = night.total; $0.sleepDeep = night.deep; $0.sleepREM = night.rem
                $0.sleepCore = night.core; $0.sleepAwake = night.awake
                $0.sleepStart = night.start; $0.sleepEnd = night.end
                $0.sleepSegments = night.segments
            }
        }

        for (day, g) in await collectGoals(start: start, end: now) {
            mutate(day) { $0.moveGoal = g.move; $0.exerciseGoal = g.exercise; $0.standGoal = g.stand }
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

    /// Today's per-hour step counts (24 entries, hours not yet reached = 0).
    /// Cheap single query — run on foreground reconcile so the 今日脚步 grass
    /// stays fresh through the day (the full backfill only runs at launch).
    func fetchTodayHourlySteps() async -> [Int] {
        guard authState == .granted, HKHealthStore.isHealthDataAvailable() else { return [] }
        let today = Calendar.current.startOfDay(for: Date())
        var result: [Int] = []
        await collectHourlySteps(start: today, anchor: today) { day, hourly in
            if day == today { result = hourly }
        }
        return result
    }

    /// One day's Apple Activity ring goals (read from `HKActivitySummary`).
    struct DayGoals: Sendable { var move = 0.0; var exercise = 0; var stand = 0 }

    /// Per-day ring goals: Move (kcal) / Exercise (min) / Stand (hours). 0 = goal
    /// unset → the 活动 card uses a default. Needs the `activitySummaryType` read
    /// auth added in `requestAuthorization`. iOS 16+ optional goals; nil → 0.
    private func collectGoals(start: Date, end: Date) async -> [Date: DayGoals] {
        let cal = Calendar.current
        var startC = cal.dateComponents([.year, .month, .day], from: start)
        startC.calendar = cal
        var endC = cal.dateComponents([.year, .month, .day], from: end)
        endC.calendar = cal
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: startC, end: endC)
        let descriptor = HKActivitySummaryQueryDescriptor(predicate: predicate)
        do {
            let summaries = try await descriptor.result(for: store)
            var out: [Date: DayGoals] = [:]
            for s in summaries {
                guard let day = cal.date(from: s.dateComponents(for: cal)) else { continue }
                let move = s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                let ex = s.exerciseTimeGoal?.doubleValue(for: .minute()) ?? 0
                let st = s.standHoursGoal?.doubleValue(for: .count()) ?? 0
                out[cal.startOfDay(for: day)] = DayGoals(
                    move: move, exercise: Int(ex.rounded()), stand: Int(st.rounded()))
            }
            LPLog.healthKit.notice("Goals: \(out.count, privacy: .public) day summaries")
            return out
        } catch {
            LPLog.healthKit.error("collectGoals: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    // MARK: - Collection helpers

    /// Hour-bucketed step sums grouped per day — emits one 24-entry array per
    /// day (index = local hour). Same statistics-collection query as the daily
    /// sums, just with a 1-hour interval.
    private func collectHourlySteps(start: Date, anchor: Date,
                                    emit: (Date, [Int]) -> Void) async {
        let cal = Calendar.current
        let type = HKQuantityType(.stepCount)
        let predicate = HKSamplePredicate.quantitySample(
            type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: Date()))
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate, options: .cumulativeSum,
            anchorDate: anchor, intervalComponents: DateComponents(hour: 1))
        do {
            let collection = try await descriptor.result(for: store)
            var byDay: [Date: [Int]] = [:]
            collection.enumerateStatistics(from: start, to: Date()) { stat, _ in
                guard let q = stat.sumQuantity() else { return }
                let day = cal.startOfDay(for: stat.startDate)
                let hour = cal.component(.hour, from: stat.startDate)
                var hourly = byDay[day] ?? Array(repeating: 0, count: 24)
                if hour < 24 { hourly[hour] += Int(q.doubleValue(for: .count())) }
                byDay[day] = hourly
            }
            for (day, hourly) in byDay { emit(day, hourly) }
        } catch {
            LPLog.healthKit.error("collectHourlySteps: \(error.localizedDescription, privacy: .public)")
        }
    }

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

    /// One night's aggregated sleep, as handed to `collectSleep`'s emit.
    struct NightSleep {
        var total: TimeInterval = 0, deep: TimeInterval = 0, rem: TimeInterval = 0
        var core: TimeInterval = 0, awake: TimeInterval = 0
        var start: Date?, end: Date?
        /// Stage segments in time order, adjacent same-stage samples merged.
        var segments: [SleepSegmentValue] = []
    }

    /// Sleep bucketed per night, attributed to the wake-day (`startOfDay` of the
    /// session's end). Prefers stage samples; falls back to legacy `.asleep` only
    /// on days with no stage data (avoids the multi-source double count).
    private func collectSleep(start: Date, now: Date,
                              emit: @escaping (Date, NightSleep) -> Void) async {
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
                let hasStages = daySamples.contains {
                    PiboCoreSleepAdapter.sampleIsDetailed(
                        HKCategoryValueSleepAnalysis(rawValue: $0.value)
                    )
                }
                var night = NightSleep()
                for s in daySamples {
                    let v = HKCategoryValueSleepAnalysis(rawValue: s.value)
                    let dur = s.endDate.timeIntervalSince(s.startDate)
                    var asleep = true
                    var stage: SleepStage?
                    switch PiboCoreSleepAdapter.resolveSample(
                        v,
                        hasDetailedSamples: hasStages
                    ) {
                    case .deep:        night.deep += dur;  night.total += dur; stage = .deep
                    case .rem:         night.rem += dur;   night.total += dur; stage = .rem
                    case .core:        night.core += dur;  night.total += dur; stage = .core
                    case .legacyAsleep, .unspecified:
                        night.total += dur; stage = .core
                    case .awake:
                        asleep = false
                        night.awake += dur
                        stage = .awake
                    case .ignored:
                        asleep = false
                    }
                    if asleep {
                        night.start = min(night.start ?? s.startDate, s.startDate)
                        night.end = max(night.end ?? s.endDate, s.endDate)
                    }
                    if let stage { appendSegment(&night.segments, s.startDate, s.endDate, stage) }
                }
                if night.total > 0 { emit(day, night) }
            }
        } catch {
            LPLog.healthKit.error("collectSleep: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Append one sample to the night's segment list, merging into the previous
    /// segment when it continues the same stage (≤60s gap) — watch data writes
    /// many back-to-back samples per stage.
    private func appendSegment(_ segments: inout [SleepSegmentValue],
                               _ start: Date, _ end: Date, _ stage: SleepStage) {
        if let last = segments.last,
           PiboCoreSleepAdapter.segmentsShouldMerge(
               sameStage: last.stage == stage,
               gapSeconds: start.timeIntervalSince(last.end)
           ) {
            segments[segments.count - 1].end = max(last.end, end)
        } else {
            segments.append(SleepSegmentValue(start: start, end: end, stage: stage))
        }
    }
}

import Foundation
import SwiftData
import Observation
import CoreLocation
import PiboCore
#if DEBUG
import UIKit
#endif

enum HealthHistoryWriteOrigin {
    case preserveExistingProvenance
    case verified
    case synthetic
}

/// In-app health history, backed by SwiftData. Owns the model context, upserts
/// daily records (one row per day), and vends read queries for the 上滑数据二楼.
///
/// `revision` bumps on every write so SwiftUI views that read it re-query after a
/// backfill / reconcile without manual refresh plumbing.
@MainActor
@Observable
final class HealthHistoryStore {
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let provenanceDefaults: UserDefaults
    @ObservationIgnored private let syntheticDaysKey: String
    @ObservationIgnored private let syntheticWorkoutIDsKey: String
    @ObservationIgnored private var syntheticHealthDayKeys: Set<String>
    @ObservationIgnored private var syntheticWorkoutIDs: Set<UUID>
    private(set) var revision = 0

    init(
        context: ModelContext,
        provenanceDefaults: UserDefaults = .standard,
        syntheticDaysKey: String = PiboPersistenceKeys.Defaults.debugSyntheticHealthDays,
        syntheticWorkoutIDsKey: String = PiboPersistenceKeys.Defaults.debugSyntheticWorkoutIDs
    ) {
        self.context = context
        self.provenanceDefaults = provenanceDefaults
        self.syntheticDaysKey = syntheticDaysKey
        self.syntheticWorkoutIDsKey = syntheticWorkoutIDsKey
        syntheticHealthDayKeys = Set(
            provenanceDefaults.stringArray(forKey: syntheticDaysKey) ?? []
        )
        syntheticWorkoutIDs = Set(
            (provenanceDefaults.stringArray(forKey: syntheticWorkoutIDsKey) ?? [])
                .compactMap(UUID.init(uuidString:))
        )
        adoptLegacyDebugSeedProvenanceIfNeeded()
    }

    // MARK: Reads

    /// The record for a given calendar day (keyed by `startOfDay`), if present.
    func record(on day: Date) -> HealthDayRecord? {
        let key = Calendar.current.startOfDay(for: day)
        var d = FetchDescriptor<HealthDayRecord>(predicate: #Predicate { $0.date == key })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Records whose day falls in `[start, end]` (inclusive), oldest first.
    func records(from start: Date, to end: Date) -> [HealthDayRecord] {
        let lo = Calendar.current.startOfDay(for: start)
        let hi = Calendar.current.startOfDay(for: end)
        let d = FetchDescriptor<HealthDayRecord>(
            predicate: #Predicate { $0.date >= lo && $0.date <= hi },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? context.fetch(d)) ?? []
    }

    /// Only platform-health rows may advance story facts or mint `bo`.
    /// DEBUG history remains useful for screenshots but is never evidence.
    func verifiedHealthRecords(from start: Date, to end: Date) -> [HealthDayRecord] {
        records(from: start, to: end).filter {
            !syntheticHealthDayKeys.contains(Self.provenanceDayKey($0.date))
        }
    }

    /// All records in the calendar month containing `day`.
    func recordsForMonth(containing day: Date) -> [HealthDayRecord] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: day) else { return [] }
        return records(from: interval.start, to: cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end)
    }

    // MARK: Writes

    /// Find-or-create the row for `day` and mutate it. Bumps `revision`.
    @discardableResult
    func upsert(
        day: Date,
        origin: HealthHistoryWriteOrigin = .preserveExistingProvenance,
        configure: (HealthDayRecord) -> Void
    ) -> HealthDayRecord {
        let key = Calendar.current.startOfDay(for: day)
        let record: HealthDayRecord
        if let existing = self.record(on: key) {
            record = existing
        } else {
            record = HealthDayRecord(date: key)
            context.insert(record)
        }
        configure(record)
        record.updatedAt = .now
        if case .synthetic = origin {
            markSyntheticHealthDays([Self.provenanceDayKey(key)])
        }
        try? context.save()
        revision += 1
        return record
    }

    /// Bulk-ingest backfilled HK values. Skips empty days so the calendar
    /// doesn't fill with all-zero placeholder rows.
    func ingest(_ values: [HealthDayValues]) {
        let persistableValues = values.filter(\.hasPersistableData)
        guard let firstDay = persistableValues.first.map({
            Calendar.current.startOfDay(for: $0.date)
        }) else { return }

        let calendar = Calendar.current
        let dayKeys = persistableValues.map { calendar.startOfDay(for: $0.date) }
        let earliestDay = dayKeys.reduce(firstDay, min)
        let latestDay = dayKeys.reduce(firstDay, max)
        var recordsByDay: [Date: HealthDayRecord] = [:]
        for record in records(from: earliestDay, to: latestDay) {
            recordsByDay[calendar.startOfDay(for: record.date)] = record
        }

        var verifiedKeys: Set<String> = []
        for value in persistableValues {
            let key = calendar.startOfDay(for: value.date)
            let record: HealthDayRecord
            if let existing = recordsByDay[key] {
                record = existing
            } else {
                record = HealthDayRecord(date: key)
                context.insert(record)
                recordsByDay[key] = record
            }
            apply(value, to: record)
            verifiedKeys.insert(Self.provenanceDayKey(key))
        }
        clearSyntheticMarkers(verifiedKeys)
        try? context.save()
        revision += 1
    }

    /// Apply transport values onto a row without per-row save (used by `ingest`).
    private func upsertSilently(_ v: HealthDayValues) {
        let key = Calendar.current.startOfDay(for: v.date)
        let record: HealthDayRecord
        if let existing = self.record(on: key) {
            record = existing
        } else {
            record = HealthDayRecord(date: key)
            context.insert(record)
        }
        apply(v, to: record)
    }

    private func apply(_ v: HealthDayValues, to record: HealthDayRecord) {
        record.steps = v.steps
        record.hourlySteps = v.hourlySteps
        record.activeEnergy = v.activeEnergy
        record.exerciseMinutes = v.exerciseMinutes
        record.standMinutes = v.standMinutes
        record.distanceMeters = v.distanceMeters
        record.flightsClimbed = v.flightsClimbed
        record.moveGoal = v.moveGoal
        record.exerciseGoal = v.exerciseGoal
        record.standGoal = v.standGoal
        record.restingHR = v.restingHR
        record.heartRateAvg = v.heartRateAvg
        record.heartRateMin = v.heartRateMin
        record.heartRateMax = v.heartRateMax
        record.hrv = v.hrv
        record.oxygenSaturation = v.oxygenSaturation
        record.sleepTotal = v.sleepTotal
        record.sleepDeep = v.sleepDeep
        record.sleepREM = v.sleepREM
        record.sleepCore = v.sleepCore
        record.sleepAwake = v.sleepAwake
        record.sleepStart = v.sleepStart
        record.sleepEnd = v.sleepEnd
        record.sleepInBed = v.sleepInBed
        record.sleepAwakeningCount = v.sleepAwakeningCount
        record.sleepLatency = v.sleepLatency
        record.sleepSegments = v.sleepSegments
        record.overnightHRV = v.overnightHRV
        record.sleepingHeartRateAverage = v.sleepingHeartRateAverage
        record.sleepingHeartRateMinimum = v.sleepingHeartRateMinimum
        record.sleepingWristTemperature = v.sleepingWristTemperature
        record.sleepingRespiratoryRate = v.sleepingRespiratoryRate
        record.sleepingOxygenSaturation = v.sleepingOxygenSaturation
        record.sleepingBreathingDisturbances = v.sleepingBreathingDisturbances
        record.vo2Max = v.vo2Max
        record.recoveryIndexScore = v.recoveryIndexScore
        record.mindfulMinutes = v.mindfulMinutes
        record.workoutCount = v.workoutCount
        record.workoutMinutes = v.workoutMinutes
        record.workoutEnergy = v.workoutEnergy
        record.updatedAt = .now
    }

    private static func provenanceDayKey(_ date: Date) -> String {
        String(date.timeIntervalSinceReferenceDate.bitPattern)
    }

    private func markSyntheticHealthDays(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        syntheticHealthDayKeys.formUnion(keys)
        persistSyntheticHealthDays()
    }

    private func clearSyntheticMarkers(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        let previousCount = syntheticHealthDayKeys.count
        syntheticHealthDayKeys.subtract(keys)
        if syntheticHealthDayKeys.count != previousCount {
            persistSyntheticHealthDays()
        }
    }

    private func persistSyntheticHealthDays() {
        provenanceDefaults.set(syntheticHealthDayKeys.sorted(), forKey: syntheticDaysKey)
    }

    private func persistSyntheticWorkoutIDs() {
        provenanceDefaults.set(
            syntheticWorkoutIDs.map(\.uuidString).sorted(),
            forKey: syntheticWorkoutIDsKey
        )
    }

    /// Builds before provenance tracking wrote deterministic sample rows into
    /// the same SwiftData table as HealthKit. Mark the existing rows once; a
    /// subsequent real HealthKit ingest clears markers day by day.
    private func adoptLegacyDebugSeedProvenanceIfNeeded() {
        let versionKey = PiboPersistenceKeys.Defaults.debugHealthProvenanceVersion
        guard provenanceDefaults.integer(forKey: versionKey) < 2 else { return }
        defer { provenanceDefaults.set(2, forKey: versionKey) }
        guard provenanceDefaults.string(
            forKey: PiboPersistenceKeys.Defaults.debugHistorySeedState
        ) != nil else { return }
        let descriptor = FetchDescriptor<HealthDayRecord>()
        let existing = (try? context.fetch(descriptor)) ?? []
        markSyntheticHealthDays(Set(existing.map { Self.provenanceDayKey($0.date) }))
        let workoutDescriptor = FetchDescriptor<WorkoutRecord>()
        let workouts = (try? context.fetch(workoutDescriptor)) ?? []
        syntheticWorkoutIDs.formUnion(workouts.map(\.id))
        persistSyntheticWorkoutIDs()
    }

    // MARK: - Workouts (per-workout detail for the 运动记录 card)

    /// Workouts whose start falls on `day`, earliest first.
    func workouts(on day: Date) -> [WorkoutRecord] {
        let key = Calendar.current.startOfDay(for: day)
        let d = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.day == key },
            sortBy: [SortDescriptor(\.start, order: .forward)])
        return (try? context.fetch(d)) ?? []
    }

    private func workoutRecord(id: UUID) -> WorkoutRecord? {
        var d = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Upsert backfilled HK workouts (keyed by HK uuid). Bumps `revision`.
    func ingestWorkouts(
        _ values: [WorkoutValues],
        origin: HealthHistoryWriteOrigin = .verified
    ) {
        let cal = Calendar.current
        var changedDays: Set<Date> = []
        if case .verified = origin {
            let descriptor = FetchDescriptor<WorkoutRecord>()
            let existing = (try? context.fetch(descriptor)) ?? []
            for workout in existing where syntheticWorkoutIDs.contains(workout.id) {
                changedDays.insert(workout.day)
                syntheticWorkoutIDs.remove(workout.id)
                context.delete(workout)
            }
            persistSyntheticWorkoutIDs()
        }
        for v in values {
            let record: WorkoutRecord
            if let existing = workoutRecord(id: v.id) {
                record = existing
            } else {
                record = WorkoutRecord(id: v.id, day: cal.startOfDay(for: v.start),
                                       kindRaw: v.kind.rawValue, start: v.start, end: v.end,
                                       duration: v.duration, energyKcal: v.energyKcal,
                                       distanceMeters: v.distanceMeters)
                context.insert(record)
            }
            record.day = cal.startOfDay(for: v.start)
            record.kindRaw = v.kind.rawValue
            record.start = v.start; record.end = v.end; record.duration = v.duration
            record.energyKcal = v.energyKcal; record.distanceMeters = v.distanceMeters
            record.averageHeartRate = v.averageHeartRate
            record.minimumHeartRate = v.minimumHeartRate
            record.maximumHeartRate = v.maximumHeartRate
            record.effortScore = v.effortScore
            record.effortIsEstimated = v.effortIsEstimated
            let dayKey = Self.provenanceDayKey(record.day)
            let restingHeartRate = syntheticHealthDayKeys.contains(dayKey)
                ? nil
                : self.record(on: record.day)?.restingHR
            record.trainingLoad = PiboCoreWellnessAdapter.trainingLoad(
                workout: v,
                restingHeartRate: restingHeartRate
            )?.load
            record.updatedAt = .now
            if case .synthetic = origin {
                syntheticWorkoutIDs.insert(record.id)
            } else if case .verified = origin {
                syntheticWorkoutIDs.remove(record.id)
            }
            changedDays.insert(record.day)
        }
        if case .synthetic = origin {
            persistSyntheticWorkoutIDs()
            markSyntheticHealthDays(Set(changedDays.map(Self.provenanceDayKey)))
        }
        for day in changedDays {
            let workouts = workouts(on: day)
            let daily: HealthDayRecord
            if let existing = record(on: day) {
                daily = existing
            } else {
                daily = HealthDayRecord(date: day)
                context.insert(daily)
            }
            let provenanceKey = Self.provenanceDayKey(day)
            if case .verified = origin,
               syntheticHealthDayKeys.remove(provenanceKey) != nil {
                // A real workout must not make the other DEBUG-seeded metrics
                // on the same row look verified.
                clearHealthMetrics(on: daily)
                persistSyntheticHealthDays()
            }
            daily.workoutCount = workouts.count
            daily.workoutMinutes = Int(workouts.reduce(0) { $0 + $1.duration } / 60)
            daily.workoutEnergy = workouts.reduce(0) { $0 + $1.energyKcal }
            let loads = workouts.compactMap(\.trainingLoad)
            daily.trainingLoad = loads.isEmpty ? nil : loads.reduce(0, +)
            daily.updatedAt = .now
        }
        try? context.save()
        revision += 1
    }

    private func clearHealthMetrics(on record: HealthDayRecord) {
        record.steps = 0
        record.hourlySteps = []
        record.activeEnergy = 0
        record.exerciseMinutes = 0
        record.standMinutes = 0
        record.distanceMeters = 0
        record.flightsClimbed = 0
        record.moveGoal = 0
        record.exerciseGoal = 0
        record.standGoal = 0
        record.restingHR = 0
        record.heartRateAvg = 0
        record.heartRateMin = 0
        record.heartRateMax = 0
        record.hrv = 0
        record.oxygenSaturation = 0
        record.sleepTotal = 0
        record.sleepDeep = 0
        record.sleepREM = 0
        record.sleepCore = 0
        record.sleepAwake = 0
        record.sleepStart = nil
        record.sleepEnd = nil
        record.sleepInBed = nil
        record.sleepAwakeningCount = nil
        record.sleepLatency = nil
        record.sleepSegments = []
        record.overnightHRV = nil
        record.sleepingHeartRateAverage = nil
        record.sleepingHeartRateMinimum = nil
        record.sleepingWristTemperature = nil
        record.sleepingRespiratoryRate = nil
        record.sleepingOxygenSaturation = nil
        record.sleepingBreathingDisturbances = nil
        record.vo2Max = nil
        record.recoveryIndexScore = nil
        record.trainingLoad = nil
        record.wellnessPayload = nil
        record.mindfulMinutes = 0
    }

    // MARK: - Cross-platform wellness reports

    /// Regenerates versioned Core outputs from verified platform data only.
    /// DEBUG rows remain available to the UI but can never become score,
    /// resilience, story, or economy evidence.
    func recomputeWellness(now: Date = .now, days: Int = 35) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -days, to: today) else { return }

        let allRecords = records(from: start, to: today)
        let verified = allRecords.filter {
            !syntheticHealthDayKeys.contains(Self.provenanceDayKey($0.date))
        }
        let verifiedDays = Set(verified.map { cal.startOfDay(for: $0.date) })
        for record in allRecords where !verifiedDays.contains(cal.startOfDay(for: record.date)) {
            record.wellnessPayload = nil
        }

        let realStressByDay = Dictionary(grouping: StressLogStore.entries.filter {
            !$0.synthetic && $0.interpretationEligible && $0.stressScore != nil
        }) { cal.startOfDay(for: $0.date) }
        .mapValues { readings -> Double in
            let scores = readings.compactMap(\.stressScore).sorted()
            let middle = scores.count / 2
            return scores.count.isMultiple(of: 2)
                ? (scores[middle - 1] + scores[middle]) / 2
                : scores[middle]
        }

        var snapshots: [Date: DailyWellnessSnapshot] = [:]
        let encoder = JSONEncoder()
        for (index, record) in verified.enumerated() {
            let report = PiboCoreWellnessAdapter.report(
                current: record,
                history: Array(verified[..<index]),
                calendar: cal
            )
            var snapshot = DailyWellnessSnapshot(report: report, generatedAt: now)
            snapshot.apply(PiboCoreWellnessAdapter.restorativeTime(
                mindfulMinutes: record.mindfulMinutes
            ))
            snapshots[cal.startOfDay(for: record.date)] = snapshot
        }

        for (index, record) in verified.enumerated() {
            let day = cal.startOfDay(for: record.date)
            guard var snapshot = snapshots[day] else { continue }
            let lowerBound = max(0, index - 13)
            let resilienceDays = verified[lowerBound...index].compactMap { candidate
                -> PiboCoreWellnessAdapter.ResilienceDay? in
                let candidateDay = cal.startOfDay(for: candidate.date)
                guard let offset = cal.dateComponents(
                    [.day], from: candidateDay, to: day
                ).day, (0..<14).contains(offset) else { return nil }
                let candidateSnapshot = snapshots[candidateDay]
                return .init(
                    daysBeforeCurrent: offset,
                    recoveryScore: candidateSnapshot?.recoveryScore?.value,
                    stressScore: realStressByDay[candidateDay],
                    restorativeMinutes: candidateSnapshot?.restorativeMinutes
                )
            }
            snapshot.apply(PiboCoreWellnessAdapter.resilience(days: resilienceDays))
            record.wellnessPayload = try? encoder.encode(snapshot)
        }

        try? context.save()
        revision += 1
    }

    // MARK: - Food photos (今日记录 card)

    /// Food photos captured on `day`, earliest first.
    func foodPhotos(on day: Date) -> [FoodPhoto] {
        let key = Calendar.current.startOfDay(for: day)
        let d = FetchDescriptor<FoodPhoto>(
            predicate: #Predicate { $0.day == key },
            sortBy: [SortDescriptor(\.capturedAt, order: .forward)])
        return (try? context.fetch(d)) ?? []
    }

    /// The latest food photo captured for `mealType` on `day`, if any.
    func foodPhoto(on day: Date, mealType: MealType) -> FoodPhoto? {
        let raw = mealType.rawValue
        return foodPhotos(on: day).last { $0.mealTypeRaw == raw }
    }

    /// Persist a freshly captured (and cut-out) food photo. Bumps `revision`.
    @discardableResult
    func addFoodPhoto(pngData: Data, sourceJPEGData: Data? = nil,
                      capturedAt: Date = .now, subjectLabel: String? = nil,
                      mealType: MealType? = nil) -> FoodPhoto {
        let photo = FoodPhoto(capturedAt: capturedAt, pngData: pngData,
                              sourceJPEGData: sourceJPEGData,
                              subjectLabel: subjectLabel, mealType: mealType)
        context.insert(photo)
        try? context.save()
        revision += 1
        return photo
    }

    /// Mutate an existing food photo (e.g. attach the backend calorie analysis).
    /// Bumps `revision` so the meal modal re-renders. No-op if the id is gone.
    func updateFoodPhoto(id: UUID, apply: (FoodPhoto) -> Void) {
        var d = FetchDescriptor<FoodPhoto>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        guard let photo = try? context.fetch(d).first else { return }
        apply(photo)
        photo.updatedAt = .now
        try? context.save()
        revision += 1
    }

    // MARK: - Walk doodles (足迹涂鸦 card)

    /// Walk doodles traced on `day`, earliest first.
    func walkDoodles(on day: Date) -> [WalkDoodleRecord] {
        let key = Calendar.current.startOfDay(for: day)
        let d = FetchDescriptor<WalkDoodleRecord>(
            predicate: #Predicate { $0.day == key },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        return (try? context.fetch(d)) ?? []
    }

    /// Persist a finished walk doodle. Bumps `revision`.
    @discardableResult
    func addWalkDoodle(_ result: WalkDoodleResult, createdAt: Date = .now) -> WalkDoodleRecord {
        let record = WalkDoodleRecord(
            createdAt: createdAt,
            coordinates: result.coordinates,
            distanceMeters: result.distanceMeters,
            areaSquareMeters: result.areaSquareMeters,
            durationSeconds: result.duration,
            title: result.title)
        context.insert(record)
        try? context.save()
        revision += 1
        return record
    }

    #if DEBUG
    /// Dev-only: seed ~5 weeks of plausible history so the 二楼 is demonstrable on
    /// a simulator with no HealthKit data. Compiled out of Release; on a real
    /// authorized device the HK backfill overwrites these rows anyway.
    func seedSampleHistoryIfEmpty(days: Int = 35, forceFill: Bool = false) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let existing = records(
            from: cal.date(byAdding: .day, value: -days, to: today) ?? today,
            to: today
        )
        // A zero-only row may be created before the demo seeder runs (for
        // example by a stress reconcile). That is not meaningful history and
        // must not prevent the simulator from getting demonstrable data.
        guard forceFill || !existing.contains(where: \.hasData) else { return }
        var seededKeys: Set<String> = []
        for offset in 0...days {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            // Deterministic pseudo-values (no RNG): vary by day-of-year.
            let doy = cal.ordinality(of: .day, in: .year, for: day) ?? offset
            let steps = 2000 + (doy * 811) % 11000
            let sleepH = 5.0 + Double((doy * 7) % 35) / 10.0          // 5.0–8.5h
            let deep = sleepH * 3600 * (0.12 + Double(doy % 9) / 100)  // 12–20%
            let sStart = cal.date(bySettingHour: 23, minute: 20, second: 0,
                                  of: cal.date(byAdding: .day, value: -1, to: day) ?? day)
            let sEnd = sStart?.addingTimeInterval(sleepH * 3600)
            upsertSilently(HealthDayValues(
                date: day,
                steps: steps,
                hourlySteps: Self.seedHourlySteps(total: steps, seed: doy),
                activeEnergy: Double(180 + (doy * 13) % 420),
                exerciseMinutes: (doy * 5) % 65,
                standMinutes: 120 + (doy % 8) * 30,   // ~2–5 stand-hours when /60
                distanceMeters: Double(steps) * 0.72,
                moveGoal: 500, exerciseGoal: 30, standGoal: 12,   // 标准三环目标（占位演示）
                restingHR: 56 + Double(doy % 12),
                heartRateAvg: 72 + Double(doy % 18),
                hrv: 30 + Double(doy % 45),
                oxygenSaturation: 0.96 + Double(doy % 4) / 100,
                sleepTotal: sleepH * 3600,
                sleepDeep: deep,
                sleepREM: sleepH * 3600 * 0.2,
                sleepStart: sStart,
                sleepEnd: sEnd,
                sleepSegments: sStart.map { Self.seedSleepSegments(start: $0, hours: sleepH, seed: doy) } ?? [],
                mindfulMinutes: doy % 3 == 0 ? 10 : 0,
                workoutCount: (doy * 5) % 65 > 20 ? 1 : 0,
                workoutMinutes: (doy * 5) % 65
            ))
            seededKeys.insert(Self.provenanceDayKey(day))
        }
        markSyntheticHealthDays(seededKeys)
        try? context.save()
        revision += 1
    }

    /// Dev-only umbrella: seed days + workouts + food, each guarded independently
    /// so a store half-populated by an older build still gets the missing pieces.
    func seedSampleAllIfEmpty(days: Int = 35, forceMaintenance: Bool = false) async {
        let today = Calendar.current.startOfDay(for: .now)
        let seedState = "2:\(Int(today.timeIntervalSinceReferenceDate))"
        let defaults = UserDefaults.standard
        guard forceMaintenance
            || defaults.string(forKey: PiboPersistenceKeys.Defaults.debugHistorySeedState) != seedState else {
            return
        }

        seedSampleHistoryIfEmpty(days: days, forceFill: forceMaintenance)
        upgradeSeededRows(days: days)
        seedSampleWorkoutsIfEmpty(days: days)
        let seededFood = await seedSampleFoodIfEmpty()
        if !seededFood {
            await upgradeSeededFood()
        }
        seedSampleDoodlesIfEmpty()
        defaults.set(seedState, forKey: PiboPersistenceKeys.Defaults.debugHistorySeedState)
    }

    /// Dev-only: one synthetic walk doodle on *today* — a hand-wobbled loop — so the
    /// 足迹涂鸦 card demos on a simulator with no GPS history. Re-rendered offline
    /// from its points like a real capture.
    private func seedSampleDoodlesIfEmpty() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard walkDoodles(on: today).isEmpty else { return }
        let centerLat = 37.7749, centerLon = -122.4194
        let radiusM = 90.0
        let mPerDegLat = 111_320.0
        let mPerDegLon = 111_320.0 * cos(centerLat * .pi / 180)
        let start = cal.date(bySettingHour: 8, minute: 12, second: 0, of: today) ?? today
        let segments = 28
        var coords: [DoodleCoordinate] = []
        for i in 0...segments {
            let a = Double(i) / Double(segments) * 2 * .pi
            let r = radiusM * (1 + 0.12 * sin(a * 3))      // wobble — not a perfect circle
            let lat = centerLat + (r * sin(a)) / mPerDegLat
            let lon = centerLon + (r * cos(a)) / mPerDegLon
            coords.append(DoodleCoordinate(latitude: lat, longitude: lon,
                                           timestamp: start.addingTimeInterval(Double(i) * 14)))
        }
        let cl = coords.map(\.coordinate)
        let record = WalkDoodleRecord(
            createdAt: start,
            coordinates: coords,
            distanceMeters: DoodleGeometry.pathLength(cl),
            areaSquareMeters: DoodleGeometry.enclosedArea(cl),
            durationSeconds: Double(segments) * 14)
        context.insert(record)
        try? context.save()
        revision += 1
    }

    /// Dev-only: rows seeded by an older build predate `hourlySteps` /
    /// `sleepSegments` — fill those in deterministically so the new visuals
    /// demo without wiping the simulator container.
    private func upgradeSeededRows(days: Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let rows = records(from: cal.date(byAdding: .day, value: -days, to: today) ?? today, to: today)
        var changed = false
        for r in rows where syntheticHealthDayKeys.contains(Self.provenanceDayKey(r.date)) {
            let doy = cal.ordinality(of: .day, in: .year, for: r.date) ?? 0
            if r.hourlySteps.isEmpty, r.steps > 0 {
                r.hourlySteps = Self.seedHourlySteps(total: r.steps, seed: doy)
                changed = true
            }
            if r.sleepSegments.isEmpty, r.sleepTotal > 0, let start = r.sleepStart {
                r.sleepSegments = Self.seedSleepSegments(start: start, hours: r.sleepTotal / 3600, seed: doy)
                changed = true
            }
            if r.moveGoal == 0 {
                r.moveGoal = 500; r.exerciseGoal = 30; r.standGoal = 12
                changed = true
            }
        }
        if changed {
            try? context.save()
            revision += 1
        }
    }

    /// Dev-only: one or two synthetic workouts on active days so the 运动记录 card
    /// demos with real-looking rows.
    private func seedSampleWorkoutsIfEmpty(days: Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard workouts(on: today).isEmpty else { return }
        var seeded: [WorkoutValues] = []
        for offset in 0...days {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let doy = cal.ordinality(of: .day, in: .year, for: day) ?? offset
            let minutes = (doy * 5) % 65
            guard minutes > 20 else { continue }
            let isRun = doy % 2 == 0
            let start = cal.date(bySettingHour: 7, minute: 0, second: 0, of: day) ?? day
            let end = start.addingTimeInterval(Double(minutes) * 60)
            let distance = isRun ? Double(minutes) * 165 : Double(minutes) * 95   // ~run vs walk pace
            seeded.append(WorkoutValues(
                id: UUID(), kind: isRun ? .run : .walk, start: start, end: end,
                duration: Double(minutes) * 60, energyKcal: Double(minutes) * 9,
                distanceMeters: distance))
            if doy % 3 == 0 {   // a second, shorter evening walk some days
                let s2 = cal.date(bySettingHour: 19, minute: 0, second: 0, of: day) ?? day
                seeded.append(WorkoutValues(
                    id: UUID(), kind: .walk, start: s2, end: s2.addingTimeInterval(1800),
                    duration: 1800, energyKcal: 120, distanceMeters: 2400))
            }
        }
        ingestWorkouts(seeded, origin: .synthetic)
    }

    /// Seed photo specs — symbol, tint, hour, 识图 label. Shared by the fresh
    /// seed and the upgrade pass that patches pre-label seeded rows.
    private struct FoodSeedSpec: Sendable {
        let symbol: String
        let color: FoodSeedColor
        let hour: Int
        let label: String
    }

    private enum FoodSeedColor: Sendable {
        case brown
        case darkGray
        case green
    }

    private struct RenderedFoodSeed: Sendable {
        let hour: Int
        let label: String
        let pngData: Data
    }

    nonisolated private static let foodSeedSpecs: [FoodSeedSpec] = [
        FoodSeedSpec(symbol: "birthday.cake.fill", color: .brown, hour: 9, label: "蛋糕"),
        FoodSeedSpec(symbol: "cup.and.saucer.fill", color: .darkGray, hour: 11, label: "咖啡"),
        FoodSeedSpec(symbol: "carrot.fill", color: .green, hour: 13, label: "胡萝卜"),
    ]

    /// Dev-only: a few cut-out-style food photos on *today* so the 今日记录 card
    /// demos with content (SF Symbols rendered onto transparency, stickerized
    /// like real captures).
    private func seedSampleFoodIfEmpty() async -> Bool {
        let today = Calendar.current.startOfDay(for: .now)
        guard foodPhotos(on: today).isEmpty else { return false }
        let cal = Calendar.current
        let seeds = await Task.detached(priority: .utility) {
            Self.renderedFoodSeeds()
        }.value
        for seed in seeds {
            let at = cal.date(bySettingHour: seed.hour, minute: 33, second: 0, of: today) ?? today
            addFoodPhoto(pngData: seed.pngData, capturedAt: at, subjectLabel: seed.label)
        }
        return !seeds.isEmpty
    }

    /// Dev-only: re-stamp the seed-slot photos (hour + :33 capture times) on a
    /// seed-version bump so label/border treatment changes land on an already-
    /// seeded container. Rendering is kept off the main actor; real captures
    /// never sit on a seed slot.
    private func upgradeSeededFood() async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let photos = foodPhotos(on: today)
        let seedHours = Set(Self.foodSeedSpecs.map(\.hour))
        guard photos.contains(where: {
            cal.component(.minute, from: $0.capturedAt) == 33
                && seedHours.contains(cal.component(.hour, from: $0.capturedAt))
        }) else { return }

        let renderedByHour = Dictionary(uniqueKeysWithValues: await Task.detached(priority: .utility) {
            Self.renderedFoodSeeds().map { ($0.hour, $0) }
        }.value)
        var changed = false
        for photo in photos {
            let hour = cal.component(.hour, from: photo.capturedAt)
            let minute = cal.component(.minute, from: photo.capturedAt)
            guard minute == 33,
                  let seed = renderedByHour[hour] else { continue }
            photo.pngData = seed.pngData
            photo.subjectLabel = seed.label
            photo.updatedAt = .now
            changed = true
        }
        if changed {
            try? context.save()
            revision += 1
        }
    }

    /// Deterministic hourly distribution of `total` steps: quiet nights, a
    /// commute bump in the morning/evening, a lunch stroll — varied by `seed`.
    private static func seedHourlySteps(total: Int, seed: Int) -> [Int] {
        // Relative weight per hour 0–23.
        let weights: [Double] = (0..<24).map { h in
            switch h {
            case 0..<7:   return 0.05
            case 7..<10:  return 1.6 + Double((seed + h) % 3) * 0.5   // morning peak
            case 12..<14: return 1.1 + Double((seed + h) % 2) * 0.4   // lunch
            case 18..<21: return 1.8 + Double((seed + h) % 3) * 0.6   // evening peak
            default:      return 0.5 + Double((seed + h) % 4) * 0.2
            }
        }
        let sum = weights.reduce(0, +)
        return weights.map { Int(Double(total) * $0 / sum) }
    }

    /// Deterministic stage segments for a seeded night: repeating 浅睡→深睡→浅睡→
    /// 眼动 cycles (~90 min each) trimmed to the night's length.
    private static func seedSleepSegments(start: Date, hours: Double, seed: Int) -> [SleepSegmentValue] {
        let cycle: [(SleepStage, TimeInterval)] = [
            (.core, 35 * 60), (.deep, 30 * 60), (.core, 15 * 60), (.rem, 12 * 60),
        ]
        var segments: [SleepSegmentValue] = []
        var t = start
        let end = start.addingTimeInterval(hours * 3600)
        var i = seed % cycle.count
        while t < end {
            let (stage, base) = cycle[i % cycle.count]
            let dur = min(base + Double((seed + i) % 5) * 120, end.timeIntervalSince(t))
            segments.append(SleepSegmentValue(start: t, end: t.addingTimeInterval(dur), stage: stage))
            t = t.addingTimeInterval(dur)
            i += 1
        }
        return segments
    }

    nonisolated private static func renderedFoodSeeds() -> [RenderedFoodSeed] {
        foodSeedSpecs.compactMap { spec in
            let color: UIColor = switch spec.color {
            case .brown: .systemBrown
            case .darkGray: .darkGray
            case .green: .systemGreen
            }
            guard let data = renderSymbolPNG(spec.symbol, color: color) else { return nil }
            return RenderedFoodSeed(hour: spec.hour, label: spec.label, pngData: data)
        }
    }

    nonisolated private static func renderSymbolPNG(_ name: String, color: UIColor) -> Data? {
        let cfg = UIImage.SymbolConfiguration(pointSize: 120, weight: .regular)
        guard let img = UIImage(systemName: name, withConfiguration: cfg)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
        let size = CGSize(width: 200, height: 200)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: fmt)
        let flat = renderer.image { _ in
            let r = CGRect(x: (size.width - img.size.width) / 2,
                           y: (size.height - img.size.height) / 2,
                           width: img.size.width, height: img.size.height)
            img.draw(in: r)
        }
        // Same 镶嵌边框 treatment as real captures so the card demos faithfully.
        return SubjectCutout.stickerize(flat, border: 7).pngData()
    }
    #endif
}

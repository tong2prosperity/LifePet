import Foundation
import SwiftData
import Observation
import CoreLocation
#if DEBUG
import UIKit
#endif

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
    var sleepSegments: [SleepSegmentValue] = []
    var mindfulMinutes = 0
    var workoutCount = 0
    var workoutMinutes = 0
    var workoutEnergy = 0.0
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
    private(set) var revision = 0

    init(context: ModelContext) {
        self.context = context
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

    /// All records in the calendar month containing `day`.
    func recordsForMonth(containing day: Date) -> [HealthDayRecord] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: day) else { return [] }
        return records(from: interval.start, to: cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end)
    }

    // MARK: Writes

    /// Find-or-create the row for `day` and mutate it. Bumps `revision`.
    @discardableResult
    func upsert(day: Date, configure: (HealthDayRecord) -> Void) -> HealthDayRecord {
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
        try? context.save()
        revision += 1
        return record
    }

    /// Bulk-ingest backfilled HK values. Skips empty days so the calendar
    /// doesn't fill with all-zero placeholder rows.
    func ingest(_ values: [HealthDayValues]) {
        for v in values where v.steps > 0 || v.sleepTotal > 0 || v.activeEnergy > 0 || v.exerciseMinutes > 0 {
            upsertSilently(v)
        }
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
        record.sleepSegments = v.sleepSegments
        record.mindfulMinutes = v.mindfulMinutes
        record.workoutCount = v.workoutCount
        record.workoutMinutes = v.workoutMinutes
        record.workoutEnergy = v.workoutEnergy
        record.updatedAt = .now
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
    func ingestWorkouts(_ values: [WorkoutValues]) {
        let cal = Calendar.current
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
            record.updatedAt = .now
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
    func addFoodPhoto(pngData: Data, capturedAt: Date = .now, subjectLabel: String? = nil,
                      mealType: MealType? = nil) -> FoodPhoto {
        let photo = FoodPhoto(capturedAt: capturedAt, pngData: pngData,
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
    func seedSampleHistoryIfEmpty(days: Int = 35) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard records(from: cal.date(byAdding: .day, value: -days, to: today) ?? today, to: today).isEmpty else { return }
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
        }
        try? context.save()
        revision += 1
    }

    /// Dev-only umbrella: seed days + workouts + food, each guarded independently
    /// so a store half-populated by an older build still gets the missing pieces.
    func seedSampleAllIfEmpty(days: Int = 35) async {
        let today = Calendar.current.startOfDay(for: .now)
        let seedState = "2:\(Int(today.timeIntervalSinceReferenceDate))"
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: PiboPersistenceKeys.Defaults.debugHistorySeedState) != seedState else {
            return
        }

        seedSampleHistoryIfEmpty(days: days)
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
        for r in rows {
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
        ingestWorkouts(seeded)
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

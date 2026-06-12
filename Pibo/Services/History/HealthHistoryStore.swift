import Foundation
import SwiftData
import Observation
#if DEBUG
import UIKit
#endif

/// Plain transport of one day's HealthKit values (Sendable) — produced by
/// `HealthHistoryFetcher` off the main actor, ingested into SwiftData here.
struct HealthDayValues: Sendable {
    var date: Date
    var steps = 0
    var activeEnergy = 0.0
    var exerciseMinutes = 0
    var standMinutes = 0
    var distanceMeters = 0.0
    var flightsClimbed = 0
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
        record.activeEnergy = v.activeEnergy
        record.exerciseMinutes = v.exerciseMinutes
        record.standMinutes = v.standMinutes
        record.distanceMeters = v.distanceMeters
        record.flightsClimbed = v.flightsClimbed
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

    /// Persist a freshly captured (and cut-out) food photo. Bumps `revision`.
    @discardableResult
    func addFoodPhoto(pngData: Data, capturedAt: Date = .now) -> FoodPhoto {
        let photo = FoodPhoto(capturedAt: capturedAt, pngData: pngData)
        context.insert(photo)
        try? context.save()
        revision += 1
        return photo
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
                activeEnergy: Double(180 + (doy * 13) % 420),
                exerciseMinutes: (doy * 5) % 65,
                standMinutes: 120 + (doy % 8) * 30,   // ~2–5 stand-hours when /60
                distanceMeters: Double(steps) * 0.72,
                restingHR: 56 + Double(doy % 12),
                heartRateAvg: 72 + Double(doy % 18),
                hrv: 30 + Double(doy % 45),
                oxygenSaturation: 0.96 + Double(doy % 4) / 100,
                sleepTotal: sleepH * 3600,
                sleepDeep: deep,
                sleepREM: sleepH * 3600 * 0.2,
                sleepStart: sStart,
                sleepEnd: sEnd,
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
    func seedSampleAllIfEmpty(days: Int = 35) {
        seedSampleHistoryIfEmpty(days: days)
        seedSampleWorkoutsIfEmpty(days: days)
        seedSampleFoodIfEmpty()
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

    /// Dev-only: a few cut-out-style food photos on *today* so the 今日记录 card
    /// demos with content (SF Symbols rendered onto transparency).
    private func seedSampleFoodIfEmpty() {
        let today = Calendar.current.startOfDay(for: .now)
        guard foodPhotos(on: today).isEmpty else { return }
        let specs: [(String, UIColor, Int)] = [
            ("birthday.cake.fill", .systemBrown, 9),
            ("cup.and.saucer.fill", .darkGray, 11),
            ("carrot.fill", .systemGreen, 13),
        ]
        let cal = Calendar.current
        for (symbol, color, hour) in specs {
            guard let data = Self.renderSymbolPNG(symbol, color: color) else { continue }
            let at = cal.date(bySettingHour: hour, minute: 33, second: 0, of: today) ?? today
            addFoodPhoto(pngData: data, capturedAt: at)
        }
    }

    private static func renderSymbolPNG(_ name: String, color: UIColor) -> Data? {
        let cfg = UIImage.SymbolConfiguration(pointSize: 120, weight: .regular)
        guard let img = UIImage(systemName: name, withConfiguration: cfg)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
        let size = CGSize(width: 200, height: 200)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: fmt)
        return renderer.image { _ in
            let r = CGRect(x: (size.width - img.size.width) / 2,
                           y: (size.height - img.size.height) / 2,
                           width: img.size.width, height: img.size.height)
            img.draw(in: r)
        }.pngData()
    }
    #endif
}

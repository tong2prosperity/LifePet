import Foundation
import os

/// Bridges the on-device HealthKit pipeline to the server economy. It reads
/// today's persisted `HealthDayRecord` (kept fresh by `HealthDataService` on
/// device, DEBUG-seeded on the simulator), turns it into upload-ready samples,
/// and pushes them through `EconomyService.sync` — the server then
/// authoritatively scores energy and mints bo.
///
/// Why the history store and not raw `HealthEvent`s: the record is the already-
/// windowed daily truth (hourly steps + last-night sleep) and exists on both
/// real devices and the simulator, so the same path demos everywhere. Per-hour
/// step samples carry stable dedup keys, so re-syncing the same day never
/// double-counts (server-side layer-B dedup).
@MainActor
@Observable
final class EconomySyncCoordinator {
    private(set) var lastResult: SyncResponse?
    private(set) var lastError: APIError?

    private let auth: AuthService
    private let economy: EconomyService
    private let history: HealthHistoryStore

    init(auth: AuthService, economy: EconomyService, history: HealthHistoryStore) {
        self.auth = auth
        self.economy = economy
        self.history = history
    }

    /// Builds today's health samples from the persisted record. Only COMPLETE
    /// past hours are sent (stable dedup keys); the in-progress hour is skipped
    /// until it closes.
    func todaySamples(now: Date = .now, calendar: Calendar = .current) -> [HealthSampleDTO] {
        guard let rec = history.record(on: now) else { return [] }
        let startOfDay = calendar.startOfDay(for: now)
        var samples: [HealthSampleDTO] = []

        if !rec.hourlySteps.isEmpty {
            for (hour, count) in rec.hourlySteps.enumerated() where count > 0 {
                guard let hStart = calendar.date(byAdding: .hour, value: hour, to: startOfDay) else { continue }
                let hEnd = hStart.addingTimeInterval(3600)
                if hEnd > now { continue } // skip the in-progress hour
                samples.append(.steps(Double(count), start: hStart, end: hEnd))
            }
        } else if rec.steps > 0 {
            // No hourly breakdown — one day-total sample with a per-day stable key.
            let dayKey = "steps-day-\(Self.dayString(startOfDay))"
            samples.append(HealthSampleDTO(metric: "steps", value: Double(rec.steps), unit: "count",
                                           startTs: startOfDay, endTs: now, dedupKey: dayKey))
        }

        if rec.sleepTotal > 0 {
            let s = rec.sleepStart ?? startOfDay
            let e = rec.sleepEnd ?? s.addingTimeInterval(rec.sleepTotal)
            samples.append(.sleep(seconds: rec.sleepTotal, start: s, end: e))
        }

        return samples
    }

    /// Uploads today's health samples and applies the authoritative result.
    /// No-op (returns nil) when logged out.
    @discardableResult
    func syncToday() async -> SyncResponse? {
        guard auth.phase == .loggedIn else {
            lastError = .unauthorized
            return nil
        }
        let samples = todaySamples()
        LPLog.economySync.debug("syncToday: \(samples.count) samples")
        let resp = await economy.sync(samples: samples)
        lastResult = resp
        lastError = economy.lastError
        return resp
    }

    /// Reports an in-app behaviour event (photo / game / pat) immediately, the
    /// 能量收集 path for non-health energy.
    @discardableResult
    func recordAction(_ actionType: String, eventId: String = UUID().uuidString) async -> SyncResponse? {
        guard auth.phase == .loggedIn else { return nil }
        let resp = await economy.sync(actions: [EconomyActionDTO(eventId: eventId, actionType: actionType)])
        lastResult = resp
        lastError = economy.lastError
        return resp
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    #if DEBUG
    /// Dev-only: stamp today's `HealthDayRecord` with step data in completed
    /// morning hours, so the health→sync→mint path is demonstrable on a
    /// simulator that has no real HealthKit data. Writes the same record the
    /// live `HealthDataService` pipeline would.
    func debugStampTodaySteps(perHour: Int = 3000, hours: ClosedRange<Int> = 6...9) {
        var hourly = Array(repeating: 0, count: 24)
        for h in hours where h >= 0 && h < 24 { hourly[h] = perHour }
        history.upsert(day: .now, origin: .synthetic) { rec in
            rec.steps = hourly.reduce(0, +)
            rec.hourlySteps = hourly
        }
    }
    #endif
}

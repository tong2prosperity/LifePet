import Foundation
import os

/// Relays the local-first ledger between the signed-in user's devices. Core has
/// already scored the on-device HealthKit day before records reach this seam;
/// the server authenticates, stores, deduplicates and pages immutable records,
/// but never becomes the user's local behavior/display source of truth.
@MainActor
@Observable
final class EconomySyncCoordinator {
    private(set) var lastResult: BoLedgerSyncResponse?
    private(set) var lastError: APIError?

    private let auth: AuthService
    private let economy: EconomyService
    private let history: HealthHistoryStore
    private let ledger: BoLedgerStore
    private let ornaments: OrnamentUnlockStore

    init(
        auth: AuthService,
        economy: EconomyService,
        history: HealthHistoryStore,
        ledger: BoLedgerStore,
        ornaments: OrnamentUnlockStore
    ) {
        self.auth = auth
        self.economy = economy
        self.history = history
        self.ledger = ledger
        self.ornaments = ornaments
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

    /// Uploads the frozen local batch, applies monotonic Core-backed merges and
    /// pages at most eight responses. No-op (returns nil) when logged out.
    @discardableResult
    func syncToday() async -> BoLedgerSyncResponse? {
        guard auth.phase == .loggedIn else {
            lastError = .unauthorized
            return nil
        }
        var latest: BoLedgerSyncResponse?
        for page in 0..<8 {
            let request = ledger.syncRequest()
            let uploadCount = request.healthRecords.count
                + request.domainEvents.count
                + request.ledgerEvents.count
            LPLog.economySync.debug(
                "ledger sync page=\(page + 1) upload=\(uploadCount) cursor=\(request.cursor)"
            )
            guard let response = await economy.syncLedger(request) else {
                lastError = economy.lastError
                return latest
            }
            latest = response
            lastResult = response
            let bitmask = ledger.acknowledgeSync(response)
            ornaments.reconcileUnlockedBitmask(bitmask)
            if !response.hasMore, !ledger.hasPendingSyncRecords() { break }
        }
        lastError = nil
        return latest
    }

    /// Reports an in-app behaviour event (photo / game / pat) immediately, the
    /// 能量收集 path for non-health energy.
    @discardableResult
    func recordAction(_ actionType: String, eventId: String = UUID().uuidString) async -> SyncResponse? {
        guard auth.phase == .loggedIn else { return nil }
        let resp = await economy.sync(actions: [EconomyActionDTO(eventId: eventId, actionType: actionType)])
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

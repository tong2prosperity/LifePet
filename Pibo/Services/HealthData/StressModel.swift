import Foundation
import SwiftUI

/// Four-tier stress classification, mirroring StressWatch's 优秀 / 正常 / 注意 /
/// 超载. Derived from Pibo-computed RMSSD (see `HeartbeatSeriesReader`) relative
/// to the wearer's own baseline — **not** from Apple's SDNN.
enum StressLevel: Int, CaseIterable, Sendable {
    case excellent   // 优秀
    case normal      // 正常
    case notice      // 注意
    case overload    // 超载

    var displayName: String {
        switch self {
        case .excellent: return "优秀"
        case .normal:    return "正常"
        case .notice:    return "注意"
        case .overload:  return "超载"
        }
    }

    /// Whether this tier warrants a push (注意 / 超载).
    var isElevated: Bool { self == .notice || self == .overload }

    var tint: Color {
        switch self {
        case .excellent: return LP.Colorful.green500
        case .normal:    return LP.Colorful.blue500
        case .notice:    return LP.Colorful.orange500
        case .overload:  return LP.Colorful.red500
        }
    }

    var bg: Color {
        switch self {
        case .excellent: return LP.Colorful.green100
        case .normal:    return LP.Colorful.blue100
        case .notice:    return LP.Colorful.orange100
        case .overload:  return LP.Colorful.red100
        }
    }

    /// In-card explanation stays with the measured signal. One HRV reading is
    /// not enough to infer the user's emotions or make Pibo physically suffer.
    var caption: String {
        switch self {
        case .excellent: return "stress.caption.excellent"
        case .normal:    return "stress.caption.normal"
        case .notice:    return "stress.caption.notice"
        case .overload:  return "stress.caption.overload"
        }
    }

    /// Push body copy (注意 / 超载 only fire).
    var notificationBody: String {
        switch self {
        case .notice:   return "stress.notification.notice"
        case .overload: return "stress.notification.overload"
        default:        return ""
        }
    }
}

enum StressModel {
    /// Classify current stress from RMSSD against the wearer's personal baseline
    /// via the unified `StressScore.anchor`. Before seven eligible natural days,
    /// no tier is returned. Once ready, resting HR may nudge the personal tier
    /// toward stress. Lower RMSSD = more stress.
    static func level(rmssd: Double, baseline: StressBaseline?, restingHR: Double) -> StressLevel? {
        PiboCoreStressAdapter.level(
            rmssd: rmssd,
            baseline: baseline,
            restingHR: restingHR
        )
    }
}

/// Platform timestamp checks around the shared Core freshness window. A future
/// timestamp is invalid acquisition metadata, not a zero-age measurement: it
/// may remain visible in the log, but it cannot be classified or notified even
/// when the diagnostic every-reading mode is enabled.
enum StressSampleTiming {
    static func age(measuredAt: Date, now: Date = Date()) -> TimeInterval? {
        let value = now.timeIntervalSince(measuredAt)
        return value.isFinite && value >= 0 ? value : nil
    }

    static func isFresh(measuredAt: Date, now: Date = Date()) -> Bool {
        guard let age = age(measuredAt: measuredAt, now: now) else { return false }
        return age <= DerivedStressModel.maxAnchorAge
    }

    static func shouldAttemptNotification(
        measuredAt: Date,
        now: Date = Date(),
        everyReading: Bool
    ) -> Bool {
        guard age(measuredAt: measuredAt, now: now) != nil else { return false }
        return everyReading || isFresh(measuredAt: measuredAt, now: now)
    }
}

/// N=2 confirmation hysteresis for the **notification** tier only (the display
/// card still reacts to every reading). A single ~1-min RMSSD series is noisy,
/// so a lone spike/dip must not move the alert tier: a tier change takes effect
/// only once **two consecutive readings agree** on it; until then the last
/// *confirmed* tier holds. The very first reading is adopted as-is (nothing to
/// confirm against). Cost: a genuine change is delayed by one reading (~one HRV
/// cadence, 2–5h) — acceptable for a gentle nudge, not a medical alarm.
///
/// State is App-Group-persisted so the confirmation survives background wakes.
/// `confirm(_:)` is called once per reading in `postStress` — always, so the
/// stream stays tracked even while the diagnostic every-reading mode is on.
enum StressHysteresis {
    private static let rawKey = "pibo.stress.hyst.raw.v1"
    private static let confirmedKey = "pibo.stress.hyst.confirmed.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PiboWidgetConstants.appGroupID) ?? .standard
    }

    /// Fold a freshly-classified tier into the confirmation stream and return the
    /// tier the notifier should act on.
    static func confirm(_ raw: StressLevel) -> StressLevel {
        let lastRaw = (defaults.object(forKey: rawKey) as? Int)
            .flatMap(StressLevel.init(rawValue:))
        let lastConfirmed = (defaults.object(forKey: confirmedKey) as? Int)
            .flatMap(StressLevel.init(rawValue:))
        // Two consecutive readings agree → adopt; otherwise hold the last confirmed.
        let confirmed = PiboCoreStressAdapter.confirmedLevel(
            raw: raw,
            lastRaw: lastRaw,
            lastConfirmed: lastConfirmed
        )
        defaults.set(raw.rawValue, forKey: rawKey)
        defaults.set(confirmed.rawValue, forKey: confirmedKey)
        return confirmed
    }

    static func reset() {
        defaults.removeObject(forKey: rawKey)
        defaults.removeObject(forKey: confirmedKey)
    }
}

/// The wearer's personal RMSSD baseline, built by **daily aggregation** and
/// persisted in the App Group so a value computed during a background HealthKit
/// wake and the foreground 压力卡 read the same window.
///
/// Why per-day, not per-reading: HRV's meaningful variation is day-to-day, and
/// same-day readings are highly correlated. Feeding raw readings would let a
/// burst of readings on one busy day dominate (and shrink σ artificially). So we
/// collapse each day's resting readings to a **median**, and the baseline stats
/// (`StressBaseline`: ln-mean / ln-SD / dayCount) come from those daily medians.
///
/// Two layers:
/// - `todayKey` — today's still-accumulating resting readings (not yet a median).
/// - `dailyKey` — finalized `{date, median}` for each past day (capped ~60d).
///
/// The baseline is computed from the **daily list only** (excludes today), which
/// both matches "judge today against your prior normal" and removes the earlier
/// self-inclusion bias. Only **resting** readings enter — active-time HRV is
/// naturally low and would poison the baseline.
enum StressBaselineStore {
    /// **v5 = Lipponen–Tarvainen corrected NN-RMSSD.** This version had not
    /// shipped before the algorithm was finalized, so v5 can keep its name while
    /// restarting every older baseline.
    ///
    /// The keys are versioned alongside the RMSSD algorithm and old values are
    /// *not* migrated. A baseline is only meaningful against readings produced the
    /// same way, and each revision has moved the level in one direction:
    ///
    /// - v2 filtered on the successive difference itself and ran systematically
    ///   **low**; scoring a v3 reading against it read as a permanent rise in HRV
    ///   and parked everyone at 优秀.
    /// - v3's flat 250 ms threshold let a moderate mis-detected beat survive, and
    ///   one such beat can nearly double a quiet wearer's RMSSD — so v3 ran
    ///   sporadically **high**. Scoring a v4 reading against it is the same error
    ///   mirrored: a permanent apparent *drop*, i.e. weeks parked at 注意/超载.
    /// - v4 applied an earlier adaptive artifact filter. Corrected v5 readings
    ///   are not comparable to those medians, so the personal baseline restarts.
    ///
    /// Until seven eligible natural days exist, readings remain visible but do
    /// not receive a stress tier. Rescaling old medians would need a conversion
    /// factor we cannot know for each historical window.
    private static let todayKey = "pibo.stress.today.v5"
    private static let dailyKey = "pibo.stress.daily.v5"
    private static let historicalReadingsKey = "pibo.stress.historical.v5"
    private static let legacyKeys = [
        "pibo.stress.rmssd.window.v1",
        "pibo.stress.today.v2",
        "pibo.stress.daily.v2",
        "pibo.stress.today.v3",
        "pibo.stress.daily.v3",
        "pibo.stress.today.v4",
        "pibo.stress.daily.v4",
    ]
    /// Keep ~two months of daily medians.
    private static let maxDays = 60
    private static let maxHistoricalReadings = 512

    private struct TodayBucket: Codable {
        var dayStart: Date
        var values: [Double]
        /// Series already folded into this open day. Optional keeps decoding
        /// buckets written before series-level idempotency was added.
        var seriesIDs: [UUID]?
    }
    private struct DailyValue: Codable { var date: Date; var median: Double }
    private struct HistoricalReading: Codable {
        var seriesID: UUID
        var date: Date
        var rmssd: Double
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PiboWidgetConstants.appGroupID) ?? .standard
    }

    /// Fold a reading into the daily aggregation and return the current baseline
    /// (computed from *past* days — this reading's day is still open). Non-resting
    /// readings are ignored for the baseline (they still get logged for display).
    @discardableResult
    static func record(
        rmssd: Double,
        isEligible: Bool,
        date: Date = Date(),
        now: Date = Date(),
        seriesID: UUID? = nil
    ) -> StressBaseline? {
        guard rmssd.isFinite, rmssd > 0, isEligible,
              date.timeIntervalSinceReferenceDate.isFinite,
              now.timeIntervalSinceReferenceDate.isFinite,
              date <= now
        else { return baseline(at: now) }
        let currentDayStart = Calendar.current.startOfDay(for: now)
        let dayStart = Calendar.current.startOfDay(for: date)
        // Only a sample genuinely measured today may update today's open bucket.
        // Stale catch-up samples and future-dated/corrupt samples remain visible
        // in the log but cannot manufacture or prematurely finalize baseline days.
        guard dayStart == currentDayStart else { return baseline(at: now) }
        var bucket = loadToday()
        if let existing = bucket, existing.dayStart != dayStart {
            // Finalize only a genuine forward rollover. A persisted future bucket
            // (for example after a clock rollback) is discarded, never promoted
            // into the daily reference window.
            if existing.dayStart < dayStart { finalize(existing) }
            bucket = nil
        }
        var today = bucket ?? TodayBucket(dayStart: dayStart, values: [], seriesIDs: [])
        if let seriesID, today.seriesIDs?.contains(seriesID) == true {
            return baseline(at: now)
        }
        today.values.append(rmssd)
        if let seriesID {
            var ids = today.seriesIDs ?? []
            ids.append(seriesID)
            today.seriesIDs = ids
        }
        saveToday(today)
        return baseline(at: now)
    }

    /// Personal baseline over the finalized daily medians (excludes today).
    static var baseline: StressBaseline? { baseline(at: Date()) }

    /// Merge eligible past HealthKit series into their natural-day medians.
    /// Raw values retain the immutable series UUID, making retries idempotent and
    /// allowing a later coalesced delivery to recompute the real median instead
    /// of taking a statistically incorrect "median of medians".
    @discardableResult
    static func backfill(
        _ readings: [(seriesID: UUID, rmssd: Double, date: Date)],
        now: Date = Date()
    ) -> StressBaseline? {
        guard now.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -maxDays, to: today) ?? .distantPast
        let valid = readings.filter {
            $0.rmssd.isFinite && $0.rmssd > 0
                && $0.date.timeIntervalSinceReferenceDate.isFinite
                && $0.date >= cutoff
                && $0.date < today
        }
        guard !valid.isEmpty else { return baseline(at: now) }

        var historical = loadHistoricalReadings().filter {
            $0.date >= cutoff && $0.date < today && $0.rmssd.isFinite && $0.rmssd > 0
        }
        for reading in valid {
            historical.removeAll { $0.seriesID == reading.seriesID }
            historical.append(HistoricalReading(
                seriesID: reading.seriesID,
                date: reading.date,
                rmssd: reading.rmssd
            ))
        }
        historical.sort { $0.date < $1.date }
        if historical.count > maxHistoricalReadings {
            historical.removeFirst(historical.count - maxHistoricalReadings)
        }
        saveHistoricalReadings(historical)

        let affectedDays = Set(valid.map { calendar.startOfDay(for: $0.date) })
        var daily = loadDaily().filter { !affectedDays.contains($0.date) }
        for day in affectedDays {
            let values = historical.compactMap { reading -> Double? in
                calendar.startOfDay(for: reading.date) == day ? reading.rmssd : nil
            }
            let value = median(values)
            if value > 0 { daily.append(DailyValue(date: day, median: value)) }
        }
        daily.sort { $0.date < $1.date }
        if daily.count > maxDays { daily.removeFirst(daily.count - maxDays) }
        saveDaily(daily)
        return baseline(at: now)
    }

    private static func baseline(at now: Date) -> StressBaseline? {
        guard now.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let today = Calendar.current.startOfDay(for: now)
        if let bucket = loadToday(),
           (!bucket.dayStart.timeIntervalSinceReferenceDate.isFinite || bucket.dayStart > today) {
            defaults.removeObject(forKey: todayKey)
        }
        let storedDays = loadDaily()
        let validPastDays = storedDays.filter {
            $0.date.timeIntervalSinceReferenceDate.isFinite
                && $0.date < today
                && $0.median.isFinite
                && $0.median > 0
        }
        if validPastDays.count != storedDays.count { saveDaily(validPastDays) }
        return stats(of: validPastDays)
    }

    /// That day's median resting RMSSD, if it has been finalized. This is the
    /// only per-day RMSSD the app keeps — `HealthDayRecord` persists Apple's
    /// SDNN, which is a different metric and not interchangeable — so it is what
    /// the 体征 card reads for past days. `nil` for today (its bucket is still
    /// open, so the live reading is the right source) and for any day with no
    /// resting reading.
    static func dailyMedian(for date: Date) -> Double? {
        let dayStart = Calendar.current.startOfDay(for: date)
        return loadDaily().first { $0.date == dayStart }?.median
    }

    static func reset() {
        defaults.removeObject(forKey: todayKey)
        defaults.removeObject(forKey: dailyKey)
        defaults.removeObject(forKey: historicalReadingsKey)
        legacyKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    // MARK: - Aggregation

    private static func finalize(_ bucket: TodayBucket) {
        let m = median(bucket.values)
        guard bucket.dayStart.timeIntervalSinceReferenceDate.isFinite,
              m.isFinite, m > 0 else { return }
        var daily = loadDaily().filter { $0.date != bucket.dayStart }
        daily.append(DailyValue(date: bucket.dayStart, median: m))
        daily.sort { $0.date < $1.date }
        if daily.count > maxDays { daily.removeFirst(daily.count - maxDays) }
        saveDaily(daily)
    }

    /// ln-mean / ln-SD / dayCount over the daily medians. SD needs ≥2 days;
    /// with fewer, `sdLn` is 0 and `StressScore` stays on the cold-start branch.
    private static func stats(of daily: [DailyValue]) -> StressBaseline? {
        PiboCoreStressAdapter.baseline(dailyMedians: daily.map(\.median))
    }

    private static func median(_ xs: [Double]) -> Double {
        let s = xs.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !s.isEmpty else { return 0 }
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    // MARK: - Persistence

    private static func loadToday() -> TodayBucket? {
        guard let data = defaults.data(forKey: todayKey) else { return nil }
        return try? JSONDecoder().decode(TodayBucket.self, from: data)
    }
    private static func saveToday(_ b: TodayBucket) {
        guard let data = try? JSONEncoder().encode(b) else { return }
        defaults.set(data, forKey: todayKey)
    }
    private static func loadDaily() -> [DailyValue] {
        guard let data = defaults.data(forKey: dailyKey),
              let decoded = try? JSONDecoder().decode([DailyValue].self, from: data)
        else { return [] }
        return decoded
    }
    private static func saveDaily(_ list: [DailyValue]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: dailyKey)
    }
    private static func loadHistoricalReadings() -> [HistoricalReading] {
        guard let data = defaults.data(forKey: historicalReadingsKey),
              let decoded = try? JSONDecoder().decode([HistoricalReading].self, from: data)
        else { return [] }
        return decoded
    }
    private static func saveHistoricalReadings(_ list: [HistoricalReading]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: historicalReadingsKey)
    }

    #if DEBUG
    /// Seed a full personal baseline (15 distinct past days) so the 压力卡 renders
    /// in the "全个人化" regime on the simulator (no heartbeat series there).
    /// No-op once any daily value exists.
    static func seedIfEmpty() {
        guard loadDaily().isEmpty else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Plausible resting RMSSD medians ~46ms with natural day-to-day spread.
        let medians: [Double] = [44, 48, 46, 52, 41, 49, 45, 47, 43, 50, 46, 44, 51, 45, 48]
        var daily: [DailyValue] = []
        for (i, m) in medians.enumerated() {
            let d = cal.date(byAdding: .day, value: -(medians.count - i), to: today) ?? today
            daily.append(DailyValue(date: d, median: m))
        }
        saveDaily(daily)
    }
    #endif
}

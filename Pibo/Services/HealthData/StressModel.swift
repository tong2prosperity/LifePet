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

    /// In-card one-liner. Tone: 傲娇不卖惨 (per Pibo spec).
    var caption: String {
        switch self {
        case .excellent: return "心跳稳稳的，花也精神……算你今天还行。"
        case .normal:    return "还行吧，别得意。"
        case .notice:    return "心跳有点乱……花好像也蔫了一点。"
        case .overload:  return "别撑了，你这样花会谢的……才不是我担心。"
        }
    }

    /// Push body copy (注意 / 超载 only fire).
    var notificationBody: String {
        switch self {
        case .notice:   return "花有点蔫了……歇会儿。才不是我在乎你。"
        case .overload: return "你再这样花就要谢了，喘口气去。"
        default:        return ""
        }
    }
}

enum StressModel {
    /// Classify current stress from RMSSD against the wearer's personal baseline
    /// via the unified `StressScore.anchor` (z-score once enough days accumulate,
    /// population thresholds before that), then nudge one tier toward stress when
    /// resting HR runs high. Lower RMSSD = more stress.
    static func level(rmssd: Double, baseline: StressBaseline?, restingHR: Double) -> StressLevel {
        guard rmssd > 0, let score = StressScore.anchor(rmssd: rmssd, baseline: baseline) else {
            return .normal
        }
        var level = StressScore.tier(for: score)
        // Elevated resting HR bumps one tier toward stress.
        if restingHR >= 80, level != .overload {
            level = StressLevel(rawValue: level.rawValue + 1) ?? .overload
        }
        return level
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
            .flatMap(StressLevel.init(rawValue:)) ?? raw
        // Two consecutive readings agree → adopt; otherwise hold the last confirmed.
        let confirmed = (lastRaw == raw) ? raw : lastConfirmed
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
    private static let todayKey = "pibo.stress.today.v2"
    private static let dailyKey = "pibo.stress.daily.v2"
    private static let legacyKey = "pibo.stress.rmssd.window.v1"
    /// Keep ~two months of daily medians.
    private static let maxDays = 60

    private struct TodayBucket: Codable { var dayStart: Date; var values: [Double] }
    private struct DailyValue: Codable { var date: Date; var median: Double }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PiboWidgetConstants.appGroupID) ?? .standard
    }

    /// Fold a reading into the daily aggregation and return the current baseline
    /// (computed from *past* days — this reading's day is still open). Non-resting
    /// readings are ignored for the baseline (they still get logged for display).
    @discardableResult
    static func record(rmssd: Double, isResting: Bool, date: Date = Date()) -> StressBaseline? {
        guard rmssd > 0, isResting else { return baseline }
        let dayStart = Calendar.current.startOfDay(for: date)
        // Drop readings dated **before today**. `latestSample` returns the newest
        // series across all time, so a cold-launch / background catch-up can carry
        // last night's series with yesterday's date. Letting it in would either
        // prematurely finalize today's in-progress bucket or inject a single-sample
        // historical day — both skew σ. Baseline aggregates fresh, same-day data.
        guard dayStart >= Calendar.current.startOfDay(for: Date()) else { return baseline }
        var bucket = loadToday()
        if let existing = bucket, existing.dayStart != dayStart {
            // Genuine day rollover (bucket is a full previous day) — finalize it.
            finalize(existing)
            bucket = nil
        }
        var today = bucket ?? TodayBucket(dayStart: dayStart, values: [])
        today.values.append(rmssd)
        saveToday(today)
        return baseline
    }

    /// Personal baseline over the finalized daily medians (excludes today).
    static var baseline: StressBaseline? { stats(of: loadDaily()) }

    static func reset() {
        defaults.removeObject(forKey: todayKey)
        defaults.removeObject(forKey: dailyKey)
        defaults.removeObject(forKey: legacyKey)
    }

    // MARK: - Aggregation

    private static func finalize(_ bucket: TodayBucket) {
        let m = median(bucket.values)
        guard m > 0 else { return }
        var daily = loadDaily().filter { $0.date != bucket.dayStart }
        daily.append(DailyValue(date: bucket.dayStart, median: m))
        daily.sort { $0.date < $1.date }
        if daily.count > maxDays { daily.removeFirst(daily.count - maxDays) }
        saveDaily(daily)
    }

    /// ln-mean / ln-SD / dayCount over the daily medians. SD needs ≥2 days;
    /// with fewer, `sdLn` is 0 and `StressScore` stays on the cold-start branch.
    private static func stats(of daily: [DailyValue]) -> StressBaseline? {
        let medians = daily.map(\.median).filter { $0 > 0 }
        guard !medians.isEmpty else { return nil }
        let lns = medians.map { Foundation.log($0) }
        let meanLn = lns.reduce(0, +) / Double(lns.count)
        let sdLn: Double
        if lns.count >= 2 {
            let variance = lns.map { ($0 - meanLn) * ($0 - meanLn) }.reduce(0, +) / Double(lns.count - 1)
            sdLn = max(variance.squareRoot(), 0.05)
        } else {
            sdLn = 0
        }
        return StressBaseline(meanLn: meanLn, sdLn: sdLn, dayCount: lns.count, geoMean: exp(meanLn))
    }

    private static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
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

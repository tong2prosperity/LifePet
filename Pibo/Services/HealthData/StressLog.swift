import Foundation

/// One persisted stress computation — a single RMSSD read from a heartbeat
/// series, its resolved tier, and whether it fired a notification. The user can
/// browse these (设置 →「压力测量记录」) to confirm the background computation is
/// actually running, even on days no push ever fires.
struct StressReading: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    var date: Date
    var rmssd: Double
    /// Geometric mean of the personal baseline at the time (你的常态 ≈ X ms).
    /// `nil` before any baseline exists.
    var baseline: Double?
    var levelRaw: Int
    /// Whether this reading fired a local notification.
    var notified: Bool
    /// Where the reading came from — a real heartbeat-series wake vs. a DEBUG
    /// injection — so the log view can label synthetic rows honestly.
    var synthetic: Bool
    /// z-distance from the personal mean (ln scale). `nil` in cold start (still
    /// on population thresholds) — so the UI can honestly say "个人化中".
    var z: Double?
    /// Distinct days the baseline covered when this was classified.
    var dayCount: Int?
    /// Whether the reading was at rest (entered the baseline). `nil` = legacy row.
    var isResting: Bool?
    /// True when a heartbeat series **was** measured but its window failed the
    /// quality gates (too many artifacts, too few usable differences), so no
    /// RMSSD was produced. `nil`/false = a real reading.
    ///
    /// These rows exist because this log's entire job is answering "到底有没有在
    /// 算". Omitting a rejected window would make a noisy-data user see an empty
    /// list and conclude nothing runs — the exact wrong conclusion, drawn from the
    /// exact screen built to prevent it.
    var skipped: Bool?

    var level: StressLevel { StressLevel(rawValue: levelRaw) ?? .normal }

    /// True when the window was measured but rejected — no usable RMSSD.
    var isSkipped: Bool { skipped == true }

    /// True once the baseline drove the tier via personal z-score (vs. cold-start
    /// population thresholds).
    var isPersonalized: Bool { z != nil }
}

/// Rolling log of stress computations, persisted in the App Group so a reading
/// computed during a **background** HealthKit wake and the foreground log view
/// share the same list. Bounded — we only keep the most recent readings.
enum StressLogStore {
    private static let key = "pibo.stress.log.v1"
    private static let lastSeriesKey = "pibo.stress.lastSeries.v1"
    private static let maxCount = 80

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PiboWidgetConstants.appGroupID) ?? .standard
    }

    /// UUID of the last heartbeat series that was folded into the baseline + log.
    /// Persisted in the App Group so the dedup survives a background-wake process
    /// being killed before the user next foregrounds: an in-memory guard alone
    /// would let the foreground `reconcile()` re-fetch and re-record the very
    /// same series (over-weighting it in the day's baseline median and appending
    /// a duplicate log row). Read/written from the MainActor only.
    static var lastProcessedSeriesID: UUID? {
        get { defaults.string(forKey: lastSeriesKey).flatMap(UUID.init) }
        set {
            if let newValue { defaults.set(newValue.uuidString, forKey: lastSeriesKey) }
            else { defaults.removeObject(forKey: lastSeriesKey) }
        }
    }

    /// Append a computation, trim to the last `maxCount`, return the stored row.
    @discardableResult
    static func record(rmssd: Double,
                       baseline: StressBaseline?,
                       level: StressLevel,
                       notified: Bool,
                       isResting: Bool = true,
                       date: Date = Date(),
                       synthetic: Bool = false) -> StressReading {
        // Surface the personal z only once past cold-start (else the row honestly
        // reads as "个人化中 · 暂用通用阈值").
        let personalized = (baseline?.dayCount ?? 0) >= StressScore.coldStartDays
            && (baseline?.sdLn ?? 0) > 0
        let reading = StressReading(
            id: UUID(),
            date: date,
            rmssd: rmssd,
            baseline: baseline?.geoMean,
            levelRaw: level.rawValue,
            notified: notified,
            synthetic: synthetic,
            z: personalized ? baseline?.z(for: rmssd) : nil,
            dayCount: baseline?.dayCount,
            isResting: isResting)
        var list = entries
        list.append(reading)
        if list.count > maxCount { list.removeFirst(list.count - maxCount) }
        persist(list)
        return reading
    }

    /// Newest first.
    static var entries: [StressReading] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([StressReading].self, from: data)
        else { return [] }
        return decoded.sorted { $0.date > $1.date }
    }

    /// Record that a heartbeat series was measured but rejected by the quality
    /// gates. Carries no RMSSD — there isn't one — but keeps the log's count of
    /// "how often did Pibo actually run" honest.
    static func recordSkipped(date: Date = Date()) {
        let reading = StressReading(
            id: UUID(),
            date: date,
            rmssd: 0,
            baseline: nil,
            levelRaw: StressLevel.normal.rawValue,
            notified: false,
            synthetic: false,
            z: nil,
            dayCount: nil,
            isResting: nil,
            skipped: true)
        var list = entries
        list.append(reading)
        if list.count > maxCount { list.removeFirst(list.count - maxCount) }
        persist(list)
    }

    static func reset() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: lastSeriesKey)
    }

    private static func persist(_ list: [StressReading]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: key)
    }

    #if DEBUG
    /// Seed a handful of plausible rows so the log view demonstrates on the
    /// simulator (which never produces a heartbeat series). No-op once any real
    /// or seeded row exists.
    static func seedIfEmpty() {
        guard entries.isEmpty else { return }
        let now = Date()
        let seed: [(mins: Double, rmssd: Double, level: StressLevel, notified: Bool)] = [
            (30,   44, .normal,    false),
            (180,  22, .notice,    true),
            (200,  13, .overload,  true),
            (260,  40, .normal,    true),   // 恢复
            (600,  54, .excellent, true),   // 优秀
        ]
        var list: [StressReading] = seed.map { s in
            StressReading(id: UUID(),
                          date: now.addingTimeInterval(-s.mins * 60),
                          rmssd: s.rmssd,
                          baseline: 46,
                          levelRaw: s.level.rawValue,
                          notified: s.notified,
                          synthetic: true,
                          z: (Foundation.log(s.rmssd / 46.0)) / 0.08,
                          dayCount: 15,
                          isResting: true)
        }
        list.sort { $0.date < $1.date }
        persist(list)
    }
    #endif
}

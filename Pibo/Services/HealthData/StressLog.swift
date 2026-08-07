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
    /// Absent while building the seven-day reference or when this measurement
    /// is record-only.
    var levelRaw: Int?
    /// Whether this reading fired a local notification.
    var notified: Bool
    /// Where the reading came from — a real heartbeat-series wake vs. a DEBUG
    /// injection — so the log view can label synthetic rows honestly.
    var synthetic: Bool
    /// z-distance from the personal mean (ln scale). `nil` during cold start or
    /// for a record-only measurement.
    var z: Double?
    /// Distinct days the baseline covered when this was classified.
    var dayCount: Int?
    /// Whether the reading was at rest (entered the baseline). `nil` = legacy row.
    var isResting: Bool?
    /// Apple-only local evidence for the corrected NN-RMSSD calculation.
    var rawRMSSD: Double?
    var durationSeconds: Double?
    var nnCount: Int?
    var correctionCount: Int?
    var correctionRate: Double?
    var measurementEligible: Bool?
    var contextEligible: Bool?
    var sourceRaw: String?
    /// Stable HealthKit identity. New rows use this to make a retry idempotent if
    /// the process was interrupted after persistence but before the processed-ID
    /// checkpoint was written.
    var seriesID: UUID? = nil
    /// Continuous personalized Core score (0 calm...1 tense). Optional keeps
    /// old persisted rows and pre-baseline readings valid without inventing a
    /// population score.
    var stressScore: Double? = nil

    var level: StressLevel? { levelRaw.flatMap(StressLevel.init(rawValue:)) }
    var source: StressMeasurementSource {
        sourceRaw.flatMap(StressMeasurementSource.init(rawValue:)) ?? .correctedNN
    }
    var interpretationEligible: Bool {
        (measurementEligible ?? true) && (contextEligible ?? isResting ?? true)
    }

    /// True once a ready personal baseline drove the tier via z-score.
    var isPersonalized: Bool { z != nil }
}

enum StressMeasurementSource: String, Codable, Sendable {
    case correctedNN
    case platformComputed
}

/// Rolling log of stress computations, persisted in the App Group so a reading
/// computed during a **background** HealthKit wake and the foreground log view
/// share the same list. Bounded — we only keep the most recent readings.
enum StressLogStore {
    /// v2 starts a clean log for the corrected NN-RMSSD algorithm. It also gives the
    /// newest series a chance to be recomputed instead of inheriting v1's
    /// quality-gate decision.
    private static let key = "pibo.stress.log.v2"
    private static let lastSeriesKey = "pibo.stress.lastSeries.v2"
    private static let processedSeriesKey = "pibo.stress.processedSeries.v2"
    private static let legacyKey = "pibo.stress.log.v1"
    private static let legacyLastSeriesKey = "pibo.stress.lastSeries.v1"
    private static let maxCount = 80
    private static let maxProcessedSeries = 512

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

    static func hasProcessedSeries(_ id: UUID) -> Bool {
        if lastProcessedSeriesID == id { return true }
        return processedSeriesIDs.contains(id)
    }

    static func markProcessedSeries(_ id: UUID) {
        var ids = processedSeriesIDs.filter { $0 != id }
        ids.append(id)
        if ids.count > maxProcessedSeries {
            ids.removeFirst(ids.count - maxProcessedSeries)
        }
        if let data = try? JSONEncoder().encode(ids) {
            defaults.set(data, forKey: processedSeriesKey)
        }
        lastProcessedSeriesID = id
    }

    private static var processedSeriesIDs: [UUID] {
        guard let data = defaults.data(forKey: processedSeriesKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data)
        else { return [] }
        return ids
    }

    /// Append a computation, trim to the last `maxCount`, return the stored row.
    @discardableResult
    static func record(rmssd: Double,
                       baseline: StressBaseline?,
                       level: StressLevel?,
                       notified: Bool,
                       isResting: Bool = true,
                       date: Date = Date(),
                       synthetic: Bool = false,
                       measurement: HRVAnalysis.Measurement? = nil,
                       measurementEligible: Bool? = nil,
                       source: StressMeasurementSource = .correctedNN,
                       seriesID: UUID? = nil) -> StressReading {
        // Surface the personal z only once the seven-day reference is ready.
        let evidenceEligible = measurementEligible ?? measurement?.canUpdateTrends ?? isResting
        let interpretationEligible = evidenceEligible && isResting
        let personalized = interpretationEligible
            && level != nil
            && (baseline?.dayCount ?? 0) >= StressScore.coldStartDays
            && (baseline?.sdLn ?? 0) > 0
        let reading = StressReading(
            id: UUID(),
            date: date,
            rmssd: rmssd,
            baseline: baseline?.geoMean,
            levelRaw: level?.rawValue,
            notified: notified,
            synthetic: synthetic,
            z: personalized ? baseline?.z(for: rmssd) : nil,
            dayCount: baseline?.dayCount,
            isResting: isResting,
            rawRMSSD: measurement?.rawRMSSD,
            durationSeconds: measurement?.durationSeconds,
            nnCount: measurement?.nnCount,
            correctionCount: measurement?.corrections.total,
            correctionRate: measurement?.correctionRate,
            measurementEligible: evidenceEligible,
            contextEligible: isResting,
            sourceRaw: source.rawValue,
            seriesID: seriesID,
            stressScore: interpretationEligible
                ? StressScore.anchor(rmssd: rmssd, baseline: baseline)
                : nil)
        // `entries` is newest-first for UI consumption. Normalize before
        // trimming so exceeding the cap removes the oldest row, never the
        // newest measurement that was just appended.
        var list = entries.sorted { $0.date < $1.date }
        if let seriesID,
           let index = list.firstIndex(where: { $0.seriesID == seriesID }) {
            list[index] = reading
        } else {
            list.append(reading)
        }
        list.sort { $0.date < $1.date }
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

    static func reset() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: lastSeriesKey)
        defaults.removeObject(forKey: processedSeriesKey)
        defaults.removeObject(forKey: legacyKey)
        defaults.removeObject(forKey: legacyLastSeriesKey)
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
                          isResting: true,
                          rawRMSSD: s.rmssd,
                          durationSeconds: 65,
                          nnCount: 64,
                          correctionCount: 0,
                          correctionRate: 0,
                          measurementEligible: true,
                          contextEligible: true,
                          sourceRaw: StressMeasurementSource.correctedNN.rawValue)
        }
        list.sort { $0.date < $1.date }
        persist(list)
    }
    #endif
}

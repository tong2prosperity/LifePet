import Foundation

/// One night as the shared sleep detail sheet renders it. Built either from a
/// persisted history day or from a morning summary; the sheet never reads
/// anything else, so history and the morning card cannot disagree.
///
/// Presentation-only: durations and percentages of intervals actually drawn.
/// This is not a sleep classifier and applies no health thresholds.
struct SleepNightDetail: Equatable {
    let wakeDay: Date
    /// Fall-asleep time. Never derived from a total.
    let start: Date?
    /// Wake time. Never derived as `start + net sleep`.
    let end: Date?
    let total: TimeInterval
    let segments: [SleepSegmentValue]
    let sleepInBed: TimeInterval?
    let sleepLatency: TimeInterval?
    /// Wake count reported by the data provider. HealthKit has no such fact,
    /// so on iOS this stays `nil`; locally inferred counts are never shown here.
    let providerAwakeningCount: Int?
    /// Whether the night body fields below were measured inside the sleep
    /// window. Summaries cached before the flag existed are `false` and show
    /// 未记录 rather than risk presenting a daytime value as a night value.
    let nightSignalsScoped: Bool
    let sleepHeartRateAverage: Double?
    let sleepHeartRateMinimum: Double?
    /// Apple Health HRV is SDNN (not RMSSD) — the sheet labels it as such.
    let overnightHRVSDNN: Double?
    /// Fraction 0–1.
    let oxygenSaturation: Double?
    let wristTemperature: Double?
    /// Morning summaries only. A history day never borrows today's baseline.
    let baselineDelta: TimeInterval?
    let baselineSampleCount: Int?

    static func from(record: HealthDayRecord) -> SleepNightDetail {
        SleepNightDetail(
            wakeDay: Calendar.current.startOfDay(for: record.date),
            start: record.sleepStart,
            end: record.sleepEnd,
            total: max(0, record.sleepTotal),
            segments: record.sleepSegments,
            sleepInBed: record.sleepInBed,
            sleepLatency: record.sleepLatency,
            providerAwakeningCount: nil,
            // Backfill joins these to the night's own [sleepStart, sleepEnd].
            nightSignalsScoped: true,
            sleepHeartRateAverage: record.sleepingHeartRateAverage,
            sleepHeartRateMinimum: record.sleepingHeartRateMinimum,
            overnightHRVSDNN: record.overnightHRV,
            oxygenSaturation: record.sleepingOxygenSaturation,
            wristTemperature: record.sleepingWristTemperature,
            baselineDelta: nil,
            baselineSampleCount: nil
        )
    }

    static func from(summary: MorningSleepSummary) -> SleepNightDetail {
        SleepNightDetail(
            wakeDay: Calendar.current.startOfDay(for: summary.wakeDay),
            start: summary.start,
            end: summary.end,
            total: max(0, summary.total),
            segments: summary.segments,
            sleepInBed: summary.sleepInBed,
            sleepLatency: summary.sleepLatency,
            providerAwakeningCount: summary.providerAwakeningCount,
            nightSignalsScoped: summary.nightSignalsScoped == true,
            sleepHeartRateAverage: summary.sleepHeartRateAverage,
            sleepHeartRateMinimum: summary.sleepHeartRateMin,
            overnightHRVSDNN: summary.overnightHRV,
            oxygenSaturation: summary.oxygenSaturation,
            wristTemperature: summary.sleepingWristTemperature,
            baselineDelta: summary.baselineDelta,
            baselineSampleCount: summary.baselineSampleCount
        )
    }

    static func empty(day: Date) -> SleepNightDetail {
        SleepNightDetail(
            wakeDay: Calendar.current.startOfDay(for: day),
            start: nil, end: nil, total: 0, segments: [],
            sleepInBed: nil, sleepLatency: nil, providerAwakeningCount: nil,
            nightSignalsScoped: true,
            sleepHeartRateAverage: nil, sleepHeartRateMinimum: nil,
            overnightHRVSDNN: nil, oxygenSaturation: nil, wristTemperature: nil,
            baselineDelta: nil, baselineSampleCount: nil
        )
    }

    // MARK: Stages

    struct StageStat: Equatable, Identifiable {
        var id: Int { stage.rawValue }
        let stage: SleepStage
        let seconds: TimeInterval
        /// Share of `recordedStageSeconds`, 0–100.
        let percent: Double
    }

    /// The intervals the trail actually plots.
    var plottedSegments: [SleepSegmentValue] {
        SleepTrailGeometry.validSegments(segments)
    }

    var hasStages: Bool { !plottedSegments.isEmpty }

    /// Denominator of every stage percentage: summed duration of the plotted
    /// stage intervals (awake included). Unrecorded gaps are not counted, so
    /// percentages are never stretched to cover missing time.
    var recordedStageSeconds: TimeInterval {
        plottedSegments.reduce(0) { $0 + $1.duration }
    }

    /// 清醒 / 眼动 / 浅睡 / 深睡 in legend order. Empty without stages.
    var stageStats: [StageStat] {
        let plotted = plottedSegments
        guard !plotted.isEmpty else { return [] }
        let denominator = recordedStageSeconds
        return SleepTrailPalette.stageOrder.map { stage in
            let seconds = plotted.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
            return StageStat(
                stage: stage,
                seconds: seconds,
                percent: denominator > 0 ? seconds / denominator * 100 : 0
            )
        }
    }

    // MARK: Structure facts

    /// Time in bed can never be shorter than the sleep inside it. A shorter or
    /// non-positive provider value is corrupt and reads as missing.
    var plausibleInBed: TimeInterval? {
        guard let inBed = sleepInBed, inBed.isFinite, inBed > 0 else { return nil }
        if total > 0, inBed < total { return nil }
        return inBed
    }

    /// Latency keeps an explicit 0 (fell asleep immediately) distinct from nil.
    var plausibleLatency: TimeInterval? {
        guard let sleepLatency, sleepLatency.isFinite, sleepLatency >= 0 else { return nil }
        return sleepLatency
    }

    /// Recorded awake intervals between fall-asleep and wake. A plain count of
    /// recorded intervals — labelled separately from any provider count.
    var recordedAwakeIntervals: Int? {
        let plotted = plottedSegments
        guard !plotted.isEmpty else { return nil }
        return plotted.filter { segment in
            guard segment.stage == .awake else { return false }
            if let start, segment.start < start { return false }
            if let end, segment.end > end { return false }
            return true
        }.count
    }

    // MARK: Night body records

    /// Only sleep-window-scoped, physically meaningful values.
    func nightValue(_ value: Double?) -> Double? {
        guard nightSignalsScoped, let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    // MARK: Trend

    struct TrendDay: Equatable, Identifiable {
        var id: Date { date }
        let date: Date
        /// `nil` = no recorded night for that date (an empty slot, not zero).
        let seconds: TimeInterval?
    }

    /// Seven real dates ending on this wake-day. The wake-day uses this detail's
    /// own total; other dates read `lookup`. Missing dates stay empty slots.
    func trendDays(
        calendar: Calendar = .current,
        lookup: (Date) -> TimeInterval?
    ) -> [TrendDay] {
        let endDay = calendar.startOfDay(for: wakeDay)
        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: endDay) else {
                return nil
            }
            let seconds = offset == 0 ? total : lookup(date)
            return TrendDay(date: date, seconds: seconds.flatMap { $0 > 0 ? $0 : nil })
        }
    }
}

enum SleepDetailFormat {
    /// "12 分钟" under an hour, else "7 小时 56 分". `nil`/invalid → "—".
    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return AppLocalization.format("%d 分钟", minutes) }
        return AppLocalization.format("%d 小时 %d 分", minutes / 60, minutes % 60)
    }

    static func number(_ value: Double?, digits: Int = 0) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        return String(format: "%.\(digits)f", value)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    /// "个人常态 +24分 · 基于 8 晚". Empty without a delta.
    static func baseline(delta: TimeInterval?, sampleCount: Int?) -> String {
        guard let delta, delta.isFinite, let sampleCount, sampleCount > 0 else { return "" }
        let minutes = Int((abs(delta) / 60).rounded())
        return AppLocalization.format(
            "个人常态 %@%d分 · 基于 %d 晚",
            delta >= 0 ? "+" : "−",
            minutes,
            sampleCount
        )
    }
}

import Foundation
import PiboCore

/// A rolling summary of recent nights for the sleep detail sheet and the
/// (currently unlisted) history weekly card.
///
/// The platform only attributes persisted records to local days. Every
/// aggregate, score, regularity threshold and guidance decision comes from
/// `pibo-core` (`PiboCoreSleep.weeklyReport`); nothing is re-derived in Swift.
/// Scores stay background inputs to guidance and are never displayed.
struct SleepWeeklyReport {
    let nightsWithData: Int
    let averageDuration: TimeInterval?
    /// Minutes-of-day (0..<1440), Core's circular mean.
    let averageBedtimeMinutes: Int?
    let averageWakeMinutes: Int?
    let averageScore: Int?
    let regularity: Int?
    /// Neutral, product-replaceable guidance copy mapped from Core flags.
    let suggestions: [String]
    /// Seven real dates ending on the report's end day; missing nights keep
    /// `hasData == false` instead of borrowing a neighbour.
    let trend: [FootprintsTrendPoint]

    var hasData: Bool { nightsWithData > 0 }

    /// minutes-of-day → "H:mm".
    nonisolated static func timeText(_ minutes: Int) -> String {
        let normalized = ((minutes % 1440) + 1440) % 1440
        return String(format: "%d:%02d", normalized / 60, normalized % 60)
    }

    /// One night the caller already holds (e.g. a morning summary that has not
    /// landed in history yet). It replaces the end day's record.
    struct LiveNight {
        let total: TimeInterval
        let deep: TimeInterval
        let rem: TimeInterval
        let awake: TimeInterval
        let start: Date?
        let end: Date?
    }

    @MainActor
    static func make(
        history: HealthHistoryStore,
        endDay: Date,
        live: LiveNight? = nil,
        calendar: Calendar = .current
    ) -> SleepWeeklyReport {
        let end = calendar.startOfDay(for: endDay)
        let start = calendar.date(byAdding: .day, value: -13, to: end) ?? end
        return report(
            records: history.records(from: start, to: end).map(Night.init(record:)),
            endDay: end,
            live: live,
            calendar: calendar
        )
    }

    /// Plain night evidence, decoupled from SwiftData for tests.
    struct Night {
        let date: Date
        let total: TimeInterval
        let deep: TimeInterval
        let rem: TimeInterval
        let awake: TimeInterval
        let start: Date?
        let end: Date?

        init(date: Date, total: TimeInterval, deep: TimeInterval = 0, rem: TimeInterval = 0,
             awake: TimeInterval = 0, start: Date? = nil, end: Date? = nil) {
            self.date = date
            self.total = total
            self.deep = deep
            self.rem = rem
            self.awake = awake
            self.start = start
            self.end = end
        }

        @MainActor
        init(record: HealthDayRecord) {
            self.init(
                date: record.date, total: record.sleepTotal, deep: record.sleepDeep,
                rem: record.sleepREM, awake: record.sleepAwake,
                start: record.sleepStart, end: record.sleepEnd
            )
        }
    }

    static func report(
        records: [Night],
        endDay: Date,
        live: LiveNight?,
        calendar: Calendar = .current
    ) -> SleepWeeklyReport {
        let end = calendar.startOfDay(for: endDay)
        var byDay: [Date: Night] = [:]
        for night in records {
            let offset = dayOffset(night.date, from: end, calendar: calendar)
            guard (-13...0).contains(offset) else { continue }
            byDay[calendar.startOfDay(for: night.date)] = night
        }
        if let live {
            byDay[end] = Night(
                date: end, total: live.total, deep: live.deep, rem: live.rem,
                awake: live.awake, start: live.start, end: live.end
            )
        }

        let coreNights = byDay.values.map { night in
            PiboCoreSleepWeeklyNight(
                totalSeconds: max(0, night.total),
                deepSeconds: max(0, night.deep),
                remSeconds: max(0, night.rem),
                awakeSeconds: max(0, night.awake),
                bedtimeMinutes: night.start.map { minuteOfDay($0, calendar: calendar) },
                wakeMinutes: night.end.map { minuteOfDay($0, calendar: calendar) },
                dayOffset: dayOffset(night.date, from: end, calendar: calendar)
            )
        }
        let core = PiboCoreSleep.weeklyReport(nights: coreNights)

        let trend: [FootprintsTrendPoint] = (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: end) else { return nil }
            let seconds = max(0, byDay[date]?.total ?? 0)
            return FootprintsTrendPoint(
                date: date,
                steps: 0,
                sleep: seconds / 3600,
                activeEnergy: 0,
                hrv: 0,
                hasData: seconds > 0
            )
        }

        return SleepWeeklyReport(
            nightsWithData: core.nightsWithData,
            averageDuration: core.averageDurationSeconds,
            averageBedtimeMinutes: core.averageBedtimeMinutes,
            averageWakeMinutes: core.averageWakeMinutes,
            averageScore: core.averageScore,
            regularity: core.regularity,
            suggestions: core.guidance.map(guidanceText),
            trend: trend
        )
    }

    private static func guidanceText(_ guidance: PiboCoreSleepWeeklyGuidance) -> String {
        switch guidance {
        case .irregular: "最近入睡和起床时间波动较大，尽量固定作息。"
        case .shortDuration: "最近平均睡眠不足 7 小时，试着早点休息。"
        case .goodQuality: "最近睡眠质量不错，保持下去。"
        case .accumulating: "睡眠数据还在积累，先坚持记录几晚。"
        }
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func dayOffset(_ date: Date, from end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents(
            [.day],
            from: end,
            to: calendar.startOfDay(for: date)
        ).day ?? 0
    }
}

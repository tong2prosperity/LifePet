import Foundation

/// A rolling summary of recent nights, shared by the morning card's compact
/// weekly strip and the history page's full weekly card. Aggregation is pure
/// over persisted `HealthDayRecord`s.
///
/// Product rule: the UI shows only facts (durations, clock times, trend). Any
/// derived *score* (sleep quality, routine regularity) stays here as a private
/// input to neutral guidance and is never displayed as a number.
struct SleepWeeklyReport {
    let nightsWithData: Int
    let averageDuration: TimeInterval?
    /// Average bedtime / wake time as minutes-of-day (0..<1440), circular-mean so
    /// times either side of midnight average correctly. Displayed as a clock time.
    let averageBedtimeMinutes: Int?
    let averageWakeMinutes: Int?
    /// Background-only signals (never shown as a number) that shape `suggestions`.
    let averageScore: Int?
    let regularity: Int?
    /// Neutral, product-replaceable guidance (no tsundere voice on this surface).
    let suggestions: [String]
    /// 7-day sleep-hours series for the sparkline (today blended live).
    let trend: [FootprintsTrendPoint]

    var hasData: Bool { nightsWithData > 0 }

    /// minutes-of-day → "H:mm".
    nonisolated static func timeText(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    @MainActor
    static func make(
        store: PetStateStore,
        history: HealthHistoryStore,
        calendar: Calendar = .current
    ) -> SleepWeeklyReport {
        let today = calendar.startOfDay(for: .now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let twoWeekStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today

        let weekRecords = history.records(from: weekStart, to: today).filter { $0.sleepTotal > 0 }
        let regularityRecords = history.records(from: twoWeekStart, to: today)
            .filter { $0.sleepStart != nil && $0.sleepEnd != nil }

        let durations = weekRecords.map(\.sleepTotal)
        let averageDuration = durations.isEmpty
            ? nil
            : durations.reduce(0, +) / Double(durations.count)

        let bedtimeMinutes = regularityRecords.compactMap(\.sleepStart)
            .map { minuteOfDay($0, calendar: calendar) }
        let wakeMinutes = regularityRecords.compactMap(\.sleepEnd)
            .map { minuteOfDay($0, calendar: calendar) }
        let averageBedtimeMinutes = bedtimeMinutes.count >= 2
            ? circularMeanMinutes(bedtimeMinutes)
            : nil
        let averageWakeMinutes = wakeMinutes.count >= 2
            ? circularMeanMinutes(wakeMinutes)
            : nil

        let scores = weekRecords.map { record in
            SleepScore.score(
                total: record.sleepTotal,
                deep: record.sleepDeep,
                rem: record.sleepREM,
                continuity: record.sleepAwake > 0
                    ? record.sleepTotal / (record.sleepTotal + record.sleepAwake)
                    : nil
            )
        }
        let averageScore = scores.isEmpty
            ? nil
            : Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())

        let regularity = routineRegularity(
            bedtimes: regularityRecords.compactMap(\.sleepStart),
            waketimes: regularityRecords.compactMap(\.sleepEnd),
            calendar: calendar
        )

        let trend = FootprintsTrendPoint.make(
            range: .sevenDays,
            store: store,
            history: history,
            calendar: calendar
        )

        return SleepWeeklyReport(
            nightsWithData: weekRecords.count,
            averageDuration: averageDuration,
            averageBedtimeMinutes: averageBedtimeMinutes,
            averageWakeMinutes: averageWakeMinutes,
            averageScore: averageScore,
            regularity: regularity,
            suggestions: suggestions(
                duration: averageDuration,
                score: averageScore,
                regularity: regularity
            ),
            trend: trend
        )
    }

    /// Circular-statistics regularity so a 23:50 / 00:10 pair reads as *close*,
    /// not 24h apart. Returns nil with fewer than 4 nights.
    nonisolated static func routineRegularity(
        bedtimes: [Date],
        waketimes: [Date],
        calendar: Calendar = .current
    ) -> Int? {
        guard bedtimes.count >= 4, waketimes.count >= 4 else { return nil }
        guard
            let bedStd = circularStdMinutes(bedtimes.map { minuteOfDay($0, calendar: calendar) }),
            let wakeStd = circularStdMinutes(waketimes.map { minuteOfDay($0, calendar: calendar) })
        else { return nil }
        // ~30 min combined night-to-night dispersion costs ≈ 15 points.
        let penalty = 0.5 * (bedStd + wakeStd)
        return min(100, max(0, Int((100 - penalty).rounded())))
    }

    private nonisolated static func minuteOfDay(_ date: Date, calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// Circular mean of times-of-day (minutes 0..<1440), returned as minutes-of-day
    /// so bedtimes either side of midnight (23:50 / 00:10) average to ~00:00.
    private nonisolated static func circularMeanMinutes(_ minutes: [Double]) -> Int? {
        guard !minutes.isEmpty else { return nil }
        let twoPi = 2 * Double.pi
        var cosSum = 0.0
        var sinSum = 0.0
        for minute in minutes {
            let angle = twoPi * (minute / 1440)
            cosSum += cos(angle)
            sinSum += sin(angle)
        }
        guard abs(cosSum) > 1e-9 || abs(sinSum) > 1e-9 else { return nil }
        var angle = atan2(sinSum, cosSum)
        if angle < 0 { angle += twoPi }
        let minute = angle / twoPi * 1440
        return Int(minute.rounded()) % 1440
    }

    /// Circular standard deviation of times-of-day (minutes 0..<1440), in minutes.
    private nonisolated static func circularStdMinutes(_ minutes: [Double]) -> Double? {
        guard !minutes.isEmpty else { return nil }
        let twoPi = 2 * Double.pi
        var cosSum = 0.0
        var sinSum = 0.0
        for minute in minutes {
            let angle = twoPi * (minute / 1440)
            cosSum += cos(angle)
            sinSum += sin(angle)
        }
        let n = Double(minutes.count)
        let r = (cosSum * cosSum + sinSum * sinSum).squareRoot() / n
        guard r > 0 else { return 1440 / 4 }   // maximally dispersed
        let stdRadians = (-2 * log(min(1, r))).squareRoot()
        return stdRadians * (1440 / twoPi)
    }

    private nonisolated static func suggestions(
        duration: TimeInterval?,
        score: Int?,
        regularity: Int?
    ) -> [String] {
        var out: [String] = []
        if let regularity, regularity < 60 {
            out.append("最近入睡和起床时间波动较大，尽量固定作息。")
        }
        if let duration, duration < 7 * 3600 {
            out.append("最近平均睡眠不足 7 小时，试着早点休息。")
        }
        if out.isEmpty, let score, score >= 80 {
            out.append("最近睡眠质量不错，保持下去。")
        }
        if out.isEmpty {
            out.append("睡眠数据还在积累，先坚持记录几晚。")
        }
        return Array(out.prefix(2))
    }
}

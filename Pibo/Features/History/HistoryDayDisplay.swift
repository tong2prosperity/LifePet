import Foundation

/// One selected day as the 健康记录 page renders it. Today and past days both
/// read the persisted `HealthDayRecord`; nothing is mixed in from live store
/// values of unknown date. `nil` means "not recorded" ("—"); a recorded 0
/// stays 0.
struct HistoryDayDisplay: Equatable {
    let date: Date
    let isToday: Bool

    let activeEnergy: Double?
    let exerciseMinutes: Int?
    let standHours: Int?
    /// Ring goals; 0 = unknown, resolved by Core's activity-water defaults.
    let moveGoal: Double
    let exerciseGoal: Int
    let standGoal: Int

    let steps: Int?
    /// Real 24 local-hour buckets (00:00–24:00), or nil. Never derived.
    let hourlySteps: [Int]?

    let sleep: SleepNightDetail

    let heartRate: Double?
    let restingHeartRate: Double?
    /// Fraction 0–1.
    let oxygenSaturation: Double?

    static func make(
        date: Date,
        record: HealthDayRecord?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> HistoryDayDisplay {
        let day = calendar.startOfDay(for: date)
        func positive(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value > 0 else { return nil }
            return value
        }
        return HistoryDayDisplay(
            date: day,
            isToday: calendar.isDate(day, inSameDayAs: now),
            activeEnergy: record?.recordedActiveEnergy,
            exerciseMinutes: record?.recordedExerciseMinutes,
            standHours: record?.recordedStandMinutes.map { Int((Double($0) / 60).rounded()) },
            moveGoal: record?.moveGoal ?? 0,
            exerciseGoal: record?.exerciseGoal ?? 0,
            standGoal: record?.standGoal ?? 0,
            steps: record?.recordedSteps,
            hourlySteps: record?.recordedHourlySteps,
            sleep: record.map { SleepNightDetail.from(record: $0) } ?? .empty(day: day),
            heartRate: positive(record?.heartRateAvg),
            restingHeartRate: positive(record?.restingHR),
            oxygenSaturation: positive(record?.oxygenSaturation)
        )
    }

    var hasAnyActivity: Bool {
        activeEnergy != nil || exerciseMinutes != nil || standHours != nil
    }

    /// Each day shows only its own RMSSD. The finalized day median wins; for
    /// today, before a median exists, the latest reading counts only when it
    /// was measured today — an older reading must not speak for today.
    static func rmssd(
        day: Date,
        dailyMedian: Double?,
        latest: Double?,
        latestMeasuredAt: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double? {
        if let dailyMedian, dailyMedian > 0 { return dailyMedian }
        guard calendar.isDate(day, inSameDayAs: now),
              let latest, latest > 0,
              let latestMeasuredAt,
              calendar.isDate(latestMeasuredAt, inSameDayAs: day)
        else { return nil }
        return latest
    }
}

/// Date bar rules: no future dates, ever.
enum HistoryDateNavigation {
    static func shifted(
        _ selected: Date,
        by days: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard let next = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: selected))
        else { return nil }
        return next <= calendar.startOfDay(for: now) ? next : nil
    }

    static func canGoForward(_ selected: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        shifted(selected, by: 1, now: now, calendar: calendar) != nil
    }

    /// Picker output clamped to a local day no later than today.
    static func clamped(_ picked: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        min(calendar.startOfDay(for: picked), calendar.startOfDay(for: now))
    }
}

/// Footer copy for the health data status. Reports what the platform told
/// us; it never infers denied authorization from missing data.
enum HistoryDataStatusText {
    static func text(
        authState: HealthDataService.AuthState,
        availability: HealthDataService.DataAvailability
    ) -> String {
        switch authState {
        case .denied:
            return AppLocalization.text("健康访问未获授权 · 可前往设置管理")
        case .requesting:
            return AppLocalization.text("正在请求健康授权")
        case .unavailable:
            return AppLocalization.text("当前设备不支持健康数据")
        case .unknown:
            return AppLocalization.text("尚未连接健康记录")
        case .granted:
            break
        }
        switch availability {
        case .unavailable:
            return AppLocalization.text("当前设备不支持健康数据")
        case .needsAuthorization:
            return AppLocalization.text("尚未连接健康记录")
        case .checking:
            return AppLocalization.text("正在检查健康记录")
        case .noReadableData:
            return AppLocalization.text("暂未读到健康记录")
        case .available(let lastCheckedAt):
            return AppLocalization.format("最近同步 %@", stamp(lastCheckedAt))
        case .temporarilyInterrupted(let lastReadableAt):
            guard let lastReadableAt else {
                return AppLocalization.text("同步中断 · 已保留此前记录")
            }
            return AppLocalization.format("同步中断 · 已保留此前记录（最近成功 %@）", stamp(lastReadableAt))
        }
    }

    private static func stamp(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()
}

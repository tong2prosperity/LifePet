import Foundation

/// Value snapshot used by the new 足迹 surface. It deliberately stays separate
/// from `PiboHistoryView.HistoryDay` so the original page remains untouched and
/// can be kept beside the redesign for comparison.
struct FootprintsDaySnapshot {
    let date: Date
    let isToday: Bool

    let steps: Int
    let hourlySteps: [Int]
    let activeEnergy: Double
    let exerciseMinutes: Int
    let standMinutes: Int

    let sleepTotal: TimeInterval
    let sleepDeep: TimeInterval
    let sleepREM: TimeInterval
    let sleepCore: TimeInterval
    let sleepAwake: TimeInterval
    let sleepStart: Date?
    let sleepEnd: Date?
    let sleepSegments: [SleepSegmentValue]

    let heartRateAverage: Double
    let heartRateMinimum: Double
    let heartRateMaximum: Double
    let restingHeartRate: Double
    let hrv: Double
    let oxygenSaturation: Double

    let workouts: [WorkoutRecord]
    let foods: [FoodPhoto]
    let doodles: [WalkDoodleRecord]

    var sleepHours: Double { sleepTotal / 3_600 }
    var deepSleepHours: Double { sleepDeep / 3_600 }
    var hasHealthData: Bool {
        steps > 0 || activeEnergy > 0 || exerciseMinutes > 0 || sleepTotal > 0
            || heartRateAverage > 0 || restingHeartRate > 0 || hrv > 0
    }

    var healthSignalCount: Int {
        [steps > 0, activeEnergy > 0, sleepTotal > 0, restingHeartRate > 0, hrv > 0]
            .filter { $0 }.count
    }

    @MainActor
    static func make(
        date: Date,
        store: PetStateStore,
        history: HealthHistoryStore,
        calendar: Calendar = .current
    ) -> FootprintsDaySnapshot {
        let day = calendar.startOfDay(for: date)
        let record = history.record(on: day)
        let isToday = calendar.isDateInToday(day)
        #if DEBUG
        let usesLiveToday = isToday && !ProcessInfo.processInfo.arguments
            .contains("-PiboHistoryDemoContent")
        #else
        let usesLiveToday = isToday
        #endif

        let liveSleepTotal = store.rawSleepHours * 3_600
        let liveSleepStart = store.rawSleepStart
        return FootprintsDaySnapshot(
            date: day,
            isToday: isToday,
            steps: usesLiveToday ? store.rawSteps : record?.steps ?? 0,
            hourlySteps: record?.hourlySteps ?? [],
            activeEnergy: usesLiveToday ? store.rawActiveEnergy : record?.activeEnergy ?? 0,
            exerciseMinutes: usesLiveToday ? store.rawExerciseMinutes : record?.exerciseMinutes ?? 0,
            standMinutes: usesLiveToday ? store.rawStandMinutes : record?.standMinutes ?? 0,
            sleepTotal: usesLiveToday ? liveSleepTotal : record?.sleepTotal ?? 0,
            sleepDeep: usesLiveToday ? store.rawSleepDeepHours * 3_600 : record?.sleepDeep ?? 0,
            sleepREM: usesLiveToday ? store.rawSleepREMHours * 3_600 : record?.sleepREM ?? 0,
            sleepCore: record?.sleepCore ?? 0,
            sleepAwake: record?.sleepAwake ?? 0,
            sleepStart: usesLiveToday ? liveSleepStart : record?.sleepStart,
            sleepEnd: usesLiveToday
                ? liveSleepStart.map { $0.addingTimeInterval(liveSleepTotal) }
                : record?.sleepEnd,
            sleepSegments: record?.sleepSegments ?? [],
            heartRateAverage: usesLiveToday ? store.rawHeartRate : record?.heartRateAvg ?? 0,
            heartRateMinimum: record?.heartRateMin ?? 0,
            heartRateMaximum: record?.heartRateMax ?? 0,
            restingHeartRate: usesLiveToday ? store.rawRestingHR : record?.restingHR ?? 0,
            hrv: usesLiveToday ? store.rawHRV : record?.hrv ?? 0,
            oxygenSaturation: usesLiveToday ? store.rawOxygen : record?.oxygenSaturation ?? 0,
            workouts: history.workouts(on: day),
            foods: history.foodPhotos(on: day),
            doodles: history.walkDoodles(on: day)
        )
    }
}

enum FootprintsMetric: String, CaseIterable, Identifiable {
    case sleep
    case steps
    case activeEnergy
    case hrv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: "睡眠"
        case .steps: "脚步"
        case .activeEnergy: "活动"
        case .hrv: "HRV"
        }
    }

    var icon: String {
        switch self {
        case .sleep: "moon.stars.fill"
        case .steps: "figure.walk"
        case .activeEnergy: "flame.fill"
        case .hrv: "waveform.path.ecg"
        }
    }

    var unit: String {
        switch self {
        case .sleep: "h"
        case .steps: "步"
        case .activeEnergy: "kcal"
        case .hrv: "ms"
        }
    }

    func value(in day: FootprintsDaySnapshot) -> Double {
        switch self {
        case .sleep: day.sleepHours
        case .steps: Double(day.steps)
        case .activeEnergy: day.activeEnergy
        case .hrv: day.hrv
        }
    }

    func value(in record: HealthDayRecord) -> Double {
        switch self {
        case .sleep: record.sleepTotal / 3_600
        case .steps: Double(record.steps)
        case .activeEnergy: record.activeEnergy
        case .hrv: record.hrv
        }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .sleep:
            return String(format: "%.1f", value)
        case .steps, .activeEnergy, .hrv:
            return "\(Int(value.rounded()))"
        }
    }

    func hasValue(_ value: Double) -> Bool { value > 0 }
}

enum FootprintsTrendRange: Int, CaseIterable, Identifiable {
    case sevenDays = 7
    case thirtyDays = 30

    var id: Int { rawValue }
    var title: String { self == .sevenDays ? "7天" : "30天" }
}

struct FootprintsTrendPoint: Identifiable {
    let date: Date
    let steps: Double
    let sleep: Double
    let activeEnergy: Double
    let hrv: Double
    let hasData: Bool

    var id: Date { date }

    func value(for metric: FootprintsMetric) -> Double {
        switch metric {
        case .sleep: sleep
        case .steps: steps
        case .activeEnergy: activeEnergy
        case .hrv: hrv
        }
    }

    @MainActor
    static func make(
        range: FootprintsTrendRange,
        store: PetStateStore,
        history: HealthHistoryStore,
        calendar: Calendar = .current
    ) -> [FootprintsTrendPoint] {
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(
            byAdding: .day,
            value: -(range.rawValue - 1),
            to: today
        ) else { return [] }

        // Rows written under a different timezone can collapse onto the same
        // local day here, so duplicate keys must resolve (keep the freshest
        // row) instead of trapping — this runs inside the morning-sheet build.
        let records = Dictionary(
            history.records(from: start, to: today).map {
                (calendar.startOfDay(for: $0.date), $0)
            },
            uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 }
        )

        return (0..<range.rawValue).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            if calendar.isDateInToday(date) {
                let day = FootprintsDaySnapshot.make(
                    date: date,
                    store: store,
                    history: history,
                    calendar: calendar
                )
                return FootprintsTrendPoint(
                    date: date,
                    steps: Double(day.steps),
                    sleep: day.sleepHours,
                    activeEnergy: day.activeEnergy,
                    hrv: day.hrv,
                    hasData: day.hasHealthData
                )
            }
            let record = records[calendar.startOfDay(for: date)]
            return FootprintsTrendPoint(
                date: date,
                steps: Double(record?.steps ?? 0),
                sleep: (record?.sleepTotal ?? 0) / 3_600,
                activeEnergy: record?.activeEnergy ?? 0,
                hrv: record?.hrv ?? 0,
                hasData: record?.hasData ?? false
            )
        }
    }
}

struct FootprintsInsight {
    let metric: FootprintsMetric
    let fact: String
    let evidence: String
    let speechCue: PiboSpeechCue

    @MainActor
    static func make(
        day: FootprintsDaySnapshot,
        history: HealthHistoryStore,
        calendar: Calendar = .current
    ) -> FootprintsInsight {
        let baseline = baselineRecords(before: day.date, history: history, calendar: calendar)
        let sleepValues = baseline.map { $0.sleepTotal / 3_600 }.filter { $0 > 0 }
        let stepValues = baseline.map { Double($0.steps) }.filter { $0 > 0 }
        let sleepBaseline = median(sleepValues)
        let stepsBaseline = median(stepValues)
        let prefix = day.isToday ? "昨晚" : "这晚"

        if day.sleepHours > 0, let sleepBaseline, sleepValues.count >= 5 {
            let deltaMinutes = Int(((day.sleepHours - sleepBaseline) * 60).rounded())
            if abs(deltaMinutes) >= 20 {
                let direction = deltaMinutes > 0 ? "多" : "少"
                return FootprintsInsight(
                    metric: .sleep,
                    fact: "\(prefix)比你的近期常态\(direction)睡了 \(abs(deltaMinutes)) 分钟",
                    evidence: "参照近 28 天中的 \(sleepValues.count) 个有效夜晚",
                    speechCue: deltaMinutes > 0
                        ? .sleepLonger(minutes: deltaMinutes)
                        : .sleepShorter(minutes: deltaMinutes)
                )
            }
        }

        if day.steps > 0, let stepsBaseline, stepValues.count >= 5 {
            let delta = day.steps - Int(stepsBaseline.rounded())
            if abs(delta) >= 1_000 {
                let direction = delta > 0 ? "多走" : "少走"
                return FootprintsInsight(
                    metric: .steps,
                    fact: "这一天比你的近期常态\(direction)了 \(abs(delta)) 步",
                    evidence: "只和你自己的 \(stepValues.count) 个有效日比较",
                    speechCue: delta > 0
                        ? .stepsMore(count: delta)
                        : .stepsFewer(count: delta)
                )
            }
        }

        if let workout = day.workouts.max(by: { $0.duration < $1.duration }) {
            return FootprintsInsight(
                metric: .activeEnergy,
                fact: "这一天有一段 \(workout.durationMinutes) 分钟的运动",
                evidence: "记录于 \(workout.timeRangeText) · \(Int(workout.energyKcal.rounded())) kcal",
                speechCue: .workoutCompleted(minutes: workout.durationMinutes)
            )
        }

        if day.hasHealthData {
            return FootprintsInsight(
                metric: day.sleepHours > 0 ? .sleep : .steps,
                fact: "Pibo 把这一天收到的身体信号放在了一起",
                evidence: "已有 \(day.healthSignalCount)/5 类数据 · 继续积累后再比较",
                speechCue: .healthAccumulating
            )
        }

        return FootprintsInsight(
            metric: .steps,
            fact: "这一天还没有收到可用的身体数据",
            evidence: "可能尚未同步、未授权，或设备没有留下记录",
            speechCue: .healthDataMissing
        )
    }

    private static func baselineRecords(
        before date: Date,
        history: HealthHistoryStore,
        calendar: Calendar
    ) -> [HealthDayRecord] {
        guard let end = calendar.date(byAdding: .day, value: -1, to: date),
              let start = calendar.date(byAdding: .day, value: -28, to: date) else {
            return []
        }
        return history.records(from: start, to: end).filter(\.hasData)
    }
}

func footprintsMedian(_ values: [Double]) -> Double? {
    let sorted = values.filter { $0.isFinite }.sorted()
    guard !sorted.isEmpty else { return nil }
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

private func median(_ values: [Double]) -> Double? {
    footprintsMedian(values)
}

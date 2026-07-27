import Foundation

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

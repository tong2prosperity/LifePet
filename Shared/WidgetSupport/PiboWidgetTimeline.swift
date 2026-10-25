import Foundation

nonisolated enum PiboWidgetTimeline {
    static func dates(from now: Date, calendar: Calendar = .current) -> [Date] {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
        let phases = [6, 17, 20].compactMap {
            calendar.date(bySettingHour: $0, minute: 0, second: 0, of: now)
        }.filter { $0 > now }
        return ([now] + phases + [midnight]).sorted()
    }
}

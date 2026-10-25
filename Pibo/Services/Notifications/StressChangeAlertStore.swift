import Foundation

/// Platform delivery checkpoints for Core's decision-055 policy. Failed
/// notifications never consume the day; no scoring or timing thresholds live here.
@MainActor
final class StressChangeAlertStore {
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let lowerKey = "pibo.stress.change.lowerDay.v1"
    private let recoveredKey = "pibo.stress.change.recoveredDay.v1"
    private let lastKey = "pibo.stress.change.lastAt.v1"

    init(defaults: UserDefaults, calendar: Calendar = .current, now: Date = .now) {
        self.defaults = defaults
        self.calendar = calendar
        let migrationKey = "pibo.stress.change.migrated.v1"
        if !defaults.bool(forKey: migrationKey) {
            if let at = defaults.object(forKey: "pibo.stress.push.lastAt.v1") as? Date, at <= now {
                defaults.set(at, forKey: lastKey)
                let level = (defaults.object(forKey: "pibo.stress.push.lastLevel.v1") as? Int).flatMap(StressLevel.init(rawValue:))
                if level == .notice || level == .overload {
                    defaults.set(calendar.startOfDay(for: at), forKey: lowerKey)
                }
            }
            defaults.set(true, forKey: migrationKey)
        }
    }

    func kind(for level: StressLevel, now: Date = .now) -> StressAlertKind? {
        let last = defaults.object(forKey: lastKey) as? Date
        let elapsed = last.flatMap { $0 <= now ? now.timeIntervalSince($0) : nil }
        return PiboCoreStressAdapter.changeAlertKind(
            level: level, lowerAlertedToday: isToday(lowerKey, now),
            recoveredAlertedToday: isToday(recoveredKey, now),
            localHour: Double(calendar.component(.hour, from: now)), secondsSinceLastAlert: elapsed
        )
    }

    func recordDelivered(_ kind: StressAlertKind, at date: Date) {
        switch kind {
        case .elevated: defaults.set(calendar.startOfDay(for: date), forKey: lowerKey)
        case .recovered: defaults.set(calendar.startOfDay(for: date), forKey: recoveredKey)
        }
        defaults.set(date, forKey: lastKey)
    }

    func deliverySummary(now: Date = .now) -> String {
        "今天已提醒偏低: \(isToday(lowerKey, now) ? "是" : "否") · 已提醒回到平时: \(isToday(recoveredKey, now) ? "是" : "否")"
    }

    static func initialPushEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: "pibo.stress.push.enabled.v1") as? Bool ?? false
    }

    private func isToday(_ key: String, _ now: Date) -> Bool {
        (defaults.object(forKey: key) as? Date).map { calendar.isDate($0, inSameDayAs: now) } ?? false
    }
}

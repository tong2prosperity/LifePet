import Foundation
import PiboCore

/// Converts persisted, paired main-sleep sessions into Core's routine input.
/// No state threshold is duplicated here.
enum HomeAnimationInputResolver {
    struct SleepHistoryWindow: Equatable {
        let start: Date
        let end: Date
    }

    static func sleepHistoryWindow(
        at date: Date,
        calendar: Calendar
    ) -> SleepHistoryWindow {
        let today = calendar.startOfDay(for: date)
        return SleepHistoryWindow(
            start: calendar.date(byAdding: .day, value: -13, to: today) ?? today,
            end: today
        )
    }

    static func nights(
        from records: [HealthDayRecord],
        at date: Date,
        calendar: Calendar
    ) -> [PiboCoreSleepWeeklyNight] {
        let today = calendar.startOfDay(for: date)
        return records.compactMap { record in
            guard record.sleepTotal > 0,
                  let start = record.sleepStart,
                  let end = record.sleepEnd,
                  end > start
            else { return nil }
            let day = calendar.startOfDay(for: record.date)
            let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
            return PiboCoreSleepWeeklyNight(
                totalSeconds: record.sleepTotal,
                deepSeconds: record.sleepDeep,
                remSeconds: record.sleepREM,
                awakeSeconds: record.sleepAwake,
                bedtimeMinutes: minuteOfDay(start, calendar: calendar),
                wakeMinutes: minuteOfDay(end, calendar: calendar),
                dayOffset: offset
            )
        }
    }

    static func resolve(
        at date: Date,
        calendar: Calendar,
        records: [HealthDayRecord],
        hasActivityData: Bool,
        steps: Int,
        lastWorkoutEndedAt: Date?
    ) -> HomeAnimationStateResolver.Input {
        HomeAnimationStateResolver.Input(
            decision: PiboCoreStateAdapter.decide(
                at: date,
                calendar: calendar,
                hasActivityData: hasActivityData,
                steps: steps,
                lastWorkoutEndedAt: lastWorkoutEndedAt,
                nights: nights(from: records, at: date, calendar: calendar)
            ),
            sleepDayKey: dayKey(for: date, calendar: calendar)
        )
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let values = calendar.dateComponents([.hour, .minute], from: date)
        return (values.hour ?? 0) * 60 + (values.minute ?? 0)
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> Int64 {
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return Int64(
            (values.year ?? 0) * 10_000
                + (values.month ?? 0) * 100
                + (values.day ?? 0)
        )
    }
}

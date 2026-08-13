import Foundation
import PiboCore

/// Maps iOS-owned time and health evidence into the existing Core-facing input.
/// State thresholds and decisions remain in `PiboCoreAnimationAdapter`.
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
            start: calendar.date(byAdding: .day, value: -40, to: today) ?? today,
            end: calendar.date(byAdding: .day, value: -1, to: today) ?? today
        )
    }

    static func resolve(
        at date: Date,
        calendar: Calendar,
        sleepHistoryTotals: [TimeInterval],
        localHour: @autoclosure () -> Double,
        rawSleepHours: @autoclosure () -> Double,
        hasStepsData: @autoclosure () -> Bool,
        rawSteps: @autoclosure () -> Int,
        hasWorkoutToday: @autoclosure () -> Bool,
        angryActive: @autoclosure () -> Bool,
        rmssd: @autoclosure () -> Double?,
        rmssdMeasuredAt: @autoclosure () -> Date?,
        rmssdInterpretationEligible: @autoclosure () -> Bool,
        stressBaseline: @autoclosure () -> StressBaseline?,
        previousStressStateID: @autoclosure () -> String,
        heldAchievement: @autoclosure () -> PiboAnimationAchievementKind?
    ) -> HomeAnimationStateResolver.Input {
        let sleepHistory = sleepHistoryTotals
            .filter { $0 > 0 }
            .suffix(28)
            .map { $0 / 3_600 }
        let sleepReference = PiboCoreAnimationAdapter.sleepReference(
            history: Array(sleepHistory)
        )
        let baseline = stressBaseline()
        let stressZ = rmssd().flatMap { value in
            baseline.map { $0.z(for: value) }
        } ?? 0
        let rmssdAge = rmssdMeasuredAt().map { date.timeIntervalSince($0) }
            ?? .greatestFiniteMagnitude
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dayKey = Int64(
            (components.year ?? 0) * 10_000
                + (components.month ?? 0) * 100
                + (components.day ?? 0)
        )

        return HomeAnimationStateResolver.Input(
            localHour: localHour(),
            hasSleepData: rawSleepHours() > 0,
            sleepHours: rawSleepHours(),
            sleepReferenceHours: sleepReference.hours,
            hasActivityData: hasStepsData(),
            steps: rawSteps(),
            hasWorkoutToday: hasWorkoutToday(),
            postPluckSleep: false,
            sleepDayKey: dayKey,
            angryActive: angryActive(),
            hasEligibleRMSSD: rmssd() != nil
                && rmssdInterpretationEligible()
                && baseline != nil,
            stressBaselineDays: baseline?.dayCount ?? 0,
            stressZ: stressZ,
            rmssdAgeSeconds: rmssdAge,
            previousStressStateID: previousStressStateID(),
            heldAchievement: heldAchievement()
        )
    }
}

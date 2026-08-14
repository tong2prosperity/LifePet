import Foundation
import PiboCore

/// The app-side seam for Core's single ambient-state decision.
/// Health thresholds and routine learning remain in `pibo-core`.
enum PiboCoreStateAdapter {
    struct Decision: Equatable {
        let state: PiboActivityState
        let cause: PiboCoreStateCause
        let sleepStartMinute: Int
        let wakeMinute: Int
        let routineSource: PiboCoreRoutineSource
        let routineSampleCount: Int
        let routineRegularity: Int
        let routineShiftMinutes: Int
    }

    static func decide(
        at date: Date,
        calendar: Calendar,
        hasActivityData: Bool,
        steps: Int,
        lastWorkoutEndedAt: Date?,
        nights: [PiboCoreSleepWeeklyNight]
    ) -> Decision {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let localMinute = Double(components.hour ?? 0) * 60
            + Double(components.minute ?? 0)
            + Double(components.second ?? 0) / 60
        let workoutAge = lastWorkoutEndedAt.map { date.timeIntervalSince($0) }
        let result = PiboCoreStatePolicy.decide(
            localMinute: localMinute,
            hasActivityData: hasActivityData,
            steps: steps,
            secondsSinceWorkout: workoutAge,
            nights: nights
        )
        return Decision(
            state: PiboActivityState(core: result.state),
            cause: result.cause,
            sleepStartMinute: result.sleepStartMinute,
            wakeMinute: result.wakeMinute,
            routineSource: result.routineSource,
            routineSampleCount: result.routineSampleCount,
            routineRegularity: result.routineRegularity,
            routineShiftMinutes: result.routineShiftMinutes
        )
    }
}

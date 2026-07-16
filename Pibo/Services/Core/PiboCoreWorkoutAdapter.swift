import PiboCore

enum PiboCoreWorkoutAdapter {
    static var pendingWorkoutMaxAgeSeconds: Double {
        PiboCoreWorkout.pendingWorkoutMaxAgeSeconds
    }

    struct Metrics {
        let durationMinutes: Int
        let paceMinutesPerKilometer: Double?
    }

    struct EventPolicy {
        let durationMinutes: Int
        let vitalityGain: Int
        let isFresh: Bool
    }

    static func metrics(durationSeconds: Double, distanceMeters: Double) -> Metrics {
        let result = PiboCoreWorkout.metrics(
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters
        )
        return Metrics(
            durationMinutes: result.durationMinutes,
            paceMinutesPerKilometer: result.paceMinutesPerKilometer
        )
    }

    static func eventPolicy(durationSeconds: Double, ageSeconds: Double) -> EventPolicy {
        let result = PiboCoreWorkout.eventPolicy(
            durationSeconds: durationSeconds,
            ageSeconds: ageSeconds
        )
        return EventPolicy(
            durationMinutes: result.durationMinutes,
            vitalityGain: result.vitalityGain,
            isFresh: result.isFresh
        )
    }

    static func pendingWorkoutIsRestorable(ageSeconds: Double, sameDay: Bool) -> Bool {
        PiboCoreWorkout.pendingWorkoutIsRestorable(
            ageSeconds: ageSeconds,
            sameDay: sameDay
        )
    }
}

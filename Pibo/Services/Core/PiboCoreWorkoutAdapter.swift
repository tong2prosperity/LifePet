import PiboCore

enum PiboCoreWorkoutAdapter {
    struct Metrics {
        let durationMinutes: Int
        let paceMinutesPerKilometer: Double?
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
}

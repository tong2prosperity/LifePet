import PiboCore

/// Converts app-domain health observations into the stable Rust activity
/// machine input and maps the SDK result back to the UI-facing enum.
enum PiboCoreActivityAdapter {
    static func state(
        localHour: Double,
        recentPatCount: Int,
        postPluckSleep: Bool,
        hasRealHealthData: Bool,
        steps: Int,
        hasWorkoutToday: Bool,
        sleepHours: Double
    ) -> PiboActivityState {
        let state = PiboCorePetBehavior.activityState(for: PiboCoreActivityInput(
            localHour: localHour,
            recentPatCount: recentPatCount,
            postPluckSleep: postPluckSleep,
            hasRealHealthData: hasRealHealthData,
            steps: steps,
            hasWorkoutToday: hasWorkoutToday,
            sleepHours: sleepHours
        ))
        return switch state {
        case .deepSleep: PiboActivityState.deepSleep
        case .waking: PiboActivityState.waking
        case .active: PiboActivityState.active
        case .irritated: PiboActivityState.irritated
        case .idle: PiboActivityState.idle
        case .disturbed: PiboActivityState.disturbed
        }
    }
}

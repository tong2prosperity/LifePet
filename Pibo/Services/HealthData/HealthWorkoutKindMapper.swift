import HealthKit

/// Maps HealthKit's platform-specific activity taxonomy to the coarse workout
/// kinds used by Pibo's event and history pipelines.
enum HealthWorkoutKindMapper {
    static func kind(
        for activityType: HKWorkoutActivityType
    ) -> HealthEvent.WorkoutKind {
        switch activityType {
        case .running:
            .run
        case .walking, .hiking:
            .walk
        case .cycling, .handCycling:
            .cycle
        case .swimming:
            .swim
        case .highIntensityIntervalTraining,
             .functionalStrengthTraining,
             .traditionalStrengthTraining,
             .crossTraining:
            .hiit
        case .yoga, .pilates, .flexibility,
             .mindAndBody, .barre:
            .yoga
        default:
            .other
        }
    }
}

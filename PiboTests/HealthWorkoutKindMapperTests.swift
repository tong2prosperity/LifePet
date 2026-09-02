import HealthKit
import Testing
@testable import Pibo

struct HealthWorkoutKindMapperTests {
    @Test func mapsEveryAuthoredActivityGroup() {
        for (activityType, expected) in Self.cases {
            #expect(HealthWorkoutKindMapper.kind(for: activityType) == expected)
        }
    }

    private static let cases: [
        (HKWorkoutActivityType, HealthEvent.WorkoutKind)
    ] = [
        (.running, .run),
        (.walking, .walk),
        (.hiking, .walk),
        (.cycling, .cycle),
        (.handCycling, .cycle),
        (.swimming, .swim),
        (.highIntensityIntervalTraining, .hiit),
        (.functionalStrengthTraining, .hiit),
        (.traditionalStrengthTraining, .hiit),
        (.crossTraining, .hiit),
        (.yoga, .yoga),
        (.pilates, .yoga),
        (.flexibility, .yoga),
        (.mindAndBody, .yoga),
        (.barre, .yoga),
        (.soccer, .other)
    ]
}

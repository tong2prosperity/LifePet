import Foundation

enum HomeSpeechInputResolver {
    static func facts(
        hasStepsData: @autoclosure () -> Bool,
        rawSteps: @autoclosure () -> Int,
        rawSleepHours: @autoclosure () -> Double,
        hasWorkoutToday: @autoclosure () -> Bool,
        pendingBoCount: @autoclosure () -> Int,
        cooperationEnabled: @autoclosure () -> Bool,
        connectionAccepted: @autoclosure () -> Bool
    ) -> PiboHomeSpeechFacts {
        PiboHomeSpeechFacts(
            hasSteps: hasStepsData() && rawSteps() > 0,
            hasSleepDuration: rawSleepHours() > 0,
            hasWorkoutType: hasWorkoutToday(),
            pendingBoCount: pendingBoCount(),
            connectionAccepted: cooperationEnabled() && connectionAccepted()
        )
    }

    static func values(
        hasStepsData: @autoclosure () -> Bool,
        rawSteps: @autoclosure () -> Int,
        rawSleepHours: @autoclosure () -> Double,
        sleepDurationUnit: @autoclosure () -> String
    ) -> [String: String] {
        var values: [String: String] = [:]
        if hasStepsData(), rawSteps() > 0 {
            values["steps"] = rawSteps().formatted()
        }
        if rawSleepHours() > 0 {
            values["sleepDuration"] = String(
                format: "%.1f %@",
                rawSleepHours(),
                sleepDurationUnit()
            )
        }
        return values
    }
}

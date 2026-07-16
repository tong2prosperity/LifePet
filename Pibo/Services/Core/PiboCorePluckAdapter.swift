import PiboCore

enum PiboCorePluckAdapter {
    static func windowOpen(localHour: Double) -> Bool {
        PiboCorePluck.windowOpen(localHour: localHour)
    }

    static func grade(
        sleepHours: Double,
        steps: Int,
        hasWorkoutToday: Bool
    ) -> PluckGrade {
        switch PiboCorePluck.grade(
            sleepHours: sleepHours,
            steps: steps,
            hasWorkoutToday: hasWorkoutToday
        ) {
        case .good: PluckGrade.good
        case .fair: PluckGrade.fair
        case .poor: PluckGrade.poor
        }
    }
}


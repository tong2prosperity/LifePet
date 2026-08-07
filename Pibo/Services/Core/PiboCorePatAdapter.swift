import PiboCore

enum PiboCorePatAdapter {
    static let recentWindowSeconds = PiboCorePat.recentWindowSeconds
    static let dailyWindowSeconds = PiboCorePat.dailyWindowSeconds

    static func shouldIdleMutter(roll: Double) -> Bool {
        PiboCorePat.shouldIdleMutter(roll: roll)
    }

    struct V2Result: Equatable {
        let speaks: Bool
        let countsTowardAngry: Bool
    }

    static func decideV2(
        spokenIn24Hours: Int,
        spokenIn10Minutes: Int,
        speechRoll: Double,
        restingState: Bool
    ) -> V2Result {
        let result = PiboCorePat.decideV2(
            spokenIn24Hours: spokenIn24Hours,
            spokenIn10Minutes: spokenIn10Minutes,
            speechRoll: speechRoll,
            restingState: restingState
        )
        return V2Result(
            speaks: result.decision == .speak,
            countsTowardAngry: result.countsTowardAngry
        )
    }

    static func countsTowardAngry(restingState: Bool) -> Bool {
        decideV2(
            spokenIn24Hours: 0,
            spokenIn10Minutes: 0,
            speechRoll: 1,
            restingState: restingState
        ).countsTowardAngry
    }
}

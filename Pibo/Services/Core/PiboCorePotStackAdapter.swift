import PiboCore

enum PiboCorePotStackAdapter {
    struct DropResult {
        let nextX: Double
        let nextWidth: Double
        let newStreak: Int
        let scoreGain: Int
        let cutPercent: Int
        let success: Bool
        let perfect: Bool
    }

    static func drop(
        topX: Double,
        topWidth: Double,
        movingX: Double,
        perfectStreak: Int
    ) -> DropResult {
        let result = PiboCorePotStack.drop(
            topX: topX,
            topWidth: topWidth,
            movingX: movingX,
            perfectStreak: perfectStreak
        )
        return DropResult(
            nextX: result.nextX,
            nextWidth: result.nextWidth,
            newStreak: result.newStreak,
            scoreGain: result.scoreGain,
            cutPercent: result.cutPercent,
            success: result.success,
            perfect: result.perfect
        )
    }
}

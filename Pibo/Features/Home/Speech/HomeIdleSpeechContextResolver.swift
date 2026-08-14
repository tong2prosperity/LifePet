import PiboCore

enum HomeIdleSpeechContextResolver {
    static func resolve(
        animationStateID: String,
        wakingSleptEnough: @autoclosure () -> Bool?,
        hasRealHealthData: @autoclosure () -> Bool
    ) -> PiboCoreHomeSpeechContext? {
        switch animationStateID {
        case "sleep-1", "sleep-2", "angry":
            nil
        case "awake":
            wakingSleptEnough() == false ? .wakingLowSleep : .waking
        case "weak":
            .lowSleepAndActivity
        case "boring":
            .lowActivity
        case "tired":
            .lowSleep
        case "dive":
            .dive
        case "coolhide":
            .coolhide
        default:
            hasRealHealthData() ? .idle : .missingDataPibo
        }
    }
}

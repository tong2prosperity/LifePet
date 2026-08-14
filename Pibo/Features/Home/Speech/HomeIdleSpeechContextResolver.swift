import PiboCore

enum HomeIdleSpeechContextResolver {
    static func resolve(
        animationStateID: String,
        hasRealHealthData: @autoclosure () -> Bool
    ) -> PiboCoreHomeSpeechContext? {
        switch animationStateID {
        case PiboAnimationResourceID.sleepingHammockA,
             PiboAnimationResourceID.sleepingHammockB,
             "angry":
            nil
        case PiboAnimationResourceID.wakingHammock:
            .waking
        case PiboAnimationResourceID.tired:
            .lowSleep
        default:
            hasRealHealthData() ? .idle : .missingDataPibo
        }
    }
}

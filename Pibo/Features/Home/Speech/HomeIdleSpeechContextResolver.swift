import PiboCore

enum HomeIdleSpeechContextResolver {
    static func resolve(
        animationStateID: String,
        hasRealHealthData: @autoclosure () -> Bool
    ) -> PiboCoreHomeSpeechContext? {
        if PiboAnimationResourceID.sleeping.contains(animationStateID) { return nil }
        return switch animationStateID {
        case "angry":
            nil
        case PiboAnimationResourceID.wakingHammock,
             PiboAnimationResourceID.wakingGroundRecovering:
            .waking
        case PiboAnimationResourceID.tired:
            .lowSleep
        default:
            hasRealHealthData() ? .idle : .missingDataPibo
        }
    }
}

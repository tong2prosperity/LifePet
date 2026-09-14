import PiboCore

enum HomeIdleSpeechContextResolver {
    static func resolve(
        animationStateID: String,
        hasRealHealthData: @autoclosure () -> Bool
    ) -> PiboCoreHomeSpeechContext? {
        if PiboAnimationResourceID.sleeping.contains(animationStateID) { return nil }
        return switch animationStateID {
        case PiboAnimationResourceID.dataUnknown:
            .missingDataPibo
        case "angry":
            nil
        case PiboAnimationResourceID.wakingHammock, PiboAnimationResourceID.wakingGround,
             PiboAnimationResourceID.wakingGreeted, PiboAnimationResourceID.wakingRecoveringGreeted,
             PiboAnimationResourceID.wakingGroundRecovering:
            .waking
        case PiboAnimationResourceID.tired, PiboAnimationResourceID.tiredResting:
            .lowSleep
        default:
            hasRealHealthData() ? .idle : .missingDataPibo
        }
    }
}

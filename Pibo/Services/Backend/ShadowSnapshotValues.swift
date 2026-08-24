import Foundation
import PiboCore

enum ShadowSnapshotValues {
    static func displayName(_ ownerName: String) -> String {
        let normalized = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((normalized.isEmpty ? "Pibo 用户" : normalized).prefix(24))
    }

    static func makeDraft(
        ownerName: String,
        state: PiboActivityState,
        decision: PiboCoreStateAdapter.Decision?,
        animationStateID: String,
        occurredAt: Date?,
        hasHammock: Bool,
        now: Date = .now
    ) -> ShadowSnapshotDraft? {
        guard state != .dataUnknown else { return nil }
        return ShadowSnapshotDraft(
            displayName: displayName(ownerName),
            publicStateId: state.rawValue,
            publicBehaviorSubstateId: behaviorSubstate(
                state: state,
                cause: decision?.cause,
                hasHammock: hasHammock
            ),
            visualVariantKey: visualVariant(
                state: state,
                animationStateID: animationStateID,
                hasHammock: hasHammock
            ),
            occurredAt: min(occurredAt ?? now, now)
        )
    }

    static func renderableStateID(_ key: String, publicStateID: String) -> String {
        if PiboAnimationStateMap.available.contains(key) { return key }
        let state = PiboActivityState(rawValue: publicStateID) ?? .stable
        return PiboAnimationStateMap.ambientStateID(for: state)
    }

    private static func behaviorSubstate(
        state: PiboActivityState,
        cause: PiboCoreStateCause?,
        hasHammock: Bool
    ) -> String {
        switch state {
        case .sleeping: hasHammock ? "sleeping.hammock" : "sleeping.ground"
        case .waking: hasHammock ? "waking.hammock" : "waking.ground"
        case .energetic:
            switch cause {
            case .recentWorkout: "energetic.recent_workout"
            case .activityMilestone: "energetic.milestone"
            case .goodSleep: "energetic.good_sleep"
            default: "energetic.active"
            }
        case .tired: cause == .insufficientSleep ? "tired.insufficient_sleep" : "tired.resting"
        default: "stable.idle"
        }
    }

    private static func visualVariant(
        state: PiboActivityState,
        animationStateID: String,
        hasHammock: Bool
    ) -> String {
        if PiboAnimationStateMap.available.contains(animationStateID) { return animationStateID }
        switch state {
        case .sleeping:
            return hasHammock
                ? PiboAnimationResourceID.sleepingHammockA
                : PiboAnimationResourceID.sleepingGroundA
        case .waking:
            return hasHammock ? PiboAnimationResourceID.wakingHammock : PiboAnimationResourceID.stable
        case .tired: return PiboAnimationResourceID.tired
        default: return PiboAnimationResourceID.stable
        }
    }
}

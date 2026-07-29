import Foundation
import PiboCore

/// Converts app-domain state into the stable Rust animation decision.
///
/// The mapping itself lives in Core beside the six-state machine, because both
/// platforms have to agree on what Pibo is doing — the artwork and the playback
/// are each platform's business, the choice is not.
enum PiboCoreAnimationAdapter {
    /// The pose Pibo holds when nothing is being performed.
    ///
    /// `stressZ` is the personal-baseline z-score; pass `hasStressBaseline:
    /// false` while the baseline is still cold, because a zero with no history
    /// behind it is an absence of data rather than a calm day, and reading a
    /// mood off it would be inventing one.
    static func ambientStateID(
        for state: PiboActivityState,
        stressZ: Double = 0,
        hasStressBaseline: Bool = false,
        sleptWell: Bool = true,
        lowEnergyDays: UInt32 = 0
    ) -> String {
        PiboCoreAnimation.ambientState(
            activity: coreState(for: state),
            stressZ: stressZ,
            hasStressBaseline: hasStressBaseline,
            sleptWell: sleptWell,
            lowEnergyDays: lowEnergyDays
        ).contentID
    }

    /// Whether a finished workout earns the 秀肌肉 → 娇羞 performance.
    static func workoutCelebrationAllowed(
        for state: PiboActivityState,
        lowEnergyDays: UInt32 = 0
    ) -> Bool {
        PiboCoreAnimation.workoutCelebrationAllowed(
            activity: coreState(for: state),
            lowEnergyDays: lowEnergyDays
        )
    }

    private static func coreState(for state: PiboActivityState) -> PiboCoreActivityState {
        switch state {
        case .deepSleep: .deepSleep
        case .waking: .waking
        case .active: .active
        case .irritated: .irritated
        case .idle: .idle
        case .disturbed: .disturbed
        }
    }
}

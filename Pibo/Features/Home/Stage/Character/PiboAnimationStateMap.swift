import Foundation

/// Which animation state Pibo wears for a given condition.
///
/// Two different axes meet here. `PiboActivityState` describes a **condition**
/// derived from health data and can hold for hours; an animation state is a
/// **pose**. Keeping them separate is what lets `muscle` and `pigu` be
/// performances rather than conditions — they are the two states the designer
/// gave an intro flourish to, and they belong to a playbook triggered by an
/// event, not to the ambient machine.
///
/// The rules themselves live in `pibo-core` beside the existing six-state
/// machine — both platforms have to agree on what Pibo is doing. This type is
/// the thin app-side seam: it asks Core, then clamps the answer to the states
/// whose artwork has actually shipped, so a Core decision that runs ahead of the
/// port degrades to `default` instead of rendering nothing.
enum PiboAnimationStateMap {
    static let fallback = "default"

    /// States with runtime artwork in this build. Core knows all twelve; the
    /// other six are `scope: deferred` in the asset manifest.
    static let available: Set<String> = ["default", "muscle", "pigu", "sleep-1", "sleep-2", "awake"]

    /// The ambient pose for a condition.
    static func ambientStateID(
        for state: PiboActivityState,
        stressZ: Double = 0,
        hasStressBaseline: Bool = false,
        sleptWell: Bool = true,
        lowEnergyDays: UInt32 = 0
    ) -> String {
        let decided = PiboCoreAnimationAdapter.ambientStateID(
            for: state,
            stressZ: stressZ,
            hasStressBaseline: hasStressBaseline,
            sleptWell: sleptWell,
            lowEnergyDays: lowEnergyDays
        )
        return available.contains(decided) ? decided : fallback
    }

    /// The performance played when a workout lands: 秀肌肉 → 娇羞 → 回常驻态.
    static let workoutCelebration: [PiboCharacterPlaybook.Beat] = [
        .init("muscle", hold: 2.0),
        .init("pigu", hold: 2.0),
    ]

    /// Whether a state belongs to the coconut, which decides hard cut vs morph.
    static func isNestState(_ stateID: String, data: PiboCharacterData?) -> Bool {
        data?.transition.zones["nest"]?.contains(stateID) ?? false
    }
}

/// Gates the vector character while it lands.
///
/// The shipping home still runs the two-sprite Pibo; this flag lets the two be
/// compared side by side on a device instead of trusting a screenshot, and keeps
/// a half-integrated character from reaching anyone. Remove it once the vector
/// path passes on device.
enum PiboVectorCharacterFlag {
    static let defaultsKey = "pibo.character.vector.v1"

    static var isEnabled: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PiboVectorCharacter") { return true }
        if ProcessInfo.processInfo.arguments.contains("-PiboLegacyCharacter") { return false }
        #endif
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }
}

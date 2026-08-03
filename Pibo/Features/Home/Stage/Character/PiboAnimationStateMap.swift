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

    /// Stable semantic IDs shipped by pibo-assets 0.3.0.
    static let available: Set<String> = [
        "default", "muscle", "pigu", "sleep-1", "sleep-2", "awake",
        "weak", "angry", "boring", "tired", "dive", "coolhide",
    ]

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

    /// The idle the home runs while it holds an achievement pose.
    ///
    /// The source integration swaps the whole combo for a single breath the
    /// moment the celebration closes (`setIdleOverride` in
    /// `pibo_design/integration/harmony-home-preview/index.html`): the flourish
    /// belongs to the Modal, and what stays on the home is the pose plus a
    /// breath taken from the character's own contact point.
    ///
    /// Only `muscle` holds. 运动完成的 `pigu` 只在成果卡片里演一次，主场景不保留
    /// 那个姿势，所以它在设计包里的那条 override（4.2s / 0.018 / `165px 292px`）
    /// 没有落点 —— 不是漏了。
    ///
    /// Authored as the source's own config shape because these are design
    /// numbers; decoding them keeps a single interpretation of `origin`,
    /// `amplitude` and `duration` shared with every other idle.
    static func holdIdle(for stateID: String) -> PiboCharacterData.Idle? {
        stateID == "muscle" ? muscleHoldIdle : nil
    }

    private static let muscleHoldIdle = decodeIdle(
        #"{"kind":"breathe-y","duration":4.2,"amplitude":0.018,"origin":"150px 270px"}"#
    )

    private static func decodeIdle(_ json: String) -> PiboCharacterData.Idle? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PiboCharacterData.Idle.self, from: data)
    }

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
        if UserDefaults.standard.object(forKey: defaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }
}

import CoreGraphics

/// The reviewed "长好了，留在头顶" maturity motion (pibo_design
/// animation-review-v4 `boRipe`), expressed as relative offsets over Pibo's
/// current v5 expression. Same curve as HarmonyOS `PiboBoRipeMotion.ets`.
///
/// It is presentation only: maturity itself comes from the ledger, and the
/// state that decides participation was already chosen by Core.
enum PiboBoRipeMotion {
    static let duration: Double = 6.8
    static let reducedDuration: Double = 0.32

    struct Pose: Equatable {
        /// 0...1 portion of the remaining container filled.
        var fill: CGFloat
        var glow: CGFloat
        /// Design units, Y-down.
        var faceY: CGFloat
        var eye: CGFloat
        /// Left hand rotation in degrees.
        var arm: CGFloat
        /// Extra sprout tilt in degrees.
        var sprout: CGFloat
        var bodyScaleY: CGFloat
    }

    /// Sleeping keeps its eyes shut and body still; tired and waking join in
    /// with less energy. This is visual amplitude, never a state change.
    static func participation(stateID: String) -> CGFloat {
        if stateID.contains("sleeping") { return 0 }
        if stateID.contains("tired") { return 0.45 }
        if stateID.contains("waking") { return 0.55 }
        return 1
    }

    static func pose(seconds: Double, participation: CGFloat, reduced: Bool) -> Pose {
        let t = seconds.isFinite ? min(max(seconds, 0), duration) : 0
        let k = reduced ? 0 : min(max(participation, 0), 1)
        let attention = envelope(t, 0.5, 1.1, 3.8, 5.6)
        return Pose(
            fill: reduced ? 1 : curve(t, [(0, 0), (1.1, 0), (2.7, 1)]),
            glow: reduced ? 0 : envelope(t, 1.1, 2.2, 3.3, 4.6),
            faceY: (-7 * attention + 3 * envelope(t, 4.15, 4.55, 4.7, 5.25)) * k,
            eye: 1 + 0.2 * attention * k,
            arm: -6 * envelope(t, 2.5, 3.4, 4, 5.7) * k,
            sprout: curve(t, [(0, 0), (1.1, 0), (2.1, 4), (3.4, -2.5), (4.2, 1.3), (5.3, 0)]) * k,
            bodyScaleY: 1 + 0.025 * envelope(t, 3.6, 4.4, 4.7, 6.1) * k
        )
    }

    private static func curve(_ t: Double, _ keys: [(Double, CGFloat)]) -> CGFloat {
        guard let first = keys.first else { return 0 }
        if t <= first.0 { return first.1 }
        for index in 1..<keys.count where t <= keys[index].0 {
            let (t0, v0) = keys[index - 1]
            let (t1, v1) = keys[index]
            let u = CGFloat((t - t0) / (t1 - t0))
            let smooth = u * u * u * (u * (u * 6 - 15) + 10)
            return v0 + (v1 - v0) * smooth
        }
        return keys[keys.count - 1].1
    }

    private static func envelope(_ t: Double, _ a: Double, _ b: Double, _ c: Double, _ d: Double) -> CGFloat {
        curve(t, [(0, 0), (a, 0), (b, 1), (c, 1), (d, 0)])
    }
}

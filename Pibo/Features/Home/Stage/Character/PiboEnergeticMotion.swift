import CoreGraphics

/// Energetic as rhythm, not proportion (2026-09-16, shared with HarmonyOS
/// `PiboEnergeticMotion.ets`).
///
/// The approved clip holds "energetic" as a narrow, tall, lifted posture that
/// reads as a stretched Pibo. The renderer undoes that authored rest scale so
/// the silhouette matches stable, then adds a two-beat hop: crouch, push off,
/// float, land, rebound — the second beat half size — and a still beat with a
/// quick double blink. Presentation only; Core already chose the state.
enum PiboEnergeticMotion {
    static let cycleSeconds: Double = 3.6
    static let pivot = CGPoint(x: 150, y: 282)

    private static let restScaleY: CGFloat = 0.995
    private static let widthCoupling: CGFloat = 0.62
    private static let apexLift: CGFloat = 15
    private static let eyeBase: CGFloat = 1.05

    struct Pose: Equatable {
        var scaleX: CGFloat
        var scaleY: CGFloat
        /// Design units, Y-down; negative lifts Pibo off the ground.
        var lift: CGFloat
        var eye: CGFloat
        /// Degrees the hands swing outwards.
        var hand: CGFloat
        /// Design units the feet tuck up.
        var leg: CGFloat
        /// Degrees of sprout whip lagging the body.
        var sprout: CGFloat
    }

    private static let blinkKeys: [(Double, CGFloat)] = [
        (0, 1), (1.74, 1), (1.79, 0.12), (1.84, 1), (1.9, 1), (1.95, 0.12), (2, 1),
    ]
    private static let liftKeys: [(Double, CGFloat)] = [
        (0, 0), (0.55, 0), (0.68, 3.2), (0.79, -2), (0.96, -apexLift), (1.12, -apexLift),
        (1.3, 0), (1.4, 3.4), (1.52, 0), (1.62, -1.2), (1.74, 0),
        (2.05, 0), (2.15, 2.2), (2.25, -1), (2.38, -apexLift * 0.52), (2.52, -apexLift * 0.52),
        (2.66, 0), (2.74, 2.4), (2.86, 0), (3.0, 0), (cycleSeconds, 0),
    ]
    private static let scaleYKeys: [(Double, CGFloat)] = [
        (0, restScaleY), (0.55, restScaleY), (0.68, 0.93), (0.79, 1.07), (0.9, 1), (1.12, 1),
        (1.3, 1), (1.4, 0.94), (1.5, 1.025), (1.6, restScaleY),
        (2.05, restScaleY), (2.15, 0.96), (2.24, 1.04), (2.34, 1), (2.52, 1),
        (2.66, 1), (2.74, 0.965), (2.84, 1.02), (2.94, restScaleY),
        (cycleSeconds, restScaleY),
    ]

    static func pose(seconds: Double, reduced: Bool) -> Pose {
        guard !reduced, seconds.isFinite else {
            return Pose(scaleX: 1 + (1 - restScaleY) * widthCoupling, scaleY: restScaleY,
                        lift: 0, eye: eyeBase, hand: 0, leg: 0, sprout: 0)
        }
        let t = max(0, seconds).truncatingRemainder(dividingBy: cycleSeconds)
        let lift = curve(t, liftKeys)
        let scaleY = curve(t, scaleYKeys)
        let scaleX = 1 + (1 - scaleY) * widthCoupling
        let airborne = min(max(-lift / apexLift, 0), 1)
        let squash = min(max((1 - scaleY) / 0.07, 0), 1)
        let previous = curve((t - 0.06 + cycleSeconds).truncatingRemainder(dividingBy: cycleSeconds), liftKeys)
        let velocity = (lift - previous) / 0.06
        return Pose(
            scaleX: scaleX,
            scaleY: scaleY,
            lift: lift,
            eye: eyeBase * (1 + 0.08 * airborne - 0.16 * squash) * curve(t, blinkKeys),
            hand: 12 * airborne,
            leg: 3.2 * airborne,
            sprout: min(max(velocity * 0.32, -10), 10)
        )
    }

    /// Scale about `pivot`, then lift. Composes after a part's own matrix.
    static func bodyTransform(scaleX: CGFloat, scaleY: CGFloat, lift: CGFloat) -> CGAffineTransform {
        CGAffineTransform(
            a: scaleX, b: 0, c: 0, d: scaleY,
            tx: pivot.x - pivot.x * scaleX,
            ty: pivot.y - pivot.y * scaleY + lift
        )
    }

    private static func curve(_ t: Double, _ keys: [(Double, CGFloat)]) -> CGFloat {
        guard let first = keys.first else { return 0 }
        if t <= first.0 { return first.1 }
        for index in 1..<keys.count where t <= keys[index].0 {
            let (t0, v0) = keys[index - 1]
            let (t1, v1) = keys[index]
            let u = CGFloat((t - t0) / (t1 - t0))
            return v0 + (v1 - v0) * u * u * u * (u * (u * 6 - 15) + 10)
        }
        return keys[keys.count - 1].1
    }
}

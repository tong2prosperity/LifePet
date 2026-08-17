import CoreGraphics
import SpriteKit

/// A lightweight six-segment rig for the canonical Pibo head sprout.
///
/// SpriteKit does not expose a 2D bone/skin system, so the chain is solved as
/// damped angular springs and skinned onto a 3 x 7 `SKWarpGeometryGrid`. The
/// bottom row never moves; progressively softer upper segments create the
/// delayed, flag-like motion at the tip.
final class PiboHeadRigDeformer {
    private struct BoneState {
        var angle: CGFloat = 0
        var angularVelocity: CGFloat = 0
    }

    private static let columnCount = 2
    private static let rowCount = 6
    private static let pivotX: CGFloat = 20.3862 / 31
    private static let maximumAngle: CGFloat = .pi * 0.24
    private static let canonicalImageName = "forest_pibo_head"

    /// Any `SKWarpable` — the legacy theme drives a sprite, the vector character
    /// drives the `SKEffectNode` that hosts its sprout paths. The rig only ever
    /// writes a warp mesh, so it does not care which it is.
    private weak var target: (SKNode & SKWarpable)?
    private var bones = Array(repeating: BoneState(), count: rowCount)
    private var dragTarget: CGFloat?
    private var sourcePositions: [SIMD2<Float>] = []
    private var axisInverted = false
    /// Where the root sits across the warp box, 0...1. The legacy head sprite has
    /// a fixed value baked from its SVG; the vector sprout supplies it per state,
    /// because the leaf attaches at a different point in each pose.
    private var pivotFraction: CGFloat = PiboHeadRigDeformer.pivotX
    private var displayedGrowth: CGFloat = 1
    private var growthStart: CGFloat = 1
    private var growthTarget: CGFloat = 1
    private var growthElapsed: TimeInterval = 0
    private var growthDuration: TimeInterval = 0

    private(set) var isEnabled = false
    /// 0 is a rigid sprout and 1 is a soft, flag-like sprout.
    var flexibility: CGFloat = 0.68 {
        didSet { flexibility = min(max(flexibility, 0), 1) }
    }

    init() {
        sourcePositions = Self.makeSourcePositions()
    }

    func attach(to sprite: SKSpriteNode, imageName: String?) {
        attach(to: sprite, enabled: imageName == Self.canonicalImageName && sprite.texture != nil)
    }

    /// Attaches to the vector character's sprout host.
    ///
    /// `axisInverted` mirrors the mesh so row zero still lands on the root: the
    /// rig's whole model is "the root is pinned, the tip is soft", and `awake`
    /// hangs out of the coconut hole with its tip *below* its root. Without the
    /// mirror that state would bend from the wrong end.
    func attach(toSprout host: SKNode & SKWarpable, axisInverted: Bool, pivotFraction: CGFloat) {
        self.axisInverted = axisInverted
        self.pivotFraction = min(max(pivotFraction, 0), 1)
        sourcePositions = Self.makeSourcePositions(inverted: axisInverted)
        attach(to: host, enabled: true)
    }

    /// Updates the root anchor without rebuilding the attachment — the sprout's
    /// root travels as states morph.
    func setPivotFraction(_ fraction: CGFloat) {
        pivotFraction = min(max(fraction, 0), 1)
    }

    private func attach(to warpable: SKNode & SKWarpable, enabled: Bool) {
        target = warpable
        isEnabled = enabled
        dragTarget = nil
        bones = Array(repeating: BoneState(), count: Self.rowCount)

        guard isEnabled else {
            warpable.warpGeometry = nil
            warpable.subdivisionLevels = 0
            return
        }
        warpable.subdivisionLevels = 2
        applyGeometry()
    }

    func update(
        time: TimeInterval,
        deltaTime: TimeInterval,
        wind: StageWind,
        reduceMotion: Bool
    ) {
        guard isEnabled, target != nil else { return }
        updateGrowth(deltaTime: deltaTime, reduceMotion: reduceMotion)
        let dt = CGFloat(min(max(deltaTime, 0), 1.0 / 30.0))
        guard dt > 0 else {
            applyGeometry()
            return
        }

        let motionScale: CGFloat = reduceMotion ? 0.16 : 1
        let strength = min(max(wind.strength, 0), 1.5) * motionScale
        let gustiness = min(max(wind.gustiness, 0), 1.5)
        let direction = min(max(wind.direction.dx, -1), 1)
        let t = CGFloat(time)

        for index in bones.indices {
            let progress = CGFloat(index + 1) / CGFloat(Self.rowCount)
            let influence = pow(progress, 1.18)
            let phase = CGFloat(index) * 0.115
            let idle = sin(t * 1.18 - phase) * 0.020 * motionScale
            let response = 0.62 + flexibility * 0.62
            let steady = direction * strength * response
                * (0.075 + sin(t * 1.02 - phase) * 0.060)
            let gust = direction * strength * gustiness * response
                * sin(t * 0.31 + 1.7)
                * sin(t * 1.91 - phase * 1.6)
                * 0.105
            let interaction = (dragTarget ?? 0) * influence
            let target = (idle + steady + gust) * influence + interaction

            // The root is comparatively rigid while the tip is deliberately
            // soft and under-damped, creating visible propagation and recoil.
            let stiffness = max(
                10,
                (58 - flexibility * 15) - CGFloat(index) * (4.2 + flexibility * 1.8)
            )
            let dampingRatio = (0.88 - flexibility * 0.24) - CGFloat(index) * 0.018
            let damping = 2 * sqrt(stiffness) * dampingRatio
            bones[index].angularVelocity += (
                (target - bones[index].angle) * stiffness
                    - bones[index].angularVelocity * damping
            ) * dt
            bones[index].angle += bones[index].angularVelocity * dt
            bones[index].angle = min(
                max(bones[index].angle, -Self.maximumAngle * (0.45 + flexibility * 0.55)),
                Self.maximumAngle * (0.45 + flexibility * 0.55)
            )
        }
        applyGeometry()
    }

    /// Reveals the canonical vector sprout from its attachment point. Core owns
    /// the semantic stages; this renderer consumes the persisted ledger's exact
    /// 0...1 progress without re-creating any thresholds.
    func setGrowthProgress(_ progress: CGFloat) {
        let value = Self.clamp01(progress)
        displayedGrowth = value
        growthStart = value
        growthTarget = value
        growthElapsed = 0
        growthDuration = 0
        applyGeometry()
    }

    func animateGrowth(from start: CGFloat, to target: CGFloat, duration: TimeInterval) {
        growthStart = Self.clamp01(start)
        growthTarget = Self.clamp01(target)
        displayedGrowth = growthStart
        growthElapsed = 0
        growthDuration = max(0, duration)
        if growthDuration == 0 { displayedGrowth = growthTarget }
        applyGeometry()
    }

    func beginInteraction() {
        guard isEnabled else { return }
        dragTarget = 0
    }

    func setInteraction(horizontalDisplacement: CGFloat, upwardDisplacement: CGFloat) {
        guard isEnabled else { return }
        let horizontal = Self.rubberBand(horizontalDisplacement, limit: 110) / 110
        let lift = Self.rubberBand(max(0, upwardDisplacement), limit: 130) / 130
        dragTarget = horizontal * (0.42 + lift * 0.18)
    }

    func endInteraction(pulled: Bool) {
        guard isEnabled else { return }
        let release = dragTarget ?? 0
        dragTarget = nil
        let impulse = -release * (pulled ? 7.2 : 4.2)
        for index in bones.indices {
            let influence = CGFloat(index + 1) / CGFloat(Self.rowCount)
            bones[index].angularVelocity += impulse * influence
        }
    }

    func addImpulse(_ impulse: CGFloat) {
        guard isEnabled else { return }
        for index in bones.indices {
            let influence = pow(CGFloat(index + 1) / CGFloat(Self.rowCount), 1.2)
            bones[index].angularVelocity += impulse * influence
        }
    }

    private func applyGeometry() {
        guard let target, isEnabled else { return }
        let destinations = destinationPositions()
        target.warpGeometry = SKWarpGeometryGrid(
            columns: Self.columnCount,
            rows: Self.rowCount,
            sourcePositions: sourcePositions,
            destinationPositions: destinations
        )
    }

    private func destinationPositions() -> [SIMD2<Float>] {
        let segmentLength = 1 / CGFloat(Self.rowCount)
        var centers = [CGPoint(x: pivotFraction, y: 0)]
        for (index, bone) in bones.enumerated() {
            let activation = segmentActivation(index)
            let previous = centers[centers.count - 1]
            centers.append(CGPoint(
                x: previous.x + sin(bone.angle * activation) * segmentLength * activation,
                y: previous.y + cos(bone.angle * activation) * segmentLength * activation
            ))
        }

        var result: [SIMD2<Float>] = []
        result.reserveCapacity((Self.columnCount + 1) * (Self.rowCount + 1))
        for row in 0 ... Self.rowCount {
            // The cross-section follows the preceding segment. Row zero stays
            // exactly at rest, which pins the sprout to Pibo's head.
            let activation = row == 0 ? 1 : segmentActivation(row - 1)
            let angle = row == 0 ? 0 : bones[row - 1].angle * activation
            let center = centers[row]
            for column in 0 ... Self.columnCount {
                let sourceX = CGFloat(column) / CGFloat(Self.columnCount)
                // Keep the attachment row fixed. Higher cross-sections unfurl
                // from a narrow fold as each bone becomes active.
                let width = row == 0 ? 1 : 0.12 + activation * 0.88
                let offset = (sourceX - pivotFraction) * width
                let x = center.x + cos(angle) * offset
                let y = center.y - sin(angle) * offset
                result.append(SIMD2(Float(x), Float(axisInverted ? 1 - y : y)))
            }
        }
        return result
    }

    private func updateGrowth(deltaTime: TimeInterval, reduceMotion: Bool) {
        guard growthDuration > 0, displayedGrowth != growthTarget else { return }
        if reduceMotion {
            displayedGrowth = growthTarget
            growthDuration = 0
            return
        }
        growthElapsed = min(growthDuration, growthElapsed + max(0, deltaTime))
        let t = CGFloat(growthElapsed / growthDuration)
        let eased = t * t * (3 - 2 * t)
        displayedGrowth = growthStart + (growthTarget - growthStart) * eased
        if growthElapsed >= growthDuration {
            displayedGrowth = growthTarget
            growthDuration = 0
        }
    }

    private func segmentActivation(_ index: Int) -> CGFloat {
        // Reveal from root to tip. A small overlap avoids visible pauses as the
        // next segment starts extending.
        let raw = displayedGrowth * CGFloat(Self.rowCount + 1) - CGFloat(index) * 0.82
        let t = Self.clamp01(raw)
        return t * t * (3 - 2 * t)
    }

    private static func makeSourcePositions(inverted: Bool = false) -> [SIMD2<Float>] {
        var result: [SIMD2<Float>] = []
        result.reserveCapacity((columnCount + 1) * (rowCount + 1))
        for row in 0 ... rowCount {
            let v = Float(row) / Float(rowCount)
            for column in 0 ... columnCount {
                result.append(SIMD2(Float(column) / Float(columnCount), inverted ? 1 - v : v))
            }
        }
        return result
    }

    private static func rubberBand(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        limit * value / (abs(value) + limit)
    }

    private static func clamp01(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

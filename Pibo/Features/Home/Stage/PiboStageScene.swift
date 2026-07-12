import SpriteKit
import SwiftUI
import UIKit

// MARK: - Pibo home stage (SpriteKit)
//
// The home activity zone is a SpriteKit scene (chosen for the growing amount of
// 2D-game-like animation: flowing water, foliage, atmosphere, idle motion,
// 拍一拍 reactions, 拔毛, 头顶毛/能量收集, and particles). SwiftUI owns chrome.
//
// Data in: a `PiboTheme` (scene backdrop + head item), a `PiboGrowthStage`
// (魔丸 「?」卷芽 ⇄ 发芽带叶), and a `PiboActivityState` (drives Pibo's
// face/posture). Touches are region-routed: a tap on the body calls `onPat`,
// a drag on the head 毛 bends it and fires `onHairPulled` on release — the
// SwiftUI layer decides how Pibo reacts (the spec's caps live in
// `PetStateStore.pat()`; the pull is 拔毛 when the window is open). Two 场景内
// No camera pan / 横向逛场景 — the stage is a single fixed portrait forest.
//
// Node tree (z back→front): backdrop(sky → ground) → 场景 icons → pibo(shadow,
// body, eyes, blush, head 毛) → overhead 黑洞 → fx (Zzz / sparkles / seeds). A
// `SKCameraNode` frames the scene; the 发芽 close-up zooms it onto the head.

/// Phases of the 发芽 close-up (Figma《识别到用户的活动》74:6102), reported back
/// so the SwiftUI overlay can swap its caption in sync.
enum SproutCloseupPhase {
    case shaking    // 毛抖动 — "收集到你的运动能量！"
    case sprouted   // 长出叶片 — "Pibo...发芽了啵！"
    case finished   // 缩回主页面 — show the 能量已收集 pop
}

final class PiboStageScene: SKScene {

    // — Inputs (set by the SwiftUI wrapper) —
    private(set) var theme: PiboTheme = .sprout
    private(set) var activityState: PiboActivityState = .idle
    private(set) var growth: PiboGrowthStage = .mystery
    private(set) var environment: ForestEnvironmentSnapshot = .daylight
    /// Fired on a tap that lands on Pibo's body (拍一拍).
    var onPat: (() -> Void)?
    /// Fired when the head 毛 is dragged past the pull threshold and released —
    /// the 拔毛 gesture. The scene plays the local snap-back; the SwiftUI layer
    /// decides what the pull *means* (collect the seed / an annoyed turn-away).
    var onHairPulled: (() -> Void)?
    /// Direct manipulation asks the SwiftUI bridge for the display's maximum
    /// cadence until the touch ends or is cancelled.
    var onDirectManipulationChanged: ((Bool) -> Void)?
    /// Authored reactions request a temporary high-refresh lease. Overlapping
    /// leases are coalesced by `PiboStageRenderController`.
    var onHighRefreshRequested: ((TimeInterval) -> Void)?

    // — Nodes —
    private let backdrop = SKNode()      // legacy backdrop or layered forest
    private let forestFoliageLayer = SKNode()
    private var forestFoliage: [ForestFoliageNode] = []
    private var forestWaterNode: SKSpriteNode?
    private var morningLightNode: SKSpriteNode?
    private let firefliesNode = SKNode()
    private var fireflyEmitter: SKEmitterNode?
    private let atmosphereNode = SKNode()
    private let multiplyOverlay = SKSpriteNode(color: .clear, size: .zero)
    private let screenOverlay = SKSpriteNode(color: .clear, size: .zero)
    private let pibo = SKNode()          // body group (bobs as a unit)
    private var bodyNode: SKShapeNode?   // procedural egg body
    private var bodySprite: SKSpriteNode? // art body (when theme.bodyImage set)
    private var leftEye = SKNode()
    private var rightEye = SKNode()
    private var blush = SKNode()
    private var headNode = SKSpriteNode()
    private let overheadNode = SKSpriteNode()  // 魔丸黑洞 — floats above the head
    private let fx = SKNode()            // transient effects layer
    private let rainBack = SKNode()      // 雨幕(Pibo 之后 — 景深层)
    private let rainFront = SKNode()     // 水花 + 滴在 Pibo(Pibo 之前)
    private let cam = SKCameraNode()
    private var splashPool: [SKSpriteNode] = []
    private var nextSplashPoolIndex = 0
    private var lastUpdateTime: TimeInterval = 0
    private var flowTime: Float = 0
    private var lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var tuning: ForestSceneTuning = .standard

    #if DEBUG
    private struct WaterDebugTuning {
        var speed: Float
        var rippleStrength: Float
        var highlightStrength: Float
        var showMask: Bool
    }
    private var waterDebugTuning: WaterDebugTuning?
    #endif

    private var built = false
    /// True while the 发芽 close-up owns the camera (blocks pats + relayouts
    /// from snapping the camera back mid-flight).
    private var closeupActive = false

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = SKColor(theme.scene.skyBottom)
        if size.width > 1, size.height > 1 { buildIfNeeded() }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let wasBuilt = built
        buildIfNeeded()
        guard wasBuilt else { return }
        rebuildBackdrop()
        rebuildPibo()
        layoutAll()
        applyAtmosphere(animated: false)
        if environment.rainIntensity > 0 { applyWeather() }
    }

    override func update(_ currentTime: TimeInterval) {
        // Belt-and-suspenders: if the scene wasn't built by didMove/didChangeSize
        // (SwiftUI SpriteView size timing), build as soon as a valid size lands.
        if !built, size.width > 1, size.height > 1 { buildIfNeeded() }
        guard built else { return }
        let delta = lastUpdateTime > 0 ? min(currentTime - lastUpdateTime, 1.0 / 15.0) : 0
        lastUpdateTime = currentTime
        guard theme.id == PiboTheme.forest.id else { return }

        flowTime.formTruncatingRemainder(dividingBy: 120)
        flowTime += Float(delta)
        forestWaterNode?.shader?.uniformNamed("u_flow_time")?.floatValue = flowTime
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        var tunedWind = environment.wind
        tunedWind.strength *= CGFloat(tuning.foliageMotionScale)
        for leaf in forestFoliage {
            leaf.update(time: currentTime, deltaTime: delta, wind: tunedWind, reduceMotion: reduceMotion)
        }
    }

    // MARK: Public API (called from the SwiftUI wrapper)

    func apply(theme newTheme: PiboTheme, state newState: PiboActivityState, growth newGrowth: PiboGrowthStage) {
        let themeChanged = newTheme.id != theme.id
        let growthChanged = newGrowth != growth
        let stateChanged = newState != activityState
        theme = newTheme
        activityState = newState
        growth = newGrowth
        if themeChanged { backgroundColor = SKColor(newTheme.scene.skyBottom) }
        guard built else { return }
        // A theme may switch between art and procedural Pibo, so rebuild the body
        // group (not just the backdrop/head) when the theme changes.
        if themeChanged {
            let forest = newTheme.id == PiboTheme.forest.id
            pibo.zPosition = forest ? 20 : 0
            overheadNode.zPosition = forest ? 33 : 13
            rainBack.zPosition = forest ? 24 : 5
            rebuildBackdrop()
            rebuildPibo()
            layoutAll()
            applyAtmosphere(animated: false)
            if environment.rainIntensity > 0 { applyWeather() }
        } else if growthChanged {
            rebuildHead()
            if environment.rainIntensity > 0 { rebuildPiboSurface() }
        }
        if stateChanged || themeChanged { applyState(animated: true) }
    }

    func setEnvironment(_ newEnvironment: ForestEnvironmentSnapshot) {
        guard newEnvironment != environment else { return }
        let rainChanged = newEnvironment.rainIntensity != environment.rainIntensity
        let phaseChanged = newEnvironment.dayPhase != environment.dayPhase
        environment = newEnvironment
        guard built else { return }
        if phaseChanged { applyAtmosphere(animated: true) }
        updateWaterLighting()
        if rainChanged { applyWeather() }
    }

    func setLowPowerMode(_ enabled: Bool) {
        guard lowPowerModeEnabled != enabled else { return }
        lowPowerModeEnabled = enabled
        applyWaterPerformanceUniforms()
        updateFireflies(animated: false)
        if environment.rainIntensity > 0 { applyWeather() }
    }

    func setTuning(_ newTuning: ForestSceneTuning) {
        let sanitized = newTuning.sanitized
        guard sanitized != tuning else { return }
        let visibilityChanged = sanitized.piboVisible != tuning.piboVisible
        tuning = sanitized
        guard built else { return }
        applyTuning(visibilityChanged: visibilityChanged)
    }

    #if DEBUG
    /// WaterLab uses the production scene, texture, and shader. Keeping tuning
    /// here prevents the debug page from drifting into a second water renderer.
    func setWaterDebugTuning(
        speed: Double,
        rippleStrength: Double,
        highlightStrength: Double,
        showMask: Bool
    ) {
        waterDebugTuning = WaterDebugTuning(
            speed: Float(speed),
            rippleStrength: Float(rippleStrength),
            highlightStrength: Float(highlightStrength),
            showMask: showMask
        )
        applyWaterPerformanceUniforms()
        updateWaterLighting()
        forestWaterNode?.shader?.uniformNamed("u_mask_preview")?.floatValue = showMask ? 1 : 0
    }
    #endif

    /// 能量收集 — the head 毛 senses new energy: shake → grow → settle, with a
    /// little sparkle burst (spec §3.4). The small in-place animation, used when
    /// the head is already sprouted (the first collection plays the close-up).
    func playEnergyGain() {
        guard built else { return }
        onHighRefreshRequested?(1.0)
        headNode.removeAction(forKey: "headIdle")
        let shake = SKAction.sequence([
            .rotate(toAngle: 0.18, duration: 0.06),
            .rotate(toAngle: -0.18, duration: 0.10),
            .rotate(toAngle: 0.10, duration: 0.08),
            .rotate(toAngle: 0, duration: 0.08),
        ])
        let grow = SKAction.sequence([.scale(to: 1.18, duration: 0.18), .scale(to: 1.0, duration: 0.22)])
        headNode.run(.sequence([shake, grow])) { [weak self] in self?.startHeadIdle() }
        emitSparkles(at: CGPoint(x: pibo.position.x, y: pibo.position.y + bodyHeight * 0.7), count: 14)
    }

    /// 发芽 close-up (Figma 74:6102): the camera zooms onto Pibo's head, the 毛
    /// 抖动 (shake) → 发力 (strain) → 长出叶片 (texture swaps to the sprouted
    /// sprite, the 黑洞 fades), then the camera pulls back.
    ///
    /// **Animation seam:** this is the shipped placeholder built from current
    /// assets. The designer's final close-up (Lottie, per the Figma note
    /// 暂定为lottie素材) plugs in at `SproutAnimationStyle` in
    /// `EnergySproutFlow.swift` — when it lands, the SwiftUI overlay plays it
    /// full-screen instead of calling this.
    func playSproutCloseup(onPhase: @escaping (SproutCloseupPhase) -> Void) {
        guard built, !closeupActive else { onPhase(.finished); return }
        onHighRefreshRequested?(5.0)
        closeupActive = true
        headNode.removeAction(forKey: "headIdle")

        // Frame the head with a hint of the body top, like the Figma close-up.
        let headWorld = CGPoint(x: pibo.position.x + headNode.position.x,
                                y: pibo.position.y + headNode.position.y)
        let focus = CGPoint(x: headWorld.x, y: headWorld.y - size.height * 0.06)
        let zoomIn = SKAction.group([.move(to: focus, duration: 0.55), .scale(to: 0.45, duration: 0.55)])
        zoomIn.timingMode = .easeInEaseOut
        let zoomOut = SKAction.group([
            .move(to: CGPoint(x: size.width / 2, y: size.height / 2), duration: 0.55),
            .scale(to: 1.0, duration: 0.55),
        ])
        zoomOut.timingMode = .easeInEaseOut

        // 毛抖动 — escalating wiggle (~1.7s).
        var swings: [SKAction] = []
        for (angle, dur) in [(0.10, 0.10), (-0.12, 0.16), (0.16, 0.14), (-0.20, 0.16),
                             (0.24, 0.14), (-0.26, 0.16), (0.30, 0.14), (-0.30, 0.16)] {
            let r = SKAction.rotate(toAngle: CGFloat(angle), duration: dur)
            r.timingMode = .easeInEaseOut
            swings.append(r)
        }
        let wiggle = SKAction.sequence(swings)

        // 发力 → 长出叶片: squash, swap to the sprouted sprite, burst back.
        let strain = SKAction.scale(to: 0.78, duration: 0.22)
        strain.timingMode = .easeIn
        let swap = SKAction.run { [weak self] in
            guard let self else { return }
            self.growth = .sprouted
            self.rebuildHead()
            self.overheadNode.run(.fadeOut(withDuration: 0.45))
            self.emitSparkles(at: headWorld, count: 18)
        }
        let burst = SKAction.sequence([.scale(to: 1.25, duration: 0.20), .scale(to: 1.0, duration: 0.24)])
        burst.timingMode = .easeOut

        let camScript = SKAction.sequence([
            zoomIn,
            .run { onPhase(.shaking) },
            .wait(forDuration: 1.7 + 0.42),          // wiggle + strain run on the head
            .run { onPhase(.sprouted) },
            .wait(forDuration: 1.5),
            zoomOut,
            .run { [weak self] in
                self?.closeupActive = false
                self?.startHeadIdle()
                onPhase(.finished)
            },
        ])
        let headScript = SKAction.sequence([
            .wait(forDuration: 0.55),
            wiggle,
            .rotate(toAngle: 0, duration: 0.08),
            strain,
            swap,
            burst,
        ])
        cam.run(camScript, withKey: "closeup")
        headNode.run(headScript, withKey: "sprout")
    }

    /// 拍一拍 不理睬 — Pibo 扭过头背对用户 (Figma 76:7115): hop, swap the body to
    /// the turned-away art, hold, turn back. Procedural themes just swivel.
    func playTurnAway() {
        guard built else { return }
        onHighRefreshRequested?(2.1)
        if let backName = theme.bodyBackImage, let body = bodySprite {
            guard body.action(forKey: "turnAway") == nil else { return }
            let frontTexture = body.texture
            let frontSize = body.size
            let backTexture = SKTexture(imageNamed: backName)
            let nat = backTexture.size()
            let backWidth = size.width * (232.0 / 393.0)
            let backSize = CGSize(width: backWidth, height: backWidth * nat.height / max(nat.width, 1))
            let turnBack = SKAction.run {
                body.texture = backTexture
                body.size = backSize
                // Bottom-align so the feet stay planted (the back pose is shorter).
                body.position.y = -(frontSize.height - backSize.height) / 2
            }
            let turnFront = SKAction.run {
                body.texture = frontTexture
                body.size = frontSize
                body.position.y = 0
            }
            let hop = SKAction.sequence([
                .scaleX(to: 0.86, y: 1.04, duration: 0.10),
                .scaleX(to: 1.0, y: 1.0, duration: 0.12),
            ])
            body.run(.sequence([hop, turnBack, .wait(forDuration: 1.4), turnFront, hop.copy() as! SKAction]),
                     withKey: "turnAway")
        } else {
            // Procedural fallback: a sulky swivel away.
            pibo.run(.sequence([
                .rotate(toAngle: 0.45, duration: 0.18),
                .wait(forDuration: 1.2),
                .rotate(toAngle: 0, duration: 0.22),
            ]))
        }
    }

    /// 拔毛 — a seed drops from the head and falls to the ground.
    func playPluck(color: SKColor) {
        guard built else { return }
        onHighRefreshRequested?(1.4)
        let seed = SKShapeNode(ellipseOf: CGSize(width: 14, height: 18))
        seed.fillColor = color
        seed.strokeColor = .clear
        seed.position = CGPoint(x: pibo.position.x, y: pibo.position.y + bodyHeight * 0.65)
        seed.zPosition = 50
        fx.addChild(seed)
        let drop = SKAction.moveBy(x: CGFloat.random(in: -16...16), y: -bodyHeight * 0.5, duration: 0.8)
        drop.timingMode = .easeIn
        seed.run(.sequence([.wait(forDuration: 0.1), drop, .fadeOut(withDuration: 0.4), .removeFromParent()]))
        headNode.run(.sequence([.rotate(byAngle: 0.2, duration: 0.08), .rotate(byAngle: -0.2, duration: 0.12)]))
    }

    // MARK: Touch → 拍一拍 (body) / 拖毛 (hair)

    /// Which sprite region a scene point lands in. The 毛 wins where it overlaps
    /// the body (it grows out of the body top), and its box is padded out to at
    /// least 44pt per side (HIG minimum — the 桃花枝 art is only ~38pt wide).
    private enum HitRegion { case hair, body, none }

    private func hitRegion(at p: CGPoint) -> HitRegion {
        guard tuning.piboVisible else { return .none }
        if !headNode.isHidden {
            // `headNode.frame` is in pibo's coords (its parent) and already
            // accounts for the idle rotation / any in-flight scale.
            let local = convert(p, to: pibo)
            let f = headNode.frame
            let padX = max(12, (44 - f.width) / 2)
            let padY = max(12, (44 - f.height) / 2)
            if f.insetBy(dx: -padX, dy: -padY).contains(local) { return .hair }
        }
        // Generous circle around the body (the prior whole-Pibo hit area).
        let dx = p.x - pibo.position.x
        let dy = p.y - (pibo.position.y + bodyHeight * 0.3)
        if dx * dx + dy * dy < pow(bodyWidth * 0.8, 2) { return .body }
        return .none
    }

    // — 拖毛 drag state —
    private var hairTouch: UITouch?
    private var hairDragOrigin: CGPoint = .zero
    /// Past this pull distance a release counts as a real 拔 (vs a poke).
    private static let hairPullThreshold: CGFloat = 30

    // — tap candidate (non-毛) — a began→ended on roughly the same point is a tap
    // that routes to 拍一拍; a small movement tolerance absorbs jitter.
    private var tapTouch: UITouch?
    private var tapOrigin: CGPoint = .zero
    /// Beyond this move a touch is a drag/scroll, not a tap.
    private static let tapSlop: CGFloat = 16

    /// Asymptotic rubber-band: approaches ±`limit` as |v| grows, so the 毛
    /// resists harder the further it's dragged and can never over-rotate.
    private static func rubberBand(_ v: CGFloat, limit: CGFloat) -> CGFloat {
        limit * v / (abs(v) + limit)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard built, !closeupActive, hairTouch == nil, tapTouch == nil,
              let t = touches.first else { return }
        onDirectManipulationChanged?(true)
        let p = t.location(in: self)
        // A touch that lands on the 毛 owns the gesture as a 拖毛 drag; everything
        // else is a tap candidate (拍一拍).
        if hitRegion(at: p) == .hair {
            hairTouch = t
            hairDragOrigin = p
            headNode.removeAction(forKey: "headIdle")
            headNode.removeAction(forKey: "hairSettle")
            return
        }
        tapTouch = t
        tapOrigin = p
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = hairTouch, touches.contains(t) {
            let p = t.location(in: self)
            // Bend toward the finger with rubber-band resistance; pulling upward
            // also stretches the 毛 a little, like it's really being tugged.
            let dx = p.x - hairDragOrigin.x
            let up = max(0, p.y - hairDragOrigin.y)
            headNode.zRotation = -0.55 * Self.rubberBand(dx, limit: 110) / 110
            headNode.yScale = 1 + 0.28 * Self.rubberBand(up, limit: 130) / 130
            return
        }
        // A tap candidate that wanders too far is no longer a tap.
        if let t = tapTouch, touches.contains(t) {
            let p = t.location(in: self)
            if hypot(p.x - tapOrigin.x, p.y - tapOrigin.y) > Self.tapSlop {
                tapTouch = nil
                onDirectManipulationChanged?(false)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = hairTouch, touches.contains(t) {
            let p = t.location(in: self)
            let pull = hypot(p.x - hairDragOrigin.x, p.y - hairDragOrigin.y)
            finishHairDrag(pulled: pull > Self.hairPullThreshold)
            return
        }
        guard let t = tapTouch, touches.contains(t) else { return }
        tapTouch = nil
        onDirectManipulationChanged?(false)
        handleTap(at: t.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // System interruption (call banner, app switcher).
        if let t = hairTouch, touches.contains(t) {
            finishHairDrag(pulled: false)
            return
        }
        if let t = tapTouch, touches.contains(t) {
            tapTouch = nil
            onDirectManipulationChanged?(false)
        }
    }

    // MARK: Tap routing

    /// Only Pibo itself handles stage touches. Feature entries live in SwiftUI.
    private func handleTap(at p: CGPoint) {
        if hitRegion(at: p) == .body { bouncePibo(); onPat?() }
    }

    /// Snap the 毛 back — a springy overshoot when it was really pulled, a tiny
    /// acknowledging wiggle for a mere poke — then resume the idle sway.
    private func finishHairDrag(pulled: Bool) {
        hairTouch = nil
        onDirectManipulationChanged?(false)
        onHighRefreshRequested?(0.7)
        let releaseAngle = headNode.zRotation
        let settle: SKAction
        if pulled {
            emitSparkles(at: CGPoint(x: pibo.position.x + headNode.position.x,
                                     y: pibo.position.y + headNode.position.y), count: 10)
            settle = .sequence([
                .group([.scaleY(to: 1, duration: 0.10),
                        .rotate(toAngle: -releaseAngle * 0.5, duration: 0.10)]),
                .rotate(toAngle: releaseAngle * 0.22, duration: 0.10),
                .rotate(toAngle: 0, duration: 0.10),
            ])
        } else {
            settle = .sequence([
                .group([.scaleY(to: 1, duration: 0.12), .rotate(toAngle: 0, duration: 0.12)]),
                .rotate(byAngle: 0.08, duration: 0.08),
                .rotate(byAngle: -0.08, duration: 0.10),
            ])
        }
        let resumeIdle = SKAction.run { [weak self] in self?.startHeadIdle() }
        headNode.run(.sequence([settle, resumeIdle]), withKey: "hairSettle")
        if pulled { onHairPulled?() }
    }

    // MARK: - Build

    private func buildIfNeeded() {
        guard !built, size.width > 1, size.height > 1 else { return }
        built = true
        addChild(backdrop)
        addChild(forestFoliageLayer)
        pibo.zPosition = theme.id == PiboTheme.forest.id ? 20 : 0
        addChild(pibo)
        overheadNode.zPosition = theme.id == PiboTheme.forest.id ? 33 : 13
        addChild(overheadNode)
        firefliesNode.zPosition = 40
        addChild(firefliesNode)
        addChild(fx)
        fx.zPosition = 55
        rainBack.zPosition = theme.id == PiboTheme.forest.id ? 24 : 5
        addChild(rainBack)
        rainFront.zPosition = 60
        addChild(rainFront)
        cam.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cam)
        camera = cam
        atmosphereNode.zPosition = 90
        cam.addChild(atmosphereNode)
        multiplyOverlay.blendMode = .multiply
        screenOverlay.blendMode = .screen
        atmosphereNode.addChild(multiplyOverlay)
        atmosphereNode.addChild(screenOverlay)

        rebuildBackdrop()
        buildPibo()
        rebuildHead()
        layoutAll()
        applyAtmosphere(animated: false)
        if environment.rainIntensity > 0 { applyWeather() }
        applyState(animated: false)
        applyTuning(visibilityChanged: true)
        startIdleBob()
        startHeadIdle()
    }

    /// When the active theme carries body art, the stage shows a sprite instead
    /// of the procedural egg/face geometry.
    private var usesArt: Bool { theme.bodyImage != nil }
    /// The live body node for squash/bounce FX, whichever path is active.
    private var bodyForFX: SKNode? { bodySprite ?? bodyNode }

    // Art bodies size to the Figma frame proportions (image 239.262×235 on a
    // 393-wide frame, node 74:5954); procedural bodies keep the prior sizing.
    private var bodyWidth: CGFloat {
        if theme.id == PiboTheme.forest.id {
            return 181.1602 * ForestLayoutMapper(sceneSize: size).scale
        }
        return usesArt ? size.width * (239.262 / 393.0) : min(size.width * 0.34, 150)
    }
    private var bodyHeight: CGFloat {
        if theme.id == PiboTheme.forest.id {
            return 199.592 / 181.1602 * bodyWidth
        }
        return usesArt ? bodyWidth * (235.0 / 239.262) : bodyWidth * 1.12
    }
    private var groundTopY: CGFloat {
        if theme.id == PiboTheme.forest.id {
            return ForestLayoutMapper(sceneSize: size).point(CGPoint(x: 0, y: 610)).y
        }
        return size.height * 0.34
    }

    /// Tear down and rebuild the body group for the current theme — used when the
    /// theme changes (art ⇄ procedural body) at runtime.
    private func rebuildPibo() {
        pibo.removeAllChildren()
        bodyNode = nil
        bodySprite = nil
        buildPibo()
        rebuildHead()
        startIdleBob()
        startHeadIdle()
    }

    private func buildPibo() {
        // Art path: a single Pibo sprite (body + face baked in) plus the head
        // item on its own layer. Procedural face/feet/shadow are skipped.
        if usesArt, let name = theme.bodyImage {
            let body = SKSpriteNode(texture: SKTexture(imageNamed: name))
            body.zPosition = 10
            bodySprite = body
            pibo.addChild(body)
            headNode.zPosition = 12
            pibo.addChild(headNode)
            return
        }

        let w = bodyWidth, h = bodyHeight
        // Soft egg/blob body.
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let path = CGPath(roundedRect: rect, cornerWidth: w * 0.5, cornerHeight: h * 0.46, transform: nil)
        let body = SKShapeNode(path: path)
        body.fillColor = SKColor.white
        body.strokeColor = SKColor(white: 0.82, alpha: 1)
        body.lineWidth = 2
        body.zPosition = 10
        bodyNode = body

        // Contact shadow.
        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 1.05, height: h * 0.16))
        shadow.fillColor = SKColor(white: 0, alpha: 0.10)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -h * 0.5)
        shadow.zPosition = 9

        // Feet.
        let footSize = CGSize(width: w * 0.26, height: w * 0.16)
        for sign in [-1.0, 1.0] {
            let foot = SKShapeNode(ellipseOf: footSize)
            foot.fillColor = SKColor.white
            foot.strokeColor = SKColor(white: 0.82, alpha: 1)
            foot.lineWidth = 1.5
            foot.position = CGPoint(x: CGFloat(sign) * w * 0.20, y: -h * 0.46)
            foot.zPosition = 9.5
            pibo.addChild(foot)
        }

        pibo.addChild(shadow)
        pibo.addChild(body)
        buildFace()
        pibo.addChild(blush)
        pibo.addChild(leftEye)
        pibo.addChild(rightEye)
        headNode.zPosition = 12
        pibo.addChild(headNode)
    }

    private func buildFace() {
        let w = bodyWidth, h = bodyHeight
        let eyeOffsetX = w * 0.17
        let eyeY = h * 0.04
        for (node, sign) in [(leftEye, -1.0), (rightEye, 1.0)] {
            node.removeAllChildren()
            node.position = CGPoint(x: CGFloat(sign) * eyeOffsetX, y: eyeY)
            node.zPosition = 11
        }
        // Blush (hidden unless irritated/active).
        blush.removeAllChildren()
        for sign in [-1.0, 1.0] {
            let b = SKShapeNode(ellipseOf: CGSize(width: w * 0.16, height: w * 0.10))
            b.fillColor = SKColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 0.55)
            b.strokeColor = .clear
            b.position = CGPoint(x: CGFloat(sign) * w * 0.30, y: -h * 0.02)
            blush.addChild(b)
        }
        blush.alpha = 0
        blush.zPosition = 10.5
    }

    /// Eyes per state: open dot / closed arc / half-lidded.
    private func setEyes(_ kind: EyeKind) {
        let w = bodyWidth
        for node in [leftEye, rightEye] {
            node.removeAllChildren()
            switch kind {
            case .open:
                let e = SKShapeNode(ellipseOf: CGSize(width: w * 0.085, height: w * 0.11))
                e.fillColor = SKColor(white: 0.12, alpha: 1); e.strokeColor = .clear
                node.addChild(e)
            case .closed:
                let line = SKShapeNode()
                let p = CGMutablePath()
                p.move(to: CGPoint(x: -w * 0.06, y: 0))
                p.addQuadCurve(to: CGPoint(x: w * 0.06, y: 0), control: CGPoint(x: 0, y: -w * 0.04))
                line.path = p
                line.strokeColor = SKColor(white: 0.12, alpha: 1); line.lineWidth = 2.2; line.lineCap = .round
                node.addChild(line)
            case .half:
                let e = SKShapeNode(ellipseOf: CGSize(width: w * 0.085, height: w * 0.06))
                e.fillColor = SKColor(white: 0.12, alpha: 1); e.strokeColor = .clear
                node.addChild(e)
            }
        }
    }

    private enum EyeKind { case open, closed, half }

    // MARK: Backdrop (sky + ground)

    /// The stage is a single home scene = the current theme backdrop.
    private func rebuildBackdrop() {
        backdrop.removeAllChildren()
        forestFoliageLayer.removeAllChildren()
        forestFoliage.removeAll(keepingCapacity: true)
        forestWaterNode = nil
        morningLightNode = nil
        if theme.id == PiboTheme.forest.id {
            buildForestBackdrop()
        } else {
            buildHomeBackdrop(into: backdrop)
        }
    }

    private func buildForestBackdrop() {
        backgroundColor = SKColor(red: 0.827, green: 0.933, blue: 0.890, alpha: 1)
        let mapper = ForestLayoutMapper(sceneSize: size)

        let base = SKSpriteNode(color: backgroundColor, size: size)
        base.position = CGPoint(x: size.width / 2, y: size.height / 2)
        base.zPosition = -1
        backdrop.addChild(base)

        for definition in ForestSceneManifest.backgroundLayers {
            backdrop.addChild(forestSprite(for: definition, mapper: mapper))
        }

        let waterDefinition = ForestSceneManifest.river
        let water = forestSprite(for: waterDefinition, mapper: mapper)
        water.shader = makeWaterShader()
        backdrop.addChild(water)
        forestWaterNode = water

        for definition in ForestSceneManifest.foliage {
            let texture = SKTexture(imageNamed: definition.image)
            texture.filteringMode = .linear
            let leaf = ForestFoliageNode(texture: texture, definition: definition)
            leaf.size = mapper.size(definition.frame.size)
            let anchorInDesign = CGPoint(
                x: definition.frame.minX + definition.frame.width * definition.anchor.x,
                y: definition.frame.minY + definition.frame.height * definition.anchor.y
            )
            leaf.position = mapper.point(anchorInDesign)
            forestFoliageLayer.addChild(leaf)
            forestFoliage.append(leaf)
        }

        let light = forestSprite(for: ForestSceneManifest.morningLight, mapper: mapper)
        light.blendMode = .screen
        backdrop.addChild(light)
        morningLightNode = light
        updateWaterLighting()
    }

    private func forestSprite(
        for definition: ForestSceneManifest.Layer,
        mapper: ForestLayoutMapper
    ) -> SKSpriteNode {
        let texture = SKTexture(imageNamed: definition.image)
        texture.filteringMode = .linear
        let sprite = SKSpriteNode(texture: texture)
        sprite.position = mapper.point(CGPoint(x: definition.frame.midX, y: definition.frame.midY))
        sprite.size = mapper.size(definition.frame.size)
        sprite.zPosition = definition.zPosition
        return sprite
    }

    private func makeWaterShader() -> SKShader {
        let shader = SKShader(fileNamed: "ForestStream.fsh")
        shader.addUniform(SKUniform(name: "u_flow_time", float: flowTime))
        shader.addUniform(SKUniform(name: "u_flow_speed", float: waterFlowSpeed))
        shader.addUniform(SKUniform(name: "u_ripple_strength", float: effectiveWaterRippleStrength))
        shader.addUniform(SKUniform(name: "u_highlight_strength", float: 0.82))
        shader.addUniform(SKUniform(name: "u_darkness", float: 0))
        shader.addUniform(SKUniform(name: "u_warmth", float: 0))
        shader.addUniform(SKUniform(name: "u_low_power", float: lowPowerModeEnabled ? 1 : 0))
        #if DEBUG
        shader.addUniform(SKUniform(name: "u_mask_preview", float: waterDebugTuning?.showMask == true ? 1 : 0))
        #else
        shader.addUniform(SKUniform(name: "u_mask_preview", float: 0))
        #endif
        return shader
    }

    private var waterFlowSpeed: Float {
        #if DEBUG
        if let waterDebugTuning { return waterDebugTuning.speed }
        #endif
        return Float(tuning.waterFlowSpeed)
    }

    private var effectiveWaterRippleStrength: Float {
        #if DEBUG
        let base = waterDebugTuning?.rippleStrength ?? 0.78
        #else
        let base: Float = 0.78
        #endif
        return base * (lowPowerModeEnabled ? 0.68 : 1)
    }

    private func applyWaterPerformanceUniforms() {
        guard let shader = forestWaterNode?.shader else { return }
        shader.uniformNamed("u_flow_speed")?.floatValue = waterFlowSpeed
        shader.uniformNamed("u_ripple_strength")?.floatValue = effectiveWaterRippleStrength
        shader.uniformNamed("u_low_power")?.floatValue = lowPowerModeEnabled ? 1 : 0
    }

    private func applyTuning(visibilityChanged: Bool) {
        pibo.isHidden = !tuning.piboVisible
        applyWaterPerformanceUniforms()
        guard visibilityChanged else { return }

        if tuning.piboVisible {
            overheadNode.isHidden = theme.resolvedHead(for: growth).overhead == nil
            showZzz(activityState == .deepSleep)
        } else {
            overheadNode.isHidden = true
            showZzz(false)
        }
    }

    private func updateWaterLighting() {
        let values: (darkness: Float, warmth: Float, highlight: Float)
        switch environment.dayPhase {
        case .morning: values = (0.02, 0.32, 0.92)
        case .day: values = (0, 0, 0.82)
        case .dusk: values = (0.18, 0.42, 0.68)
        case .night: values = (0.72, 0, 0.38)
        }
        forestWaterNode?.shader?.uniformNamed("u_darkness")?.floatValue = values.darkness
        forestWaterNode?.shader?.uniformNamed("u_warmth")?.floatValue = values.warmth
        #if DEBUG
        let highlight = waterDebugTuning?.highlightStrength ?? values.highlight
        #else
        let highlight = values.highlight
        #endif
        forestWaterNode?.shader?.uniformNamed("u_highlight_strength")?.floatValue = highlight
    }

    private func applyAtmosphere(animated: Bool) {
        atmosphereNode.position = .zero
        multiplyOverlay.size = size
        screenOverlay.size = size

        let multiply: (SKColor, CGFloat)
        let screen: (SKColor, CGFloat)
        let morningAlpha: CGFloat
        switch environment.dayPhase {
        case .morning:
            multiply = (SKColor(red: 0.91, green: 0.95, blue: 0.88, alpha: 1), 0.10)
            screen = (SKColor(red: 1, green: 0.84, blue: 0.60, alpha: 1), 0.12)
            morningAlpha = 0.92
        case .day:
            multiply = (.white, 0)
            screen = (.white, 0.02)
            morningAlpha = 0.10
        case .dusk:
            multiply = (SKColor(red: 0.21, green: 0.36, blue: 0.35, alpha: 1), 0.18)
            screen = (SKColor(red: 1, green: 0.69, blue: 0.42, alpha: 1), 0.16)
            morningAlpha = 0.04
        case .night:
            multiply = (SKColor(red: 0.08, green: 0.18, blue: 0.23, alpha: 1), 0.48)
            screen = (SKColor(red: 0.55, green: 0.79, blue: 0.84, alpha: 1), 0.08)
            morningAlpha = 0
        }

        let duration = animated ? 1.2 : 0
        multiplyOverlay.removeAction(forKey: "atmosphere")
        screenOverlay.removeAction(forKey: "atmosphere")
        morningLightNode?.removeAction(forKey: "atmosphere")
        multiplyOverlay.run(.group([
            .colorize(with: multiply.0, colorBlendFactor: 1, duration: duration),
            .fadeAlpha(to: multiply.1, duration: duration),
        ]), withKey: "atmosphere")
        screenOverlay.run(.group([
            .colorize(with: screen.0, colorBlendFactor: 1, duration: duration),
            .fadeAlpha(to: screen.1, duration: duration),
        ]), withKey: "atmosphere")
        morningLightNode?.run(.fadeAlpha(to: morningAlpha, duration: duration), withKey: "atmosphere")
        updateFireflies(animated: animated)
    }

    private func updateFireflies(animated: Bool) {
        guard theme.id == PiboTheme.forest.id else {
            fireflyEmitter?.particleBirthRate = 0
            return
        }
        let emitter = fireflyEmitter ?? makeFireflyEmitter()
        emitter.position = CGPoint(x: size.width / 2, y: size.height * 0.36)
        emitter.particlePositionRange = CGVector(dx: size.width * 0.92, dy: size.height * 0.32)

        let targetRate: CGFloat
        switch environment.dayPhase {
        case .morning, .day:
            targetRate = 0
        case .dusk:
            targetRate = lowPowerModeEnabled ? 0 : 1.2
        case .night:
            targetRate = lowPowerModeEnabled ? 2.0 : 6.0
        }
        if animated {
            let start = emitter.particleBirthRate
            emitter.run(.customAction(withDuration: 1.2) { node, elapsed in
                guard let emitter = node as? SKEmitterNode else { return }
                let progress = min(max(elapsed / 1.2, 0), 1)
                emitter.particleBirthRate = start + (targetRate - start) * progress
            }, withKey: "phase")
        } else {
            emitter.removeAction(forKey: "phase")
            emitter.particleBirthRate = targetRate
        }
    }

    private func makeFireflyEmitter() -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = Self.fireflyTexture
        emitter.particleBirthRate = 0
        emitter.particleLifetime = 4.8
        emitter.particleLifetimeRange = 2.2
        emitter.emissionAngleRange = .pi * 2
        emitter.particleSpeed = 7
        emitter.particleSpeedRange = 5
        emitter.particleAlpha = 0
        emitter.particleAlphaRange = 0.12
        emitter.particleAction = .repeatForever(.sequence([
            .fadeAlpha(to: 0.95, duration: 0.8),
            .fadeAlpha(to: 0.16, duration: 1.1),
        ]))
        emitter.particleScale = 0.42
        emitter.particleScaleRange = 0.22
        emitter.particleColor = SKColor(red: 0.94, green: 1, blue: 0.52, alpha: 1)
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        firefliesNode.addChild(emitter)
        fireflyEmitter = emitter
        return emitter
    }

    /// home 区域背景 = 当前主题（图片主题一张全幅图，程序化主题天空渐变 + 地面带）。
    private func buildHomeBackdrop(into parent: SKNode) {
        let scene = theme.scene
        if let bg = scene.backgroundImage {
            let sprite = SKSpriteNode(texture: SKTexture(imageNamed: bg))
            sprite.zPosition = 0
            sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
            sprite.size = size
            parent.addChild(sprite)
            return
        }
        let sky = SKSpriteNode(texture: Self.gradientTexture(
            top: SKColor(scene.skyTop), bottom: SKColor(scene.skyBottom)))
        sky.anchorPoint = .zero
        sky.position = .zero
        sky.size = size
        sky.zPosition = 0
        parent.addChild(sky)

        let ground = SKShapeNode(path: groundPath(scene.terrain))
        ground.fillColor = SKColor(scene.ground)
        ground.strokeColor = .clear
        ground.zPosition = 1
        parent.addChild(ground)

        addGroundDetail(scene, into: parent)
    }

    private func groundPath(_ terrain: PiboScene.Terrain) -> CGPath {
        let w = size.width, top = groundTopY
        let p = CGMutablePath()
        switch terrain {
        case .meadow:
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: top - 14))
            p.addQuadCurve(to: CGPoint(x: w, y: top - 20), control: CGPoint(x: w * 0.5, y: top + 16))
            p.addLine(to: CGPoint(x: w, y: 0))
            p.closeSubpath()
        case .beach:
            // Sand fills the band; sea drawn separately in detail.
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: top - 18))
            p.addQuadCurve(to: CGPoint(x: w, y: top - 18), control: CGPoint(x: w * 0.5, y: top - 34))
            p.addLine(to: CGPoint(x: w, y: 0))
            p.closeSubpath()
        case .platform:
            // A floating slab around the band top.
            let y = top
            p.move(to: CGPoint(x: w * 0.14, y: y - size.height * 0.02))
            p.addLine(to: CGPoint(x: w * 0.86, y: y + size.height * 0.02))
            p.addLine(to: CGPoint(x: w * 0.93, y: y - size.height * 0.025))
            p.addLine(to: CGPoint(x: w * 0.21, y: y - size.height * 0.065))
            p.closeSubpath()
        }
        return p
    }

    private func addGroundDetail(_ scene: PiboScene, into parent: SKNode) {
        let w = size.width, top = groundTopY
        switch scene.terrain {
        case .meadow:
            for p in Self.petals {
                let r = 3 + p.s * 4
                let petal = SKShapeNode(ellipseOf: CGSize(width: r * 2, height: r * 1.4))
                petal.fillColor = SKColor(scene.groundAccent).withAlphaComponent(0.85)
                petal.strokeColor = .clear
                petal.position = CGPoint(x: p.x * w, y: (top - 10) * (1 - p.y))
                petal.zPosition = 2
                parent.addChild(petal)
            }
        case .beach:
            let sea = SKShapeNode(rect: CGRect(x: 0, y: top - 18, width: w, height: size.height * 0.14))
            sea.fillColor = SKColor(scene.groundAccent)
            sea.strokeColor = .clear
            sea.zPosition = 0.5
            parent.addChild(sea)
        case .platform:
            let edge = SKShapeNode(rect: CGRect(x: w * 0.21, y: top - size.height * 0.095,
                                                width: w * 0.72, height: size.height * 0.04))
            edge.fillColor = SKColor(scene.groundAccent)
            edge.strokeColor = .clear
            edge.zPosition = 0.9
            parent.addChild(edge)
        }
    }

    // MARK: Head item (theme art, or rendered from the SwiftUI design-system view)

    private func rebuildHead() {
        let (head, overhead) = theme.resolvedHead(for: growth)

        // Overhead 黑洞 — scene-level so the curl slides through it as Pibo bobs.
        if let overhead {
            overheadNode.texture = SKTexture(imageNamed: overhead.image)
            overheadNode.isHidden = !tuning.piboVisible
            overheadNode.alpha = 1
        } else {
            overheadNode.isHidden = true
        }

        // Art path: a real head-item texture (桃花枝 / 海草 / 卷芽); sized/placed
        // in layout from its design-frame anchor.
        if let head {
            headNode.texture = SKTexture(imageNamed: head.image)
            headNode.isHidden = false
            positionHead()
            return
        }
        if usesArt {
            // Art body without head art (shouldn't happen for shipped themes).
            headNode.isHidden = true
            positionHead()
            return
        }

        headNode.isHidden = false
        let side = bodyWidth * 0.9
        let renderer = ImageRenderer(content:
            PiboHeadItemView(item: theme.headItem, size: side)
                .frame(width: side * (theme.headItem == .mystery ? 1.7 : 1.0), height: side)
        )
        renderer.scale = UIScreen.main.scale
        if let img = renderer.uiImage {
            headNode.texture = SKTexture(image: img)
            headNode.size = img.size.applying(.init(scaleX: 1 / renderer.scale, y: 1 / renderer.scale))
        }
        positionHead()
    }

    // MARK: Layout

    private func layoutAll() {
        guard built else { return }
        if theme.id == PiboTheme.forest.id {
            let mapper = ForestLayoutMapper(sceneSize: size)
            let foot = mapper.point(ForestSceneManifest.piboFootPoint)
            pibo.position = CGPoint(x: foot.x, y: foot.y + bodyHeight * 0.5)
        } else if usesArt {
            // Place the body sprite at the theme's design-frame body center; size
            // it to the mapped box.
            bodySprite?.size = CGSize(width: bodyWidth, height: bodyHeight)
            pibo.position = CGPoint(x: size.width * (theme.bodyCenterX / 393.0),
                                    y: size.height * (1 - theme.bodyCenterY / 852.0))
        } else {
            pibo.position = CGPoint(x: size.width / 2, y: groundTopY + bodyHeight * 0.18)
        }
        positionHead()
        if !closeupActive {
            cam.position = CGPoint(x: size.width / 2, y: size.height / 2)
            cam.setScale(1)
        }
    }

    private func positionHead() {
        let (head, overhead) = theme.resolvedHead(for: growth)

        if let overhead {
            let nat = overheadNode.texture?.size() ?? CGSize(width: 234, height: 64)
            let s = size.height / 852.0
            overheadNode.size = CGSize(width: nat.width * s, height: nat.height * s)
            overheadNode.position = CGPoint(x: size.width * (overhead.centerX / 393.0),
                                            y: size.height * (1 - overhead.centerY / 852.0))
        }

        if let head {
            if theme.id == PiboTheme.forest.id {
                let mapper = ForestLayoutMapper(sceneSize: size)
                let nat = headNode.texture?.size() ?? CGSize(width: 30.716, height: 66.573)
                headNode.size = mapper.size(nat)
                headNode.position = CGPoint(
                    x: (head.centerX - theme.bodyCenterX) * mapper.scale,
                    y: (theme.bodyCenterY - head.centerY) * mapper.scale
                )
                return
            }
            // Size from the head texture's natural points (@3x asset → design pts)
            // so each theme's 毛/花 keeps its own aspect — 桃花枝 38×89.5 stays put,
            // while 阿那亚 海草 (taller/narrower) isn't squished into the branch box.
            // Scaled uniformly by the 852-pt frame height to stay resolution-free.
            let nat = headNode.texture?.size() ?? CGSize(width: 38, height: 89.5)
            let s = size.height / 852.0
            headNode.size = CGSize(width: nat.width * s, height: nat.height * s)
            // Offset from the body center to the sprite's design-frame anchor —
            // center-anchored, so a taller head grows symmetrically about it.
            headNode.position = CGPoint(
                x: size.width * ((head.centerX - theme.bodyCenterX) / 393.0),
                y: size.height * ((theme.bodyCenterY - head.centerY) / 852.0))
            return
        }
        headNode.position = CGPoint(x: 0, y: bodyHeight * 0.5 + headNode.size.height * 0.32)
    }

    // MARK: State

    private func applyState(animated: Bool) {
        if usesArt {
            if theme.id == PiboTheme.forest.id {
                applyForestState(animated: animated)
                return
            }
            showZzz(activityState == .deepSleep)
            if activityState == .disturbed { playTurnAway() }
            return
        }
        switch activityState {
        case .deepSleep:
            setEyes(.closed); setBlush(0); showZzz(true); setBodyTint(0.97)
        case .waking:
            setEyes(.half); setBlush(0); showZzz(false); setBodyTint(1.0)
        case .active:
            setEyes(.open); setBlush(0.7); showZzz(false); setBodyTint(1.0)
        case .irritated:
            setEyes(.half); setBlush(0.5); showZzz(false); setBodyTint(0.96)
        case .disturbed:
            setEyes(.half); setBlush(0.3); showZzz(false); setBodyTint(1.0)
            playTurnAway()
        case .idle:
            setEyes(.open); setBlush(0); showZzz(false); setBodyTint(1.0)
        }
    }

    private func applyForestState(animated: Bool) {
        guard let body = bodySprite else { return }
        body.removeAction(forKey: "forestState")
        headNode.removeAction(forKey: "forestState")
        headNode.removeAction(forKey: "headIdle")
        showZzz(activityState == .deepSleep)
        let duration = animated ? 0.32 : 0

        switch activityState {
        case .deepSleep:
            body.run(.group([
                .scaleX(to: 1.03, y: 0.96, duration: duration),
                .rotate(toAngle: -0.025, duration: duration),
            ]), withKey: "forestState")
            runForestHeadReaction(.rotate(toAngle: -0.12, duration: duration))
        case .waking:
            body.run(.group([
                .scaleX(to: 1, y: 1, duration: duration),
                .rotate(toAngle: 0.025, duration: duration),
            ]), withKey: "forestState")
            runForestHeadReaction(.rotate(toAngle: -0.04, duration: duration))
        case .active:
            let pulse = SKAction.sequence([
                .scaleX(to: 0.96, y: 1.06, duration: 0.12),
                .scaleX(to: 1.02, y: 0.98, duration: 0.12),
                .scaleX(to: 1, y: 1, duration: 0.16),
            ])
            body.run(pulse, withKey: "forestState")
            runForestHeadReaction(.sequence([
                .rotate(toAngle: 0.10, duration: 0.12),
                .rotate(toAngle: -0.08, duration: 0.14),
                .rotate(toAngle: 0, duration: 0.18),
            ]))
        case .irritated:
            body.run(.group([
                .scaleX(to: 1.01, y: 0.98, duration: duration),
                .rotate(toAngle: 0.045, duration: duration),
            ]), withKey: "forestState")
            runForestHeadReaction(.rotate(toAngle: 0.13, duration: duration))
        case .disturbed:
            body.setScale(1)
            playTurnAway()
            startHeadIdle()
        case .idle:
            body.run(.group([
                .scaleX(to: 1, y: 1, duration: duration),
                .rotate(toAngle: 0, duration: duration),
            ]), withKey: "forestState")
            runForestHeadReaction(.rotate(toAngle: 0, duration: duration))
        }
    }

    private func runForestHeadReaction(_ action: SKAction) {
        headNode.run(.sequence([
            action,
            .run { [weak self] in self?.startHeadIdle() },
        ]), withKey: "forestState")
    }

    private func setBlush(_ a: CGFloat) {
        blush.run(.fadeAlpha(to: a, duration: 0.3))
    }

    private func setBodyTint(_ brightness: CGFloat) {
        // Subtle dim for low-energy states via a fill color shift.
        bodyNode?.run(.colorize(with: SKColor(white: brightness, alpha: 1), colorBlendFactor: 0, duration: 0.2))
        bodyNode?.fillColor = SKColor(white: brightness, alpha: 1)
    }

    private func showZzz(_ show: Bool) {
        fx.childNode(withName: "zzz")?.removeFromParent()
        guard show, tuning.piboVisible else { return }
        let z = SKLabelNode(text: "Zzz")
        z.name = "zzz"
        z.fontName = "AvenirNext-Bold"
        z.fontSize = bodyWidth * 0.2
        z.fontColor = SKColor(white: 0.6, alpha: 0.9)
        z.position = CGPoint(x: pibo.position.x + bodyWidth * 0.5, y: pibo.position.y + bodyHeight * 0.45)
        z.zPosition = 45
        fx.addChild(z)
        z.run(.repeatForever(.sequence([
            .group([.moveBy(x: 8, y: 24, duration: 1.6), .fadeOut(withDuration: 1.6)]),
            .run { [weak self, weak z] in
                guard let self, let z else { return }
                z.position = CGPoint(x: self.pibo.position.x + self.bodyWidth * 0.5, y: self.pibo.position.y + self.bodyHeight * 0.45)
            },
            .fadeIn(withDuration: 0.01),
        ])))
    }

    // MARK: Idle motion

    private func startIdleBob() {
        pibo.removeAction(forKey: "bob")
        let up = SKAction.moveBy(x: 0, y: 8, duration: 1.1); up.timingMode = .easeInEaseOut
        let down = SKAction.moveBy(x: 0, y: -8, duration: 1.1); down.timingMode = .easeInEaseOut
        pibo.run(.repeatForever(.sequence([up, down])), withKey: "bob")
    }

    private func startHeadIdle() {
        headNode.removeAction(forKey: "headIdle")
        let center: CGFloat
        if theme.id == PiboTheme.forest.id {
            switch activityState {
            case .deepSleep: center = -0.12
            case .waking: center = -0.04
            case .irritated: center = 0.13
            case .active, .disturbed, .idle: center = 0
            }
        } else {
            center = 0
        }
        let amplitude: CGFloat = theme.id == PiboTheme.forest.id ? 0.035 : 0.06
        let l = SKAction.rotate(toAngle: center + amplitude, duration: 1.4); l.timingMode = .easeInEaseOut
        let r = SKAction.rotate(toAngle: center - amplitude, duration: 1.4); r.timingMode = .easeInEaseOut
        headNode.run(.repeatForever(.sequence([l, r])), withKey: "headIdle")
    }

    private func bouncePibo() {
        onHighRefreshRequested?(0.5)
        bodyForFX?.removeAction(forKey: "squash")
        let squash = SKAction.sequence([
            .scaleX(to: 1.12, y: 0.9, duration: 0.08),
            .scaleX(to: 0.94, y: 1.08, duration: 0.10),
            .scaleX(to: 1.0, y: 1.0, duration: 0.12),
        ])
        bodyForFX?.run(squash, withKey: "squash")
    }

    private func emitSparkles(at point: CGPoint, count: Int) {
        for _ in 0..<count {
            let s = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.5...3.5))
            s.fillColor = SKColor(theme.scene.groundAccent)
            s.strokeColor = .clear
            s.position = point
            s.zPosition = 46
            fx.addChild(s)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let dist = CGFloat.random(in: 20...60)
            let move = SKAction.moveBy(x: cos(angle) * dist, y: sin(angle) * dist + 20, duration: 0.7)
            move.timingMode = .easeOut
            s.run(.sequence([.group([move, .fadeOut(withDuration: 0.7)]), .removeFromParent()]))
        }
    }

    // MARK: - Weather (下雨三件套)
    //
    // 三层,分工明确:
    //   1. 雨幕 — 一个 `SKEmitterNode` 挂在 `rainBack`(z=5,Pibo 之后),GPU 批处理,
    //      撑起整片下落的雨 + 景深 + 风斜。粒子不与节点碰撞,纯氛围。
    //   2. 地面水花 — `rainFront`(z=41,Pibo 之前)上一个重复 spawner,沿名义地面线
    //      `groundLineY` 随机点生成"皇冠环 + 回弹水珠 + 溅滴"(脚本碰撞,复用
    //      WaterSurface 的 impact 造型语言)。
    //   3. 滴在 Pibo 上 — 同样在 `rainFront`,每隔一阵在 Pibo 顶部轮廓随机点投下一滴
    //      (实时读 `pibo.position.y`,跟着 idle bob 一起动),落点炸出同款水花。
    //
    // 性能:不上物理引擎(脚本落点已够"滴在地面/Pibo 上"的识别度);全屏功能覆盖
    // Home 时 SwiftUI 会暂停 scene 并移除承载它的 SKView → 雨与水花自动停转。

    /// 名义地面线(场景坐标,y 向上)。程序化主题 = 地面带顶;图片主题地面烘焙在
    /// 背景图里,这里用同一高度近似(后续可按主题加 `groundLineY` 微调)。
    private var groundLineY: CGFloat { groundTopY }

    /// Pibo 顶面轮廓采样点(pibo-local 偏移)。雨滴只落在这些点上 → 顺着蛋形 + 毛的
    /// 真实轮廓滴,而不是一条水平线。滴落时加 `pibo.position` 换算到场景坐标,跟随
    /// idle bob。由 `rebuildPiboSurface()` 在雨开始 / 布局 / 发芽换头时重建并缓存。
    private var piboSurface: [CGPoint] = []

    /// 应用当前天气:清掉旧雨层,雨天则重建三层。
    private func applyWeather() {
        rainBack.removeAllChildren();  rainBack.removeAllActions()
        rainFront.removeAllChildren(); rainFront.removeAllActions()
        splashPool.removeAll(keepingCapacity: true)
        nextSplashPoolIndex = 0
        guard environment.rainIntensity > 0 else { return }
        prepareSplashPool()
        buildRainCurtain()
        startGroundSplashes()
        startPiboDrips()
    }

    /// 雨幕 — 顶部一个全宽发射器,粒子加速下落(雷雨更密更快、风更斜)。
    private func buildRainCurtain() {
        let storm = environment.rainIntensity >= 0.8
        let e = SKEmitterNode()
        e.particleTexture = Self.rainTexture
        e.position = CGPoint(x: size.width / 2, y: size.height + 24)
        e.particlePositionRange = CGVector(dx: size.width * 1.15, dy: 0)
        let powerMultiplier: CGFloat = lowPowerModeEnabled ? 0.45 : 1
        e.particleBirthRate = (90 + 150 * environment.rainIntensity) * powerMultiplier
        e.particleLifetime = size.height / 480 + 0.6
        e.particleLifetimeRange = 0.3
        e.emissionAngle = -.pi / 2          // 垂直向下(SpriteKit:角度自 +x 逆时针)
        e.emissionAngleRange = 0.05
        e.particleSpeed = storm ? 720 : 560
        e.particleSpeedRange = 140
        e.yAcceleration = -420              // 重力加速下落
        e.xAcceleration = environment.wind.direction.dx * (storm ? 140 : 55)
        e.particleAlpha = 0.55
        e.particleAlphaRange = 0.2
        e.particleAlphaSpeed = -0.12
        e.particleScale = storm ? 0.55 : 0.42
        e.particleScaleRange = 0.2
        e.particleColor = Self.rainTint
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .alpha
        e.advanceSimulationTime(1.6)        // 出现即在下雨,而非从顶部抹下来
        rainBack.addChild(e)
    }

    /// Surface impacts are sampled independently from the visual rain curtain;
    /// no per-drop physics bodies are created.
    private func startGroundSplashes() {
        let storm = environment.rainIntensity >= 0.8
        let interval = (storm ? 0.05 : 0.11) * (lowPowerModeEnabled ? 2.2 : 1)
        rainFront.run(.repeatForever(.sequence([
            .wait(forDuration: interval, withRange: interval * 0.8),
            .run { [weak self] in self?.spawnGroundSplash() },
        ])), withKey: "groundSplash")
    }

    /// 滴在 Pibo 上 — 沿真实轮廓随机点持续投滴(频率比地面低)。
    private func startPiboDrips() {
        rebuildPiboSurface()
        let storm = environment.rainIntensity >= 0.8
        let interval = (storm ? 0.35 : 0.6) * (lowPowerModeEnabled ? 1.8 : 1)
        rainFront.run(.repeatForever(.sequence([
            .wait(forDuration: interval, withRange: interval * 0.7),
            .run { [weak self] in self?.spawnPiboDrip() },
        ])), withKey: "piboDrip")
    }

    private func spawnGroundSplash() {
        if theme.id == PiboTheme.forest.id {
            let roll = CGFloat.random(in: 0...1)
            if roll < 0.48, let point = randomForestWaterPoint() {
                makeSplash(at: point, scale: CGFloat.random(in: 0.75...1.15), flatten: 0.35)
                return
            }
            if roll < 0.72, let leaf = forestFoliage.randomElement() {
                let frame = leaf.calculateAccumulatedFrame()
                let point = CGPoint(
                    x: CGFloat.random(in: frame.minX...frame.maxX),
                    y: CGFloat.random(in: frame.midY...frame.maxY)
                )
                leaf.receiveRainImpact(
                    strength: environment.rainIntensity,
                    side: point.x < frame.midX ? -1 : 1
                )
                makeSplash(at: point, scale: 0.52, flatten: 0.64)
                return
            }

            let mapper = ForestLayoutMapper(sceneSize: size)
            let point = mapper.point(CGPoint(
                x: CGFloat.random(in: 24...369),
                y: CGFloat.random(in: 570...625)
            ))
            makeSplash(at: point, scale: CGFloat.random(in: 0.65...1.0), flatten: 0.45)
            return
        }

        let x = CGFloat.random(in: size.width * 0.04 ... size.width * 0.96)
        let y = groundLineY + CGFloat.random(in: -6 ... 10)
        makeSplash(at: CGPoint(x: x, y: y), scale: CGFloat.random(in: 0.8 ... 1.3), flatten: 0.42)
    }

    private func randomForestWaterPoint() -> CGPoint? {
        guard let water = forestWaterNode,
              let normalized = Self.forestWaterSamples.randomElement() else { return nil }
        let local = CGPoint(
            x: (normalized.x - 0.5) * water.size.width,
            y: (normalized.y - 0.5) * water.size.height
        )
        return water.convert(local, to: self)
    }

    /// 一滴从上方落到 Pibo **真实轮廓**上的某点 → 触身炸水花。落点来自
    /// `piboSurface`(蛋形 / 毛的顶面采样),加 `pibo.position` 实时跟随 idle bob。
    private func spawnPiboDrip() {
        guard built, tuning.piboVisible, let local = piboSurface.randomElement() else { return }
        let land = CGPoint(x: pibo.position.x + local.x + CGFloat.random(in: -2 ... 2),
                           y: pibo.position.y + local.y + CGFloat.random(in: -2 ... 3))
        // 入射水滴(最后 ~46pt,因为雨幕在 Pibo 之后,需要一颗"落在 Pibo 前面"的滴)。
        let drop = SKSpriteNode(texture: Self.rainTexture)
        drop.size = CGSize(width: 3, height: 11)
        drop.color = Self.rainTint
        drop.colorBlendFactor = 1
        drop.position = CGPoint(x: land.x, y: land.y + 46)
        rainFront.addChild(drop)
        let fall = SKAction.moveTo(y: land.y, duration: 0.14)
        fall.timingMode = .easeIn
        drop.run(.sequence([
            fall,
            .run { [weak self] in self?.makeSplash(at: land, scale: 0.7, flatten: 0.62) },
            .removeFromParent(),
        ]))
    }

    /// 重建 Pibo 顶面轮廓采样点:身体(图片主题采纹理 alpha 轮廓,程序化用椭圆顶)
    /// + 头顶毛(采 alpha)。于是雨滴顺着蛋形 + 毛的真实轮廓滴,不再排成一条水平线。
    private func rebuildPiboSurface() {
        guard built, size.width > 1 else { return }
        var pts: [CGPoint] = []

        // 身体:图片主题采纹理 alpha;失败 / 程序化 → 椭圆顶解析轮廓。
        if usesArt, let name = theme.bodyImage {
            pts += topSurfacePoints(imageNamed: name, center: bodySprite?.position ?? .zero,
                                    size: CGSize(width: bodyWidth, height: bodyHeight), columns: 26)
        }
        if pts.isEmpty {
            let halfW = bodyWidth * 0.5, topY = bodyHeight * 0.5
            for i in 0..<26 {
                let u = CGFloat(i) / 25 * 2 - 1                  // -1...1
                let y = topY * pow(max(0, 1 - u * u), 0.62)      // 椭圆顶(略压扁)
                pts.append(CGPoint(x: u * halfW * 0.9, y: y))
            }
        }

        // 头顶毛:选用主题的 head 都是图片(卷芽 / 桃花枝 / 海草)。
        if !headNode.isHidden, let head = theme.resolvedHead(for: growth).head {
            pts += topSurfacePoints(imageNamed: head.image, center: headNode.position,
                                    size: headNode.size, columns: 10)
        }

        piboSurface = pts
    }

    /// 采样一张图片资源每列"最高不透明像素",换算成 sprite-local 顶面点。重绘到
    /// RGBA8(premultipliedLast)缓冲稳妥读 alpha;缓冲 row 0 = 图像底部(CG y 向上),
    /// row 越大越靠上 → sprite-local y 越大。空白列(该列没有 Pibo)跳过。
    private func topSurfacePoints(imageNamed name: String, center: CGPoint,
                                  size: CGSize, columns: Int) -> [CGPoint] {
        guard size.width > 1, size.height > 1,
              let cg = UIImage(named: name)?.cgImage, cg.width > 1, cg.height > 1 else { return [] }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var pts: [CGPoint] = []
        let threshold: UInt8 = 30
        for c in 0..<columns {
            let col = min(w - 1, Int((CGFloat(c) + 0.5) / CGFloat(columns) * CGFloat(w)))
            var topRow = -1
            var r = h - 1
            while r >= 0 {
                if buf[(r * w + col) * 4 + 3] > threshold { topRow = r; break }
                r -= 1
            }
            guard topRow >= 0 else { continue }
            let fx = (CGFloat(col) + 0.5) / CGFloat(w)
            let fy = (CGFloat(topRow) + 0.5) / CGFloat(h)
            pts.append(CGPoint(x: center.x - size.width * 0.5 + fx * size.width,
                               y: center.y - size.height * 0.5 + fy * size.height))
        }
        return pts
    }

    /// 触水水花 — 皇冠扁环(快速外扩淡出)+ 回弹水珠(Rayleigh jet)+ 两侧溅滴。
    /// 复用 `WaterSurface.impact` 的造型语言。动画预渲染为纹理帧，并从固定
    /// 节点池取 sprite，避免雨天每秒创建、曲面细分几十个 `SKShapeNode`。
    private func makeSplash(at p: CGPoint, scale s: CGFloat, flatten: CGFloat) {
        guard let splash = acquireSplashNode() else { return }
        let isPiboSplash = flatten > 0.5
        splash.texture = isPiboSplash ? Self.piboSplashFrames[0] : Self.groundSplashFrames[0]
        splash.position = p
        splash.setScale(s)
        splash.alpha = 1
        splash.isHidden = false
        splash.run(isPiboSplash ? Self.piboSplashAction : Self.groundSplashAction)
    }

    private func prepareSplashPool() {
        splashPool.reserveCapacity(Self.splashPoolSize)
        for _ in 0..<Self.splashPoolSize {
            let node = SKSpriteNode(texture: Self.groundSplashFrames[0])
            node.size = Self.splashTextureSize
            node.zPosition = 1
            node.isHidden = true
            rainFront.addChild(node)
            splashPool.append(node)
        }
    }

    private func acquireSplashNode() -> SKSpriteNode? {
        guard !splashPool.isEmpty else { return nil }
        for offset in 0..<splashPool.count {
            let index = (nextSplashPoolIndex + offset) % splashPool.count
            let node = splashPool[index]
            if node.isHidden || !node.hasActions() {
                nextSplashPoolIndex = (index + 1) % splashPool.count
                node.removeAllActions()
                return node
            }
        }

        // The pool is deliberately larger than the maximum normal concurrency;
        // if a long frame overlaps every slot, recycle the oldest round-robin
        // node instead of allocating on the hot path.
        let node = splashPool[nextSplashPoolIndex]
        nextSplashPoolIndex = (nextSplashPoolIndex + 1) % splashPool.count
        node.removeAllActions()
        return node
    }

    /// 雨滴贴图 — 一道柔和的竖直水痕(自上而下渐显)。建一次复用。
    private static let rainTint = SKColor(red: 0.62, green: 0.78, blue: 0.92, alpha: 1)
    private static let forestWaterSamples = normalizedAlphaSamples(
        imageNamed: "forest_river",
        maximumSamplesPerAxis: 64
    )
    private static let splashPoolSize = 24
    private static let splashTextureSize = CGSize(width: 48, height: 44)
    private static let groundSplashFrames = splashFrames(flatten: 0.42)
    private static let piboSplashFrames = splashFrames(flatten: 0.62)
    private static let groundSplashAction = SKAction.sequence([
        .animate(with: groundSplashFrames, timePerFrame: 0.34 / Double(groundSplashFrames.count - 1),
                 resize: false, restore: false),
        .hide(),
    ])
    private static let piboSplashAction = SKAction.sequence([
        .animate(with: piboSplashFrames, timePerFrame: 0.34 / Double(piboSplashFrames.count - 1),
                 resize: false, restore: false),
        .hide(),
    ])

    private static func splashFrames(flatten: CGFloat) -> [SKTexture] {
        let frameCount = 21
        let duration: CGFloat = 0.34
        let base = CGPoint(x: splashTextureSize.width / 2, y: splashTextureSize.height * 0.68)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false

        return (0..<frameCount).map { frame in
            let time = CGFloat(frame) / CGFloat(frameCount - 1) * duration
            let image = UIGraphicsImageRenderer(size: splashTextureSize, format: format).image { context in
                let cg = context.cgContext

                let ringProgress = min(1, time / duration)
                let ringScale = 1 + 1.6 * ringProgress
                let ringSize = CGSize(width: 11 * ringScale, height: 11 * flatten * ringScale)
                cg.setStrokeColor(rainTint.withAlphaComponent(0.75 * (1 - ringProgress)).cgColor)
                cg.setLineWidth(1.4)
                cg.strokeEllipse(in: CGRect(
                    x: base.x - ringSize.width / 2,
                    y: base.y - ringSize.height / 2,
                    width: ringSize.width,
                    height: ringSize.height
                ))

                let beadProgress: CGFloat
                let beadY: CGFloat
                if time <= 0.16 {
                    beadProgress = time / 0.16
                    let eased = 1 - pow(1 - beadProgress, 2)
                    beadY = base.y - 11 * eased
                } else {
                    beadProgress = min(1, (time - 0.16) / 0.16)
                    beadY = base.y - 11 * (1 - beadProgress * beadProgress)
                }
                let beadAlpha = max(0, 1 - time / 0.32)
                cg.setFillColor(rainTint.withAlphaComponent(beadAlpha).cgColor)
                cg.fillEllipse(in: CGRect(x: base.x - 1.7, y: beadY - 1.7, width: 3.4, height: 3.4))

                let sideProgress = min(1, time / 0.18)
                let sideAlpha = max(0, 1 - time / 0.22)
                cg.setFillColor(rainTint.withAlphaComponent(sideAlpha).cgColor)
                for sign: CGFloat in [-1, 1] {
                    let center = CGPoint(
                        x: base.x + sign * 12 * sideProgress,
                        y: base.y - 9 * sideProgress
                    )
                    cg.fillEllipse(in: CGRect(x: center.x - 1.3, y: center.y - 1.3,
                                              width: 2.6, height: 2.6))
                }
            }
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            return texture
        }
    }

    private static let rainTexture: SKTexture = {
        let sz = CGSize(width: 4, height: 18)
        let img = UIGraphicsImageRenderer(size: sz).image { ctx in
            let cg = ctx.cgContext
            cg.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: sz),
                              cornerWidth: 2, cornerHeight: 2, transform: nil))
            cg.clip()
            let colors = [SKColor.white.withAlphaComponent(0).cgColor, SKColor.white.cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 1]) else { return }
            cg.drawLinearGradient(g, start: CGPoint(x: 2, y: 0), end: CGPoint(x: 2, y: 18), options: [])
        }
        return SKTexture(image: img)
    }()

    private static let fireflyTexture: SKTexture = {
        let size = CGSize(width: 18, height: 18)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [
                SKColor.white.withAlphaComponent(0.95).cgColor,
                SKColor(red: 0.88, green: 1, blue: 0.42, alpha: 0.35).cgColor,
                SKColor.clear.cgColor,
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.28, 1]
            ) else { return }
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: 9, y: 9),
                startRadius: 0,
                endCenter: CGPoint(x: 9, y: 9),
                endRadius: 9,
                options: []
            )
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()

    private static func normalizedAlphaSamples(
        imageNamed name: String,
        maximumSamplesPerAxis: Int
    ) -> [CGPoint] {
        guard let cg = UIImage(named: name)?.cgImage, cg.width > 1, cg.height > 1 else { return [] }
        let width = cg.width
        let height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        let stride = max(1, max(width, height) / maximumSamplesPerAxis)
        var result: [CGPoint] = []
        for row in Swift.stride(from: stride / 2, to: height, by: stride) {
            for column in Swift.stride(from: stride / 2, to: width, by: stride) {
                let alpha = pixels[(row * width + column) * 4 + 3]
                if alpha > 80 {
                    result.append(CGPoint(
                        x: (CGFloat(column) + 0.5) / CGFloat(width),
                        y: (CGFloat(row) + 0.5) / CGFloat(height)
                    ))
                }
            }
        }
        return result
    }

    // MARK: Helpers

    private static let petals: [(x: CGFloat, y: CGFloat, s: CGFloat)] = [
        (0.08, 0.42, 0.6), (0.17, 0.70, 0.3), (0.27, 0.30, 0.9), (0.34, 0.62, 0.5),
        (0.45, 0.48, 0.2), (0.52, 0.78, 0.7), (0.61, 0.36, 0.4), (0.69, 0.66, 0.8),
        (0.77, 0.44, 0.3), (0.84, 0.72, 0.6), (0.91, 0.34, 0.5), (0.13, 0.88, 0.4),
    ]

    /// A vertical gradient only needs a narrow source texture. Rendering it at
    /// full-screen points with the device's 3x scale created a multi-megabyte
    /// bitmap and texture upload on the main thread; SpriteKit can stretch this
    /// small linear-filtered texture without changing the result.
    private static func gradientTexture(top: SKColor, bottom: SKColor) -> SKTexture {
        let textureSize = CGSize(width: 2, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: textureSize, format: format)
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: [0, 1]) else { return }
            cg.drawLinearGradient(grad,
                                  start: CGPoint(x: textureSize.width / 2, y: 0),
                                  end: CGPoint(x: textureSize.width / 2, y: textureSize.height),
                                  options: [])
        }
        let texture = SKTexture(image: img)
        texture.filteringMode = .linear
        return texture
    }
}

import SpriteKit
import SwiftUI

// MARK: - Pibo home stage (SpriteKit)
//
// The home activity zone is a SpriteKit scene (chosen for the growing amount of
// 2D-game-like animation: idle motion, 拍一拍 reactions, 拔毛, 头顶毛/能量收集,
// background transitions, particles). SwiftUI owns only the surrounding chrome.
//
// Data in: a `PiboTheme` (scene backdrop + head item), a `PiboGrowthStage`
// (魔丸 「?」卷芽 ⇄ 发芽带叶), and a `PiboActivityState` (drives Pibo's
// face/posture). Touches on Pibo call `onPat`; the SwiftUI layer decides how
// Pibo reacts (the spec's caps live in `PetStateStore.pat()`).
//
// Node tree (z back→front): backdrop(sky → ground) → pibo(shadow, body, eyes,
// blush, head 毛) → overhead 黑洞 → fx (Zzz / sparkles / seeds). A
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
    /// Fired on a tap that lands on Pibo.
    var onPat: (() -> Void)?

    // — Nodes —
    private let backdrop = SKNode()      // sky + ground
    private let pibo = SKNode()          // body group (bobs as a unit)
    private var bodyNode: SKShapeNode?   // procedural egg body
    private var bodySprite: SKSpriteNode? // art body (when theme.bodyImage set)
    private var leftEye = SKNode()
    private var rightEye = SKNode()
    private var blush = SKNode()
    private var headNode = SKSpriteNode()
    private let overheadNode = SKSpriteNode()  // 魔丸黑洞 — floats above the head
    private let fx = SKNode()            // transient effects layer
    private let cam = SKCameraNode()

    private var built = false
    /// True while the 发芽 close-up owns the camera (blocks pats + relayouts
    /// from snapping the camera back mid-flight).
    private var closeupActive = false

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .clear
        if size.width > 1, size.height > 1 { buildIfNeeded() }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        buildIfNeeded()
        layoutAll()
    }

    override func update(_ currentTime: TimeInterval) {
        // Belt-and-suspenders: if the scene wasn't built by didMove/didChangeSize
        // (SwiftUI SpriteView size timing), build as soon as a valid size lands.
        if !built, size.width > 1, size.height > 1 { buildIfNeeded() }
    }

    // MARK: Public API (called from the SwiftUI wrapper)

    func apply(theme newTheme: PiboTheme, state newState: PiboActivityState, growth newGrowth: PiboGrowthStage) {
        let themeChanged = newTheme.id != theme.id
        let growthChanged = newGrowth != growth
        let stateChanged = newState != activityState
        theme = newTheme
        activityState = newState
        growth = newGrowth
        guard built else { return }
        // A theme may switch between art and procedural Pibo, so rebuild the body
        // group (not just the backdrop/head) when the theme changes.
        if themeChanged { rebuildBackdrop(); rebuildPibo() }
        else if growthChanged { rebuildHead() }
        if stateChanged || themeChanged { applyState(animated: true) }
    }

    /// 能量收集 — the head 毛 senses new energy: shake → grow → settle, with a
    /// little sparkle burst (spec §3.4). The small in-place animation, used when
    /// the head is already sprouted (the first collection plays the close-up).
    func playEnergyGain() {
        guard built else { return }
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

    // MARK: Touch → pat

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard built, !closeupActive, let t = touches.first else { return }
        let p = t.location(in: self)
        // Generous hit area around Pibo.
        let dx = p.x - pibo.position.x
        let dy = p.y - (pibo.position.y + bodyHeight * 0.3)
        if dx * dx + dy * dy < pow(bodyWidth * 0.8, 2) {
            bouncePibo()
            onPat?()
        }
    }

    // MARK: - Build

    private func buildIfNeeded() {
        guard !built, size.width > 1, size.height > 1 else { return }
        built = true
        addChild(backdrop)
        addChild(pibo)
        overheadNode.zPosition = 13   // over the head 毛 — the curl emerges from the hole
        addChild(overheadNode)
        addChild(fx)
        fx.zPosition = 40
        cam.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cam)
        camera = cam

        rebuildBackdrop()
        buildPibo()
        rebuildHead()
        layoutAll()
        applyState(animated: false)
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
        usesArt ? size.width * (239.262 / 393.0) : min(size.width * 0.34, 150)
    }
    private var bodyHeight: CGFloat {
        usesArt ? bodyWidth * (235.0 / 239.262) : bodyWidth * 1.12
    }
    private var groundTopY: CGFloat { size.height * 0.34 }   // ground band height from bottom

    /// Tear down and rebuild the body group for the current theme — used when the
    /// theme changes (art ⇄ procedural body) at runtime.
    private func rebuildPibo() {
        pibo.removeAllChildren()
        bodyNode = nil
        bodySprite = nil
        buildPibo()
        rebuildHead()
        layoutAll()
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

    private func rebuildBackdrop() {
        backdrop.removeAllChildren()
        let scene = theme.scene

        // Art path: one full-bleed backdrop sprite (sky + grass + ground baked in).
        if let bg = scene.backgroundImage {
            let sprite = SKSpriteNode(texture: SKTexture(imageNamed: bg))
            sprite.zPosition = 0
            sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
            sprite.size = size
            backdrop.addChild(sprite)
            return
        }

        // Sky gradient.
        let sky = SKSpriteNode(texture: Self.gradientTexture(
            size: size, top: SKColor(scene.skyTop), bottom: SKColor(scene.skyBottom)))
        sky.anchorPoint = .zero
        sky.position = .zero
        sky.zPosition = 0
        backdrop.addChild(sky)

        // Ground per terrain.
        let ground = SKShapeNode(path: groundPath(scene.terrain))
        ground.fillColor = SKColor(scene.ground)
        ground.strokeColor = .clear
        ground.zPosition = 1
        backdrop.addChild(ground)

        addGroundDetail(scene)
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

    private func addGroundDetail(_ scene: PiboScene) {
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
                backdrop.addChild(petal)
            }
        case .beach:
            let sea = SKShapeNode(rect: CGRect(x: 0, y: top - 18, width: w, height: size.height * 0.14))
            sea.fillColor = SKColor(scene.groundAccent)
            sea.strokeColor = .clear
            sea.zPosition = 0.5
            backdrop.addChild(sea)
        case .platform:
            let edge = SKShapeNode(rect: CGRect(x: w * 0.21, y: top - size.height * 0.095,
                                                width: w * 0.72, height: size.height * 0.04))
            edge.fillColor = SKColor(scene.groundAccent)
            edge.strokeColor = .clear
            edge.zPosition = 0.9
            backdrop.addChild(edge)
        }
    }

    // MARK: Head item (theme art, or rendered from the SwiftUI design-system view)

    private func rebuildHead() {
        let (head, overhead) = theme.resolvedHead(for: growth)

        // Overhead 黑洞 — scene-level so the curl slides through it as Pibo bobs.
        if let overhead {
            overheadNode.texture = SKTexture(imageNamed: overhead.image)
            overheadNode.isHidden = false
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
        rebuildBackdrop()
        if usesArt {
            // Place the body sprite at the theme's design-frame body center;
            // size it to the mapped body box.
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
        // Art bodies bake the face/expression into the sprite — only posture-level
        // cues apply (Zzz when asleep, a brief turn-away when 被打扰). Per-state art
        // swaps come with the state-machine pass.
        if usesArt {
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
        guard show else { return }
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
            .run { z.position = CGPoint(x: self.pibo.position.x + self.bodyWidth * 0.5, y: self.pibo.position.y + self.bodyHeight * 0.45) },
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
        let l = SKAction.rotate(toAngle: 0.06, duration: 1.4); l.timingMode = .easeInEaseOut
        let r = SKAction.rotate(toAngle: -0.06, duration: 1.4); r.timingMode = .easeInEaseOut
        headNode.run(.repeatForever(.sequence([l, r])), withKey: "headIdle")
    }

    private func bouncePibo() {
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

    // MARK: Helpers

    private static let petals: [(x: CGFloat, y: CGFloat, s: CGFloat)] = [
        (0.08, 0.42, 0.6), (0.17, 0.70, 0.3), (0.27, 0.30, 0.9), (0.34, 0.62, 0.5),
        (0.45, 0.48, 0.2), (0.52, 0.78, 0.7), (0.61, 0.36, 0.4), (0.69, 0.66, 0.8),
        (0.77, 0.44, 0.3), (0.84, 0.72, 0.6), (0.91, 0.34, 0.5), (0.13, 0.88, 0.4),
    ]

    private static func gradientTexture(size: CGSize, top: SKColor, bottom: SKColor) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: [0, 1]) else { return }
            cg.drawLinearGradient(grad,
                                  start: CGPoint(x: size.width / 2, y: 0),
                                  end: CGPoint(x: size.width / 2, y: size.height),
                                  options: [])
        }
        return SKTexture(image: img)
    }
}

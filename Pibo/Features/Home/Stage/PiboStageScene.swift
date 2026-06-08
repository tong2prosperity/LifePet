import SpriteKit
import SwiftUI

// MARK: - Pibo home stage (SpriteKit)
//
// The home activity zone is a SpriteKit scene (chosen for the growing amount of
// 2D-game-like animation: idle motion, 拍一拍 reactions, 拔毛, 头顶毛/能量收集,
// background transitions, particles). SwiftUI owns only the surrounding chrome.
//
// Data in: a `PiboTheme` (scene backdrop + head item) and a `PiboActivityState`
// (drives Pibo's face/posture). Touches on Pibo call `onPat`; the SwiftUI layer
// decides whether Pibo speaks (the spec's caps live in `PetStateStore.pat()`).
//
// Node tree (z back→front): sky → ground → pibo(shadow, body, eyes, blush) →
// head item → fx (Zzz / sparkles / seeds).

final class PiboStageScene: SKScene {

    // — Inputs (set by the SwiftUI wrapper) —
    private(set) var theme: PiboTheme = .sprout
    private(set) var activityState: PiboActivityState = .idle
    /// Fired on a tap that lands on Pibo.
    var onPat: (() -> Void)?

    // — Nodes —
    private let backdrop = SKNode()      // sky + ground
    private let pibo = SKNode()          // body group (bobs as a unit)
    private var bodyNode: SKShapeNode?
    private var leftEye = SKNode()
    private var rightEye = SKNode()
    private var blush = SKNode()
    private var headNode = SKSpriteNode()
    private let fx = SKNode()            // transient effects layer

    private var built = false

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

    // MARK: Public API (called from the SwiftUI wrapper)

    func apply(theme newTheme: PiboTheme, state newState: PiboActivityState) {
        let themeChanged = newTheme.id != theme.id
        let stateChanged = newState != activityState
        theme = newTheme
        activityState = newState
        guard built else { return }
        if themeChanged { rebuildBackdrop(); rebuildHead() }
        if stateChanged || themeChanged { applyState(animated: true) }
    }

    /// 能量收集 — the head 毛 senses new energy: shake → grow → settle, with a
    /// little sparkle burst (spec §3.4).
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
        guard built, let t = touches.first else { return }
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
        addChild(fx)
        fx.zPosition = 40

        rebuildBackdrop()
        buildPibo()
        rebuildHead()
        layoutAll()
        applyState(animated: false)
        startIdleBob()
        startHeadIdle()
    }

    private var bodyWidth: CGFloat { min(size.width * 0.34, 150) }
    private var bodyHeight: CGFloat { bodyWidth * 1.12 }
    private var groundTopY: CGFloat { size.height * 0.34 }   // ground band height from bottom

    private func buildPibo() {
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

    // MARK: Head item (rendered from the SwiftUI design-system view → texture)

    private func rebuildHead() {
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
        pibo.position = CGPoint(x: size.width / 2, y: groundTopY + bodyHeight * 0.18)
        positionHead()
    }

    private func positionHead() {
        headNode.position = CGPoint(x: 0, y: bodyHeight * 0.5 + headNode.size.height * 0.32)
    }

    // MARK: State

    private func applyState(animated: Bool) {
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
            // Turn away briefly.
            pibo.run(.sequence([.rotate(toAngle: 0.12, duration: 0.15), .wait(forDuration: 0.6), .rotate(toAngle: 0, duration: 0.2)]))
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
        bodyNode?.removeAction(forKey: "squash")
        let squash = SKAction.sequence([
            .scaleX(to: 1.12, y: 0.9, duration: 0.08),
            .scaleX(to: 0.94, y: 1.08, duration: 0.10),
            .scaleX(to: 1.0, y: 1.0, duration: 0.12),
        ])
        bodyNode?.run(squash, withKey: "squash")
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

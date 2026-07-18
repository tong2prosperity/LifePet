import SpriteKit
import SwiftUI
import UIKit

enum PiboCharacterHitRegion {
    case hair
    case body
    case none
}

/// Shared Pibo renderer. Theme renderers supply placement and atmosphere while
/// this component owns character art, state, hit geometry, and authored FX.
final class PiboCharacterRenderer {
    let rootNode = SKNode()
    let overheadNode = SKSpriteNode()
    let effectsNode = SKNode()

    var onHairPulled: () -> Void = {}
    private weak var scene: SKScene?
    private weak var camera: SKCameraNode?
    private var theme: PiboTheme = .forest
    private var state: PiboActivityState = .idle
    private var growth: PiboGrowthStage = .mystery
    private var placement: PiboCharacterPlacement?
    private var visible = true

    private var bodyNode: SKShapeNode?
    private var bodySprite: SKSpriteNode?
    private var bodyArtwork: PiboSVGArtwork?
    private var leftEye = SKNode()
    private var rightEye = SKNode()
    private var blush = SKNode()
    private let headNode = SKSpriteNode()
    private let headRig = PiboHeadRigDeformer()
    private var sproutGrowthProgress: CGFloat = 1
    private var headArtwork: PiboSVGArtwork?
    private var hairDragOrigin: CGPoint?
    private var surface: [CGPoint] = []
    private(set) var isCloseupActive = false

    var bodyForReflection: SKNode? { bodySprite ?? bodyNode }
    var headForReflection: SKSpriteNode { headNode }
    var headNaturalSize: CGSize? { headNode.texture?.size() }
    var overheadNaturalSize: CGSize? { overheadNode.texture?.size() }
    var bodyWidth: CGFloat { placement?.body.size.width ?? 1 }
    var bodyHeight: CGFloat { placement?.body.size.height ?? 1 }

    func install(scene: SKScene, camera: SKCameraNode) {
        self.scene = scene
        self.camera = camera
        overheadNode.zPosition = 13
        effectsNode.zPosition = 55
    }

    func apply(
        theme newTheme: PiboTheme,
        state newState: PiboActivityState,
        growth newGrowth: PiboGrowthStage,
        placement newPlacement: PiboCharacterPlacement,
        animated: Bool
    ) {
        let themeChanged = newTheme.id != theme.id
        let growthChanged = newGrowth != growth
        let stateChanged = newState != state
        theme = newTheme
        state = newState
        growth = newGrowth
        placement = newPlacement

        if rootNode.parent != nil {
            if themeChanged {
                rebuildBody()
            } else if growthChanged {
                rebuildHead()
            }
            layout()
            if stateChanged || themeChanged { applyState(animated: animated) }
        }
    }

    func buildIfNeeded() {
        guard rootNode.children.isEmpty else { return }
        buildBody()
        rebuildHead()
        layout()
        applyState(animated: false)
        startIdleBob()
        startHeadIdle()
    }

    func setVisible(_ isVisible: Bool) {
        visible = isVisible
        rootNode.isHidden = !isVisible
        overheadNode.isHidden = !isVisible || theme.resolvedHead(for: growth).overhead == nil
        showZzz(isVisible && state == .deepSleep)
    }

    func applyShader(_ shader: SKShader?) {
        bodySprite?.shader = shader
        headNode.shader = shader
    }

    func hitRegion(at point: CGPoint, in scene: SKScene) -> PiboCharacterHitRegion {
        guard visible else { return .none }
        if !headNode.isHidden {
            if headRig.isEnabled {
                let local = scene.convert(point, to: rootNode)
                let interactiveFrame = headNode.frame.insetBy(dx: -12, dy: -10)
                if interactiveFrame.contains(local) { return .hair }
            }
            if let headArtwork {
                let local = scene.convert(point, to: headNode)
                if headArtwork.contains(
                    spriteLocalPoint: local,
                    displayedSize: headNode.size,
                    anchorPoint: headNode.anchorPoint
                ) { return .hair }
            } else {
                let local = scene.convert(point, to: rootNode)
                let frame = headNode.frame
                let padX = max(12, (44 - frame.width) / 2)
                let padY = max(12, (44 - frame.height) / 2)
                if frame.insetBy(dx: -padX, dy: -padY).contains(local) { return .hair }
            }
        }
        if let bodySprite, let bodyArtwork {
            let local = scene.convert(point, to: bodySprite)
            return bodyArtwork.contains(
                spriteLocalPoint: local,
                displayedSize: bodySprite.size,
                anchorPoint: bodySprite.anchorPoint
            ) ? .body : .none
        }
        let dx = point.x - rootNode.position.x
        let dy = point.y - (rootNode.position.y + bodyHeight * 0.3)
        return dx * dx + dy * dy < pow(bodyWidth * 0.8, 2) ? .body : .none
    }

    func beginHairDrag(at point: CGPoint) {
        hairDragOrigin = point
        headNode.removeAction(forKey: "headIdle")
        headNode.removeAction(forKey: "hairSettle")
        headRig.beginInteraction()
    }

    func moveHairDrag(to point: CGPoint) {
        guard let origin = hairDragOrigin else { return }
        let dx = point.x - origin.x
        let up = max(0, point.y - origin.y)
        if headRig.isEnabled {
            headRig.setInteraction(horizontalDisplacement: dx, upwardDisplacement: up)
            return
        }
        headNode.zRotation = -0.55 * Self.rubberBand(dx, limit: 110) / 110
        headNode.yScale = 1 + 0.28 * Self.rubberBand(up, limit: 130) / 130
    }

    func endHairDrag(at point: CGPoint, cancelled: Bool) {
        guard let origin = hairDragOrigin else { return }
        hairDragOrigin = nil
        let pulled = !cancelled && hypot(point.x - origin.x, point.y - origin.y) > 30
        if headRig.isEnabled {
            headRig.endInteraction(pulled: pulled)
            if pulled {
                emitSparkles(at: CGPoint(
                    x: rootNode.position.x + headNode.position.x,
                    y: rootNode.position.y + headNode.position.y
                ), count: 10)
                onHairPulled()
            }
            return
        }
        let releaseAngle = headNode.zRotation
        let settle: SKAction
        if pulled {
            emitSparkles(at: CGPoint(
                x: rootNode.position.x + headNode.position.x,
                y: rootNode.position.y + headNode.position.y
            ), count: 10)
            settle = .sequence([
                .group([
                    .scaleY(to: 1, duration: 0.10),
                    .rotate(toAngle: -releaseAngle * 0.5, duration: 0.10),
                ]),
                .rotate(toAngle: releaseAngle * 0.18, duration: 0.10),
                .rotate(toAngle: 0, duration: 0.14),
            ])
        } else {
            settle = .sequence([
                .group([.scaleY(to: 1, duration: 0.12), .rotate(toAngle: 0, duration: 0.12)]),
                .rotate(byAngle: 0.08, duration: 0.08),
                .rotate(byAngle: -0.08, duration: 0.10),
            ])
        }
        headNode.run(.sequence([
            settle,
            .run { [weak self] in self?.startHeadIdle() },
        ]), withKey: "hairSettle")
        if pulled { onHairPulled() }
    }

    func playBodyTap() {
        bodyForReflection?.removeAction(forKey: "squash")
        bodyForReflection?.run(.sequence([
            .scaleX(to: 1.12, y: 0.9, duration: 0.08),
            .scaleX(to: 0.94, y: 1.08, duration: 0.10),
            .scaleX(to: 1, y: 1, duration: 0.12),
        ]), withKey: "squash")
    }

    func playEnergyGain() {
        if headRig.isEnabled {
            headRig.addImpulse(1.7)
            headNode.run(.sequence([.scale(to: 1.10, duration: 0.16), .scale(to: 1, duration: 0.24)]))
            emitSparkles(
                at: CGPoint(x: rootNode.position.x, y: rootNode.position.y + bodyHeight * 0.7),
                count: 14
            )
            return
        }
        headNode.removeAction(forKey: "headIdle")
        let shake = SKAction.sequence([
            .rotate(toAngle: 0.18, duration: 0.06),
            .rotate(toAngle: -0.18, duration: 0.10),
            .rotate(toAngle: 0.10, duration: 0.08),
            .rotate(toAngle: 0, duration: 0.08),
        ])
        let grow = SKAction.sequence([.scale(to: 1.18, duration: 0.18), .scale(to: 1, duration: 0.22)])
        headNode.run(.sequence([shake, grow])) { [weak self] in self?.startHeadIdle() }
        emitSparkles(
            at: CGPoint(x: rootNode.position.x, y: rootNode.position.y + bodyHeight * 0.7),
            count: 14
        )
    }

    func setSproutGrowthProgress(_ progress: CGFloat) {
        sproutGrowthProgress = min(max(progress, 0), 1)
        headRig.setGrowthProgress(sproutGrowthProgress)
    }

    func playSproutGrowth(from start: CGFloat, to target: CGFloat, duration: TimeInterval) {
        sproutGrowthProgress = min(max(target, 0), 1)
        headRig.animateGrowth(from: start, to: sproutGrowthProgress, duration: duration)
        headRig.addImpulse(0.8 + (sproutGrowthProgress - start) * 2.4)
        emitSparkles(
            at: CGPoint(x: rootNode.position.x, y: rootNode.position.y + bodyHeight * 0.7),
            count: 12
        )
    }

    func playSproutCloseup(
        growthFrom start: CGFloat,
        growthTo target: CGFloat,
        onPhase: @escaping (SproutCloseupPhase) -> Void
    ) {
        guard let scene, let camera, !isCloseupActive else { onPhase(.finished); return }
        isCloseupActive = true
        headNode.removeAction(forKey: "headIdle")
        let headWorld = CGPoint(
            x: rootNode.position.x + headNode.position.x,
            y: rootNode.position.y + headNode.position.y
        )
        let focus = CGPoint(x: headWorld.x, y: headWorld.y - scene.size.height * 0.06)
        let zoomIn = SKAction.group([.move(to: focus, duration: 0.55), .scale(to: 0.45, duration: 0.55)])
        zoomIn.timingMode = .easeInEaseOut
        let zoomOut = SKAction.group([
            .move(to: CGPoint(x: scene.size.width / 2, y: scene.size.height / 2), duration: 0.55),
            .scale(to: 1, duration: 0.55),
        ])
        zoomOut.timingMode = .easeInEaseOut

        let wiggle = SKAction.sequence([
            (0.10, 0.10), (-0.12, 0.16), (0.16, 0.14), (-0.20, 0.16),
            (0.24, 0.14), (-0.26, 0.16), (0.30, 0.14), (-0.30, 0.16),
        ].map { angle, duration in
            let action = SKAction.rotate(toAngle: CGFloat(angle), duration: duration)
            action.timingMode = .easeInEaseOut
            return action
        })
        let strain = SKAction.scale(to: 0.78, duration: 0.22)
        strain.timingMode = .easeIn
        let swap = SKAction.run { [weak self] in
            guard let self else { return }
            self.growth = .sprouted
            self.sproutGrowthProgress = start
            self.rebuildHead()
            self.headRig.setGrowthProgress(start)
            self.playSproutGrowth(from: start, to: target, duration: 1.35)
            self.overheadNode.run(.fadeOut(withDuration: 0.45))
            self.emitSparkles(at: headWorld, count: 18)
        }
        let burst = SKAction.sequence([.scale(to: 1.25, duration: 0.20), .scale(to: 1, duration: 0.24)])
        burst.timingMode = .easeOut
        camera.run(.sequence([
            zoomIn,
            .run { onPhase(.shaking) },
            .wait(forDuration: 2.12),
            .run { onPhase(.sprouted) },
            .wait(forDuration: 1.5),
            zoomOut,
            .run { [weak self] in
                self?.isCloseupActive = false
                self?.startHeadIdle()
                onPhase(.finished)
            },
        ]), withKey: "closeup")
        headNode.run(.sequence([
            .wait(forDuration: 0.55), wiggle, .rotate(toAngle: 0, duration: 0.08), strain, swap, burst,
        ]), withKey: "sprout")
    }

    func playTurnAway() {
        if let backName = theme.bodyBackImage, let body = bodySprite {
            guard body.action(forKey: "turnAway") == nil else { return }
            let frontTexture = body.texture
            let frontSize = body.size
            let backTexture = SKTexture(imageNamed: backName)
            let natural = backTexture.size()
            let backWidth = (scene?.size.width ?? 393) * (232 / 393)
            let backSize = CGSize(width: backWidth, height: backWidth * natural.height / max(natural.width, 1))
            let swapBack = SKAction.run {
                body.texture = backTexture
                body.size = backSize
                body.position.y = -(frontSize.height - backSize.height) / 2
            }
            let swapFront = SKAction.run {
                body.texture = frontTexture
                body.size = frontSize
                body.position.y = 0
            }
            let hop = SKAction.sequence([
                .scaleX(to: 0.86, y: 1.04, duration: 0.10),
                .scaleX(to: 1, y: 1, duration: 0.12),
            ])
            body.run(.sequence([hop, swapBack, .wait(forDuration: 1.4), swapFront, hop.copy() as! SKAction]),
                     withKey: "turnAway")
        } else {
            guard rootNode.action(forKey: "turnAway") == nil else { return }
            rootNode.run(.sequence([
                .rotate(toAngle: 0.45, duration: 0.18),
                .wait(forDuration: 1.2),
                .rotate(toAngle: 0, duration: 0.22),
            ]), withKey: "turnAway")
        }
    }

    func playPluck(color: SKColor) {
        let seed = SKShapeNode(ellipseOf: CGSize(width: 14, height: 18))
        seed.fillColor = color
        seed.strokeColor = .clear
        seed.position = CGPoint(x: rootNode.position.x, y: rootNode.position.y + bodyHeight * 0.65)
        seed.zPosition = 50
        effectsNode.addChild(seed)
        headRig.addImpulse(CGFloat.random(in: -2.3 ... 2.3))
        let drop = SKAction.moveBy(x: CGFloat.random(in: -16...16), y: -bodyHeight * 0.5, duration: 0.8)
        drop.timingMode = .easeIn
        seed.run(.sequence([.wait(forDuration: 0.1), drop, .fadeOut(withDuration: 0.4), .removeFromParent()]))
        headNode.run(.sequence([.rotate(byAngle: 0.2, duration: 0.08), .rotate(byAngle: -0.2, duration: 0.12)]))
    }

    func randomPrecipitationPoint() -> CGPoint? {
        if surface.isEmpty { rebuildSurface() }
        guard visible, let local = surface.randomElement() else { return nil }
        return CGPoint(
            x: rootNode.position.x + local.x + CGFloat.random(in: -2...2),
            y: rootNode.position.y + local.y + CGFloat.random(in: -2...3)
        )
    }

    private var usesArt: Bool { theme.bodyImage != nil }

    private func rebuildBody() {
        rootNode.removeAllChildren()
        bodyNode = nil
        bodySprite = nil
        bodyArtwork = nil
        buildBody()
        rebuildHead()
        startIdleBob()
        startHeadIdle()
    }

    private func buildBody() {
        guard let placement else { return }
        if usesArt, let name = theme.bodyImage {
            bodyArtwork = PiboSVGAssets.artwork(named: name)
            let texture = bodyArtwork?.makeTexture() ?? SKTexture(imageNamed: name)
            let body = SKSpriteNode(texture: texture)
            body.zPosition = 10
            bodySprite = body
            rootNode.addChild(body)
            headNode.zPosition = 12
            rootNode.addChild(headNode)
            return
        }

        let width = placement.body.size.width
        let height = placement.body.size.height
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        let body = SKShapeNode(path: CGPath(
            roundedRect: rect,
            cornerWidth: width * 0.5,
            cornerHeight: height * 0.46,
            transform: nil
        ))
        body.fillColor = .white
        body.strokeColor = SKColor(white: 0.82, alpha: 1)
        body.lineWidth = 2
        body.zPosition = 10
        bodyNode = body

        let shadow = SKShapeNode(ellipseOf: CGSize(width: width * 1.05, height: height * 0.16))
        shadow.fillColor = SKColor(white: 0, alpha: 0.10)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -height * 0.5)
        shadow.zPosition = 9
        let footSize = CGSize(width: width * 0.26, height: width * 0.16)
        for sign in [-1.0, 1.0] {
            let foot = SKShapeNode(ellipseOf: footSize)
            foot.fillColor = .white
            foot.strokeColor = SKColor(white: 0.82, alpha: 1)
            foot.lineWidth = 1.5
            foot.position = CGPoint(x: CGFloat(sign) * width * 0.20, y: -height * 0.46)
            foot.zPosition = 9.5
            rootNode.addChild(foot)
        }
        rootNode.addChild(shadow)
        rootNode.addChild(body)
        buildFace()
        rootNode.addChild(blush)
        rootNode.addChild(leftEye)
        rootNode.addChild(rightEye)
        headNode.zPosition = 12
        rootNode.addChild(headNode)
    }

    private func buildFace() {
        let width = bodyWidth
        let height = bodyHeight
        let eyeOffsetX = width * 0.17
        let eyeY = height * 0.04
        for (eye, sign) in [(leftEye, -1.0), (rightEye, 1.0)] {
            eye.removeAllChildren()
            eye.position = CGPoint(x: CGFloat(sign) * eyeOffsetX, y: eyeY)
            eye.zPosition = 11
        }
        blush.removeAllChildren()
        for sign in [-1.0, 1.0] {
            let cheek = SKShapeNode(ellipseOf: CGSize(width: width * 0.16, height: width * 0.10))
            cheek.fillColor = SKColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 0.55)
            cheek.strokeColor = .clear
            cheek.position = CGPoint(x: CGFloat(sign) * width * 0.30, y: -height * 0.02)
            blush.addChild(cheek)
        }
        blush.alpha = 0
        blush.zPosition = 10.5
    }

    private func rebuildHead() {
        let resolved = theme.resolvedHead(for: growth)
        headArtwork = nil
        if let overhead = resolved.overhead {
            overheadNode.texture = SKTexture(imageNamed: overhead.image)
            overheadNode.isHidden = !visible
            overheadNode.alpha = 1
        } else {
            overheadNode.isHidden = true
        }
        if let head = resolved.head {
            headArtwork = PiboSVGAssets.artwork(named: head.image)
            headNode.texture = headArtwork?.makeTexture() ?? SKTexture(imageNamed: head.image)
            headNode.isHidden = false
            headRig.attach(to: headNode, imageName: head.image)
            headRig.setGrowthProgress(sproutGrowthProgress)
        } else if usesArt {
            headNode.isHidden = true
            headRig.attach(to: headNode, imageName: nil)
        } else {
            headNode.isHidden = false
            headRig.attach(to: headNode, imageName: nil)
            let side = bodyWidth * 0.9
            let renderer = ImageRenderer(content:
                PiboHeadItemView(item: theme.headItem, size: side)
                    .frame(width: side * (theme.headItem == .mystery ? 1.7 : 1), height: side)
            )
            renderer.scale = UIScreen.main.scale
            if let image = renderer.uiImage {
                headNode.texture = SKTexture(image: image)
                headNode.size = image.size.applying(.init(scaleX: 1 / renderer.scale, y: 1 / renderer.scale))
            }
        }
        layout()
        surface.removeAll(keepingCapacity: true)
    }

    private func layout() {
        guard let placement else { return }
        bodySprite?.size = placement.body.size
        rootNode.position = placement.body.position
        rootNode.zPosition = placement.characterZ
        if let head = placement.head {
            headNode.position = head.position
            headNode.size = head.size
        } else if !usesArt {
            headNode.position = CGPoint(x: 0, y: bodyHeight * 0.5 + headNode.size.height * 0.32)
        }
        if let overhead = placement.overhead {
            overheadNode.position = overhead.position
            overheadNode.size = overhead.size
        }
        overheadNode.zPosition = placement.overheadZ
        surface.removeAll(keepingCapacity: true)
    }

    private enum EyeKind { case open, closed, half }

    private func setEyes(_ kind: EyeKind) {
        let width = bodyWidth
        for eye in [leftEye, rightEye] {
            eye.removeAllChildren()
            switch kind {
            case .open:
                let shape = SKShapeNode(ellipseOf: CGSize(width: width * 0.085, height: width * 0.11))
                shape.fillColor = SKColor(white: 0.12, alpha: 1)
                shape.strokeColor = .clear
                eye.addChild(shape)
            case .closed:
                let line = SKShapeNode()
                let path = CGMutablePath()
                path.move(to: CGPoint(x: -width * 0.06, y: 0))
                path.addQuadCurve(
                    to: CGPoint(x: width * 0.06, y: 0),
                    control: CGPoint(x: 0, y: -width * 0.04)
                )
                line.path = path
                line.strokeColor = SKColor(white: 0.12, alpha: 1)
                line.lineWidth = 2.2
                line.lineCap = .round
                eye.addChild(line)
            case .half:
                let shape = SKShapeNode(ellipseOf: CGSize(width: width * 0.085, height: width * 0.06))
                shape.fillColor = SKColor(white: 0.12, alpha: 1)
                shape.strokeColor = .clear
                eye.addChild(shape)
            }
        }
    }

    private func applyState(animated: Bool) {
        if usesArt {
            if placement?.usesCanonicalMotion == true {
                applyCanonicalState(animated: animated)
            } else {
                showZzz(state == .deepSleep)
                if state == .disturbed { playTurnAway() }
            }
            return
        }
        switch state {
        case .deepSleep: setEyes(.closed); setBlush(0); showZzz(true); setBodyTint(0.97)
        case .waking: setEyes(.half); setBlush(0); showZzz(false); setBodyTint(1)
        case .active: setEyes(.open); setBlush(0.7); showZzz(false); setBodyTint(1)
        case .irritated: setEyes(.half); setBlush(0.5); showZzz(false); setBodyTint(0.96)
        case .disturbed: setEyes(.half); setBlush(0.3); showZzz(false); setBodyTint(1); playTurnAway()
        case .idle: setEyes(.open); setBlush(0); showZzz(false); setBodyTint(1)
        }
    }

    private func applyCanonicalState(animated: Bool) {
        guard let body = bodySprite else { return }
        body.removeAction(forKey: "canonicalState")
        headNode.removeAction(forKey: "canonicalState")
        headNode.removeAction(forKey: "headIdle")
        showZzz(state == .deepSleep)
        let duration = animated ? 0.32 : 0
        switch state {
        case .deepSleep:
            body.run(.group([.scaleX(to: 1.03, y: 0.96, duration: duration), .rotate(toAngle: -0.025, duration: duration)]), withKey: "canonicalState")
            runHeadReaction(.rotate(toAngle: -0.12, duration: duration))
        case .waking:
            body.run(.group([.scaleX(to: 1, y: 1, duration: duration), .rotate(toAngle: 0.025, duration: duration)]), withKey: "canonicalState")
            runHeadReaction(.rotate(toAngle: -0.04, duration: duration))
        case .active:
            body.run(.sequence([
                .scaleX(to: 0.96, y: 1.06, duration: 0.12),
                .scaleX(to: 1.02, y: 0.98, duration: 0.12),
                .scaleX(to: 1, y: 1, duration: 0.16),
            ]), withKey: "canonicalState")
            runHeadReaction(.sequence([
                .rotate(toAngle: 0.10, duration: 0.12),
                .rotate(toAngle: -0.08, duration: 0.14),
                .rotate(toAngle: 0, duration: 0.18),
            ]))
        case .irritated:
            body.run(.group([.scaleX(to: 1.01, y: 0.98, duration: duration), .rotate(toAngle: 0.045, duration: duration)]), withKey: "canonicalState")
            runHeadReaction(.rotate(toAngle: 0.13, duration: duration))
        case .disturbed:
            body.setScale(1); playTurnAway(); startHeadIdle()
        case .idle:
            body.run(.group([.scaleX(to: 1, y: 1, duration: duration), .rotate(toAngle: 0, duration: duration)]), withKey: "canonicalState")
            runHeadReaction(.rotate(toAngle: 0, duration: duration))
        }
    }

    private func runHeadReaction(_ action: SKAction) {
        headNode.run(.sequence([action, .run { [weak self] in self?.startHeadIdle() }]), withKey: "canonicalState")
    }

    private func setBlush(_ alpha: CGFloat) { blush.run(.fadeAlpha(to: alpha, duration: 0.3)) }

    private func setBodyTint(_ brightness: CGFloat) {
        bodyNode?.fillColor = SKColor(white: brightness, alpha: 1)
    }

    private func showZzz(_ show: Bool) {
        effectsNode.childNode(withName: "zzz")?.removeFromParent()
        guard show, visible else { return }
        let label = SKLabelNode(text: "Zzz")
        label.name = "zzz"
        label.fontName = "AvenirNext-Bold"
        label.fontSize = bodyWidth * 0.2
        label.fontColor = SKColor(white: 0.6, alpha: 0.9)
        label.position = CGPoint(x: rootNode.position.x + bodyWidth * 0.5, y: rootNode.position.y + bodyHeight * 0.45)
        label.zPosition = 45
        effectsNode.addChild(label)
        label.run(.repeatForever(.sequence([
            .group([.moveBy(x: 8, y: 24, duration: 1.6), .fadeOut(withDuration: 1.6)]),
            .run { [weak self, weak label] in
                guard let self, let label else { return }
                label.position = CGPoint(x: self.rootNode.position.x + self.bodyWidth * 0.5,
                                         y: self.rootNode.position.y + self.bodyHeight * 0.45)
            },
            .fadeIn(withDuration: 0.01),
        ])))
    }

    private func startIdleBob() {
        rootNode.removeAction(forKey: "bob")
        let up = SKAction.moveBy(x: 0, y: 8, duration: 1.1); up.timingMode = .easeInEaseOut
        let down = SKAction.moveBy(x: 0, y: -8, duration: 1.1); down.timingMode = .easeInEaseOut
        rootNode.run(.repeatForever(.sequence([up, down])), withKey: "bob")
    }

    private func startHeadIdle() {
        headNode.removeAction(forKey: "headIdle")
        guard !headRig.isEnabled else {
            headNode.zRotation = 0
            headNode.xScale = 1
            headNode.yScale = 1
            return
        }
        let canonical = placement?.usesCanonicalMotion == true
        let center: CGFloat
        if canonical {
            switch state {
            case .deepSleep: center = -0.12
            case .waking: center = -0.04
            case .irritated: center = 0.13
            case .active, .disturbed, .idle: center = 0
            }
        } else { center = 0 }
        let amplitude: CGFloat = canonical ? 0.035 : 0.06
        let left = SKAction.rotate(toAngle: center + amplitude, duration: 1.4); left.timingMode = .easeInEaseOut
        let right = SKAction.rotate(toAngle: center - amplitude, duration: 1.4); right.timingMode = .easeInEaseOut
        headNode.run(.repeatForever(.sequence([left, right])), withKey: "headIdle")
    }

    func update(
        time: TimeInterval,
        deltaTime: TimeInterval,
        wind: StageWind,
        reduceMotion: Bool
    ) {
        headRig.update(
            time: time,
            deltaTime: deltaTime,
            wind: wind,
            reduceMotion: reduceMotion
        )
    }

    func setHeadRigFlexibility(_ flexibility: CGFloat) {
        headRig.flexibility = flexibility
    }

    private func emitSparkles(at point: CGPoint, count: Int) {
        for _ in 0..<count {
            let sparkle = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.5...3.5))
            sparkle.fillColor = SKColor(theme.scene.groundAccent)
            sparkle.strokeColor = .clear
            sparkle.position = point
            sparkle.zPosition = 46
            effectsNode.addChild(sparkle)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 20...60)
            let move = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance + 20, duration: 0.7)
            move.timingMode = .easeOut
            sparkle.run(.sequence([.group([move, .fadeOut(withDuration: 0.7)]), .removeFromParent()]))
        }
    }

    private func rebuildSurface() {
        guard let placement else { return }
        var points: [CGPoint] = []
        if usesArt, let name = theme.bodyImage {
            if let image = bodyArtwork?.image.cgImage {
                points += topSurfacePoints(cgImage: image, center: bodySprite?.position ?? .zero,
                                           size: placement.body.size, columns: 26)
            } else if let image = UIImage(named: name)?.cgImage {
                points += topSurfacePoints(cgImage: image, center: bodySprite?.position ?? .zero,
                                           size: placement.body.size, columns: 26)
            }
        }
        if points.isEmpty {
            for index in 0..<26 {
                let u = CGFloat(index) / 25 * 2 - 1
                points.append(CGPoint(
                    x: u * bodyWidth * 0.45,
                    y: bodyHeight * 0.5 * pow(max(0, 1 - u * u), 0.62)
                ))
            }
        }
        if !headNode.isHidden, let resolved = theme.resolvedHead(for: growth).head {
            let image = headArtwork?.image.cgImage ?? UIImage(named: resolved.image)?.cgImage
            if let image {
                points += topSurfacePoints(cgImage: image, center: headNode.position,
                                           size: headNode.size, columns: 10)
            }
        }
        surface = points
    }

    private func topSurfacePoints(
        cgImage: CGImage,
        center: CGPoint,
        size: CGSize,
        columns: Int
    ) -> [CGPoint] {
        let width = cgImage.width
        let height = cgImage.height
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
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var result: [CGPoint] = []
        for columnIndex in 0..<columns {
            let column = min(width - 1, Int((CGFloat(columnIndex) + 0.5) / CGFloat(columns) * CGFloat(width)))
            var topRow = -1
            for row in stride(from: height - 1, through: 0, by: -1) where pixels[(row * width + column) * 4 + 3] > 30 {
                topRow = row
                break
            }
            guard topRow >= 0 else { continue }
            let fx = (CGFloat(column) + 0.5) / CGFloat(width)
            let fy = (CGFloat(topRow) + 0.5) / CGFloat(height)
            result.append(CGPoint(
                x: center.x - size.width * 0.5 + fx * size.width,
                y: center.y - size.height * 0.5 + fy * size.height
            ))
        }
        return result
    }

    private static func rubberBand(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        limit * value / (abs(value) + limit)
    }
}

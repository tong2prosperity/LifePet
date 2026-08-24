import SpriteKit
import SwiftUI
import UIKit
import os

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

    var onSproutTouched: () -> Void = {}
    private weak var scene: SKScene?
    private weak var camera: SKCameraNode?
    private var theme: PiboTheme = .forest
    private var state: PiboActivityState = .dataUnknown
    private var animationStateID = PiboAnimationStateMap.fallback
    private var growth: PiboGrowthStage = .mystery
    private var placement: PiboCharacterPlacement?
    private var visible = true

    /// 矢量角色。开关打开时由它承担外观、命中几何与芽的形变；旧的双 sprite 路径
    /// 原样保留在下面，两条路可以在真机上并排比较，见 PiboVectorCharacterFlag。
    private var vector: PiboVectorCharacter?
    private var vectorTransition: PiboStateTransition?
    private var vectorIdle: PiboIdleAnimator?
    private var vectorPlaybook: PiboCharacterPlaybook?
    private var vectorRigInverted: Bool?
    private var boringElapsed: TimeInterval = 0
    private let boProgressHost = SKNode()
    private var pendingBoProgress: BoProgressPresentation?
    private let usesVector = PiboVectorCharacterFlag.isEnabled

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

    var bodyForReflection: SKNode? { vector?.reflectionSource ?? bodySprite ?? bodyNode }
    /// 矢量角色是一棵 shape 树、没有纹理，倒影靠一张定期快照的隐藏代理供图。
    var headForReflection: SKSpriteNode { vector?.reflectionSource ?? headNode }
    var headNaturalSize: CGSize? { headNode.texture?.size() }
    var overheadNaturalSize: CGSize? { overheadNode.texture?.size() }
    var bodyWidth: CGFloat { placement?.body.size.width ?? 1 }
    var bodyHeight: CGFloat { placement?.body.size.height ?? 1 }

    func install(scene: SKScene, camera: SKCameraNode) {
        self.scene = scene
        self.camera = camera
        overheadNode.zPosition = 13
        effectsNode.zPosition = 55
        boProgressHost.zPosition = 8
        effectsNode.addChild(boProgressHost)
    }

    func apply(
        theme newTheme: PiboTheme,
        state newState: PiboActivityState,
        animationStateID newAnimationStateID: String? = nil,
        growth newGrowth: PiboGrowthStage,
        placement newPlacement: PiboCharacterPlacement,
        animated: Bool
    ) {
        let themeChanged = newTheme.id != theme.id
        let growthChanged = newGrowth != growth
        let stateChanged = newState != state
        let resolvedAnimationStateID = newAnimationStateID
            .flatMap { PiboAnimationStateMap.available.contains($0) ? $0 : nil }
            ?? PiboAnimationStateMap.ambientStateID(for: newState)
        let animationStateChanged = resolvedAnimationStateID != animationStateID
        if animationStateChanged, resolvedAnimationStateID == "boring" {
            boringElapsed = 0
        }
        theme = newTheme
        state = newState
        animationStateID = resolvedAnimationStateID
        growth = newGrowth
        placement = newPlacement

        if vector != nil {
            if animationStateChanged {
                vectorPlaybook?.setAmbient(resolvedAnimationStateID)
                showZzz(visible && newState == .sleeping)
            }
            // `pibo_context` swaps the state and its placement in the same
            // business update. Layout only after the hard cut so there is no
            // one-frame stay at the previous state's position or z layer.
            layoutVector()
            return
        }

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
        if usesVector, buildVector() { return }
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
        if vector != nil {
            showZzz(isVisible && state == .sleeping)
            return
        }
        overheadNode.isHidden = !isVisible || theme.resolvedHead(for: growth).overhead == nil
        showZzz(isVisible && state == .sleeping)
    }

    func applyShader(_ shader: SKShader?) {
        // 矢量角色不走 shader：材质 shader 是纯逐像素颜色变换，对 shape 树而言
        // 把同一套数学算在颜色上更好 —— 不需要离屏，也就不会赔掉抗锯齿。
        // 光照由 `setLighting(_:)` 从同一份 profile 喂进去。
        guard vector == nil else { return }
        bodySprite?.shader = shader
        headNode.shader = shader
    }

    /// 时段光照。与 `ForestMaterial.fsh` 同一套数学，只是算在颜色上。
    func setVectorLighting(_ lighting: PiboCharacterLighting) {
        vector?.setLighting(lighting)
    }

    #if DEBUG
    /// 让成果态改演完整连招而不是保持呼吸，用来并排比对这两者。
    var debugPlaysAchievementCombo = false

    /// 从头再放一次当前状态的登场与连招。
    ///
    /// 没有登场的状态走 `startAuthoredIntro` 的空分支，直接触发
    /// `onIntroFinished` → 连招时间轴归零，所以一个入口同时是「重播登场」和
    /// 「从 0 秒看连招」。
    func replayIntro() {
        vectorTransition?.startAuthoredIntro()
    }
    #endif

    func transition(
        to stateID: String,
        intent: PiboCoreAnimationAdapter.TransitionIntent
    ) {
        guard PiboAnimationStateMap.available.contains(stateID), stateID != animationStateID else { return }
        animationStateID = stateID
        if stateID == "boring" { boringElapsed = 0 }
        switch intent {
        case .hardCut:
            vectorPlaybook?.setAmbient(stateID)
        case .bounceCut:
            vectorPlaybook?.syncAmbientState(stateID)
            vectorTransition?.bounceCut(to: stateID)
        }
    }

    /// Plays a short interaction/achievement pose and then returns to the
    /// current ambient state. It never mutates the ambient state ID.
    func performEvent(stateID: String, hold: TimeInterval = 1.6) {
        guard PiboAnimationStateMap.available.contains(stateID) else { return }
        if let vectorPlaybook {
            vectorPlaybook.play([.init(stateID, hold: hold)])
        }
    }

    func hitRegion(at point: CGPoint, in scene: SKScene) -> PiboCharacterHitRegion {
        guard visible else { return .none }
        if let vector {
            // 命中几何直接来自正在显示的路径，所以看到的轮廓与可摸到的轮廓
            // 不可能漂移 —— 旧路径靠贴图像素采样，形变时两者会分家。
            let local = scene.convert(point, to: vector.rootNode)
            if let sprout = vector.sproutPath(),
               sprout.copy(strokingWithWidth: 24, lineCap: .round, lineJoin: .round, miterLimit: 10)
                   .contains(local) || sprout.contains(local) {
                return .hair
            }
            if let body = vector.bodyPath(), body.contains(local) { return .body }
            return .none
        }
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
            }
            if !cancelled { onSproutTouched() }
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
        if !cancelled { onSproutTouched() }
    }

    func playSproutTouch() {
        if headRig.isEnabled {
            headRig.addImpulse(0.42)
            return
        }
        headNode.removeAction(forKey: "sproutTouch")
        headNode.run(.sequence([
            .rotate(byAngle: 0.07, duration: 0.09),
            .rotate(byAngle: -0.12, duration: 0.14),
            .rotate(toAngle: 0, duration: 0.18),
        ]), withKey: "sproutTouch")
    }

    func playBodyTap() {
        if let vector {
            vector.rootNode.removeAction(forKey: "squash")
            vector.rootNode.run(.sequence([
                .scaleX(to: 1.10, y: 0.92, duration: 0.08),
                .scaleX(to: 0.96, y: 1.06, duration: 0.10),
                .scaleX(to: 1, y: 1, duration: 0.12),
            ]), withKey: "squash")
            return
        }
        bodyForReflection?.removeAction(forKey: "squash")
        bodyForReflection?.run(.sequence([
            .scaleX(to: 1.12, y: 0.9, duration: 0.08),
            .scaleX(to: 0.94, y: 1.08, duration: 0.10),
            .scaleX(to: 1, y: 1, duration: 0.12),
        ]), withKey: "squash")
    }

    func playContextualAction(_ action: PiboCoreAnimationAdapter.ContextualAction) {
        cancelContextualAction()
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let short = reduceMotion ? 0.01 : 0.12
        let medium = reduceMotion ? 0.01 : 0.20
        let actor = rootNode
        let sequence: SKAction
        switch action {
        case .checkConnection:
            sequence = .sequence([
                .rotate(byAngle: 0.08, duration: short),
                .rotate(byAngle: -0.16, duration: medium),
                .rotate(byAngle: 0.08, duration: short),
            ])
        case .letSleep:
            sequence = .sequence([
                .scaleX(to: 1.015, y: 0.985, duration: medium),
                .wait(forDuration: reduceMotion ? 0.01 : 0.32),
                .scaleX(to: 1, y: 1, duration: medium),
            ])
        case .morningGreeting:
            sequence = .sequence([
                .scaleX(to: 0.96, y: 1.08, duration: medium),
                .rotate(byAngle: 0.06, duration: short),
                .rotate(byAngle: -0.06, duration: short),
                .scaleX(to: 1, y: 1, duration: medium),
            ])
        case .checkIn:
            playBodyTap()
            return
        case .play:
            let hop = reduceMotion ? CGFloat(2) : max(10, bodyHeight * 0.08)
            let side = reduceMotion ? CGFloat(2) : max(12, bodyWidth * 0.12)
            sequence = .sequence([
                .group([
                    .moveBy(x: -side, y: hop, duration: medium),
                    .rotate(byAngle: 0.08, duration: medium),
                ]),
                .group([
                    .moveBy(x: side * 2, y: 0, duration: medium),
                    .rotate(byAngle: -0.16, duration: medium),
                ]),
                .group([
                    .moveBy(x: -side, y: -hop, duration: medium),
                    .rotate(byAngle: 0.08, duration: medium),
                ]),
            ])
        case .rest:
            let settle = reduceMotion ? CGFloat(1) : max(6, bodyHeight * 0.045)
            sequence = .sequence([
                .group([
                    .moveBy(x: 0, y: -settle, duration: medium),
                    .scaleX(to: 1.025, y: 0.94, duration: medium),
                ]),
                .wait(forDuration: reduceMotion ? 0.01 : 0.46),
                .group([
                    .moveBy(x: 0, y: settle, duration: medium),
                    .scaleX(to: 1, y: 1, duration: medium),
                ]),
            ])
        }
        actor.run(sequence, withKey: "contextualAction")
    }

    func cancelContextualAction() {
        rootNode.removeAction(forKey: "contextualAction")
        rootNode.zRotation = 0
        rootNode.xScale = 1
        rootNode.yScale = 1
        if vector == nil {
            layout()
        } else {
            rootNode.position = .zero
        }
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

    /// Accepts one coalesced causal presentation. Transitioning characters wait until the
    /// destination pose settles; an off-camera anchor is deliberately ignored.
    @discardableResult
    func playBoProgressFeedback(_ presentation: BoProgressPresentation) -> Bool {
        if pendingBoProgress.map({ presentation.milestone >= $0.milestone }) ?? true {
            pendingBoProgress = presentation
        }
        attemptBoProgressFeedback()
        return true
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
        // 矢量路径下 headNode 是隐藏的遗留节点，位置永远是 0；聚焦点要取自
        // 当前姿态的芽根，那是 `sproutAxis` 按状态混合出来的。
        let headWorld: CGPoint
        if let vector, let axis = vector.sproutAxis {
            let local = axis.root.applying(vector.designToNodeTransform)
            headWorld = CGPoint(
                x: rootNode.position.x + vector.rootNode.position.x + local.x,
                y: rootNode.position.y + vector.rootNode.position.y + local.y
            )
        } else {
            headWorld = CGPoint(
                x: rootNode.position.x + headNode.position.x,
                y: rootNode.position.y + headNode.position.y
            )
        }
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

    /// Turn-away is intentionally disabled (removed per product direction): the
    /// 不理睬 / 生气 / 被打扰 reactions and 拖毛 rejection no longer tilt, spin, or
    /// swap Pibo to a back-facing pose. Kept as a no-op so the existing call sites
    /// stay valid; restore the body below to bring the effect back.
    func playTurnAway() {}


    func playPluck() {
        headRig.addImpulse(CGFloat.random(in: -2.3 ... 2.3))
        headNode.run(.sequence([.rotate(byAngle: 0.2, duration: 0.08), .rotate(byAngle: -0.2, duration: 0.12)]))
    }

    func randomPrecipitationPoint() -> CGPoint? {
        if let vector {
            guard visible, let scene, let body = vector.bodyPath() else { return nil }
            // 沿身体轮廓的上缘取样：矢量路径直接给出轮廓，不必再去贴图里逐列扫
            // alpha 找顶点。
            let box = body.boundingBoxOfPath
            guard box.width > 0 else { return nil }
            let u = CGFloat.random(in: 0.08 ... 0.92)
            let x = box.minX + box.width * u
            // 半圆近似上缘，足够天气系统用。
            let arch = sin(u * .pi)
            let y = box.minY + box.height * (0.52 + 0.44 * arch)
            let presented = vector.rootPoint(forBodyPathPoint: CGPoint(x: x, y: y))
            return scene.convert(presented, from: vector.rootNode)
        }
        if surface.isEmpty { rebuildSurface() }
        guard visible, let local = surface.randomElement() else { return nil }
        return CGPoint(
            x: rootNode.position.x + local.x + CGFloat.random(in: -2...2),
            y: rootNode.position.y + local.y + CGFloat.random(in: -2...3)
        )
    }

    private var usesArt: Bool { theme.bodyImage != nil }

    // MARK: - 矢量角色

    private func buildVector() -> Bool {
        guard let data = PiboCharacterData.shared,
              let built = PiboVectorCharacter(
                  stateID: animationStateID,
                  data: data
              ) else { return false }
        vector = built
        rootNode.addChild(built.rootNode)

        let driver = PiboStateTransition(data: data, stateID: built.currentStateID)
        let animator = PiboIdleAnimator(data: data)
        // 连招在落定后从自己的 0 秒起播，而不是接着上一个状态的时钟跑。
        // 连招从登场结束后才起播；没有登场的状态，登场回调紧跟落定。
        driver.onIntroFinished = { [weak animator] in animator?.restartTimeline() }
        vectorTransition = driver
        vectorIdle = animator
        vectorPlaybook = PiboCharacterPlaybook(transition: driver, ambientStateID: built.currentStateID)
        layoutVector()
        showZzz(visible && state == .sleeping)
        return true
    }

    /// 站位严格复刻 `pibo_context` 的 300×300 整画板注册。不能按 body bounds
    /// 逐状态 fit：pigu / muscle / weak 等轮廓宽度不同，那会让切换时角色自己改
    /// 尺寸并漂移。特殊状态的遮挡层也属于该原型合同的一部分。
    private func layoutVector() {
        guard let vector, let scene else { return }
        let stateID = vectorTransition?.displayStateID ?? vector.currentStateID
        let mapper = ForestLayoutMapper(sceneSize: scene.size)
        let player = ForestSceneManifest.piboPlayerPlacement(
            stateID: stateID,
            boringElapsed: boringElapsed
        )
        let authored = player.artboardFrame
        vector.setScale(authored.width / 300 * mapper.scale)
        let center = mapper.point(CGPoint(x: authored.midX, y: authored.midY))
        vector.rootNode.position = CGPoint(
            x: center.x - rootNode.position.x,
            y: center.y - rootNode.position.y
        )
        rootNode.zPosition = player.zPosition
    }

    private func updateVector(
        time: TimeInterval,
        deltaTime: TimeInterval,
        wind: StageWind,
        reduceMotion: Bool
    ) {
        guard let vector, let transition = vectorTransition else { return }
        // The traverse belongs to the player that is actually visible. During
        // bounceCut the destination is selected before the 190 ms exit ends;
        // advancing from animationStateID made boring enter mid-crossing.
        if transition.displayStateID == "boring" {
            boringElapsed += max(0, deltaTime)
        }
        vectorPlaybook?.update(deltaTime: deltaTime)
        transition.update(deltaTime: deltaTime)
        vector.setTransition(
            from: transition.fromStateID,
            to: transition.toStateID,
            progress: transition.progress
        )
        vector.setSettleScale(transition.settleScale * transition.introScale)
        vector.setPresentationScale(
            x: transition.presentationScaleX,
            y: transition.presentationScaleY
        )
        vector.setGlow(colorHex: transition.introGlowColor, intensity: transition.introGlow)
        vector.rootNode.alpha = transition.visualAlpha
        layoutVector()

        // 先把上一帧的待机姿态与路径形变全部归位，再叠加这一帧 —— 待机原语因此
        // 永远从一份干净的基准出发，不需要自己缓存「静止形状」。
        vector.resetIdleTransforms()
        // 亮相是定格 pose：登场期间常规连招暂停。
        if !transition.suppressesIdle {
            // 成果姿势留在首页时只呼吸，不继续演连招 —— 连招属于成果 Modal。
            var holdIdle = vectorPlaybook?.isPlaying == true
                ? nil
                : PiboAnimationStateMap.holdIdle(for: transition.toStateID)
            #if DEBUG
            if debugPlaysAchievementCombo { holdIdle = nil }
            #endif
            vectorIdle?.apply(
                idle: holdIdle ?? PiboCharacterData.shared?.states[transition.toStateID]?.idle,
                stateID: transition.toStateID,
                character: vector,
                time: time,
                amplitude: transition.idleAmplitude
            )
        }
        updateVectorRig(time: time, deltaTime: deltaTime, wind: wind, reduceMotion: reduceMotion)
        if let view = scene?.view { vector.refreshReflectionSnapshotIfNeeded(in: view) }
    }

    /// 同一套六段骨骼阻尼弹簧，宿主换成矢量角色的芽。根梢方向随状态变化，
    /// 翻转时必须重挂 —— 网格的第 0 行钉的是根部。
    private func updateVectorRig(
        time: TimeInterval,
        deltaTime: TimeInterval,
        wind: StageWind,
        reduceMotion: Bool
    ) {
        guard let vector, let anchor = vector.sproutWarpAnchor else { return }
        if vectorRigInverted != anchor.axisInverted {
            vectorRigInverted = anchor.axisInverted
            headRig.attach(
                toSprout: vector.sproutNode,
                axisInverted: anchor.axisInverted,
                pivotFraction: anchor.pivotFraction
            )
        } else {
            headRig.setPivotFraction(anchor.pivotFraction)
        }
        headRig.update(time: time, deltaTime: deltaTime, wind: wind, reduceMotion: reduceMotion)
    }

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
                showZzz(state == .sleeping)
            }
            return
        }
        switch state {
        case .sleeping: setEyes(.closed); setBlush(0); showZzz(true); setBodyTint(0.97)
        case .waking: setEyes(.half); setBlush(0); showZzz(false); setBodyTint(1)
        case .energetic, .stable, .dataUnknown:
            setEyes(.open); setBlush(0); showZzz(false); setBodyTint(1)
        case .tired: setEyes(.half); setBlush(0); showZzz(false); setBodyTint(0.97)
        }
    }

    private func applyCanonicalState(animated: Bool) {
        guard let body = bodySprite else { return }
        body.removeAction(forKey: "canonicalState")
        headNode.removeAction(forKey: "canonicalState")
        headNode.removeAction(forKey: "headIdle")
        showZzz(state == .sleeping)
        let duration = animated ? 0.32 : 0
        switch state {
        case .sleeping:
            body.run(.group([.scaleX(to: 1.03, y: 0.96, duration: duration), .rotate(toAngle: -0.025, duration: duration)]), withKey: "canonicalState")
            runHeadReaction(.rotate(toAngle: -0.12, duration: duration))
        case .waking:
            body.run(.group([.scaleX(to: 1, y: 1, duration: duration), .rotate(toAngle: 0.025, duration: duration)]), withKey: "canonicalState")
            runHeadReaction(.rotate(toAngle: -0.04, duration: duration))
        case .energetic, .stable, .dataUnknown:
            body.run(.group([.scaleX(to: 1, y: 1, duration: duration), .rotate(toAngle: 0, duration: duration)]), withKey: "canonicalState")
            runHeadReaction(.rotate(toAngle: 0, duration: duration))
        case .tired:
            body.run(.group([.scaleX(to: 1.01, y: 0.98, duration: duration), .rotate(toAngle: 0.045, duration: duration)]), withKey: "canonicalState")
            runHeadReaction(.rotate(toAngle: 0.13, duration: duration))
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
        // The migrated sleep states already contain their authored Z / bubble
        // decorations and animate them inside the 300×300 state artboard. The
        // legacy label is positioned from the old procedural body's placement;
        // layering it over the vector state produces a duplicate at the former
        // ground location instead of beside the coconut nest.
        guard vector == nil, show, visible else { return }
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
            case .sleeping: center = -0.12
            case .waking: center = -0.04
            case .tired: center = 0.13
            case .energetic, .stable, .dataUnknown: center = 0
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
        if vector != nil {
            updateVector(time: time, deltaTime: deltaTime, wind: wind, reduceMotion: reduceMotion)
            updateBoProgressFeedback()
            return
        }
        headRig.update(
            time: time,
            deltaTime: deltaTime,
            wind: wind,
            reduceMotion: reduceMotion
        )
        followBodyDeformation()
        updateBoProgressFeedback()
    }

    private func updateBoProgressFeedback() {
        if let anchor = sproutAnchorInScene(), !boProgressHost.children.isEmpty {
            boProgressHost.position = anchor
        }
        attemptBoProgressFeedback()
    }

    private func attemptBoProgressFeedback() {
        guard let presentation = pendingBoProgress else { return }
        guard !isCloseupActive, vectorTransition?.isRunning != true else { return }
        pendingBoProgress = nil
        guard visible, let anchor = sproutAnchorInScene(), isVisibleInCamera(anchor) else {
            LPLog.bo.debug("progress feedback ignored — sprout anchor is not visible")
            return
        }
        boProgressHost.removeAllActions()
        boProgressHost.removeAllChildren()
        boProgressHost.position = anchor

        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let previous = CGFloat(min(1, max(0, presentation.previousProgress)))
        let current = CGFloat(min(1, max(0, presentation.currentProgress)))
        headRig.setGrowthProgress(previous)

        if !presentation.fact.isEmpty {
            buildBoProgressLabel(
                presentation.fact,
                y: 116,
                startDelay: reduceMotion ? 0 : 0.30,
                visibleDuration: reduceMotion ? 0.22 : 4.05
            )
        }
        if !reduceMotion {
            buildBoProgressParticles(
                color: SKColor(theme.scene.groundAccent),
                source: presentation.fact.isEmpty ? nil : CGPoint(x: 0, y: 104),
                startDelay: 1.10
            )
        }
        boProgressHost.run(.sequence([
            .wait(forDuration: reduceMotion ? 0.08 : 2.40),
            .run { [weak self] in
                guard let self, self.state != .sleeping else { return }
                self.headRig.addImpulse(reduceMotion ? 0.22 : 0.55)
            },
            .wait(forDuration: reduceMotion ? 0.08 : 1.00),
            .run { [weak self] in
                guard let self else { return }
                self.headRig.animateGrowth(
                    from: previous,
                    to: current,
                    duration: reduceMotion ? 0.12 : 1.05
                )
                self.sproutGrowthProgress = current
            },
        ]), withKey: "boProgressCausality")
        buildBoProgressLabel(
            presentation.message,
            y: 42,
            startDelay: reduceMotion ? 0.24 : 4.60,
            visibleDuration: reduceMotion ? 0.18 : 0.40
        )
        boProgressHost.run(.sequence([
            .wait(forDuration: reduceMotion ? 0.42 : 5.20),
            .run { [weak self] in self?.boProgressHost.removeAllChildren() },
        ]), withKey: "boProgressLifetime")
        LPLog.bo.notice(
            "progress feedback played milestone=\(presentation.milestone.rawValue, privacy: .public)"
        )
    }

    private func sproutAnchorInScene() -> CGPoint? {
        guard let scene else { return nil }
        if let vector, let point = vector.presentedSproutRootPoint() {
            return scene.convert(point, from: vector.rootNode)
        }
        guard !headNode.isHidden else { return nil }
        return scene.convert(.zero, from: headNode)
    }

    private func isVisibleInCamera(_ point: CGPoint) -> Bool {
        guard let scene, let camera else { return false }
        let halfWidth = scene.size.width * camera.xScale / 2
        let halfHeight = scene.size.height * camera.yScale / 2
        let visibleRect = CGRect(
            x: camera.position.x - halfWidth,
            y: camera.position.y - halfHeight,
            width: halfWidth * 2,
            height: halfHeight * 2
        ).insetBy(dx: 18, dy: 28)
        return visibleRect.contains(point)
    }

    private func buildBoProgressParticles(
        color: SKColor,
        source: CGPoint? = nil,
        startDelay: TimeInterval = 0
    ) {
        for index in 0..<10 {
            let angle = CGFloat(index) / 10 * 2 * .pi + CGFloat.random(in: -0.18...0.18)
            let radius = CGFloat.random(in: 34...62)
            let particle = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.8...3.4))
            particle.fillColor = color
            particle.strokeColor = .white.withAlphaComponent(0.72)
            particle.lineWidth = 0.8
            particle.position = source.map {
                CGPoint(
                    x: $0.x + CGFloat(index - 5) * 6 + CGFloat.random(in: -3...3),
                    y: $0.y + CGFloat(abs(index - 5)) * 1.5
                )
            } ?? CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            particle.alpha = 0
            boProgressHost.addChild(particle)

            let delay = TimeInterval.random(in: 0...0.12)
            let arrive = SKAction.move(to: .zero, duration: 0.58)
            arrive.timingMode = .easeOut
            particle.run(.sequence([
                .wait(forDuration: startDelay + delay),
                .group([.fadeIn(withDuration: 0.12), arrive]),
                .group([.scale(to: 0.2, duration: 0.16), .fadeOut(withDuration: 0.16)]),
                .removeFromParent(),
            ]))
        }

        let ring = SKShapeNode(circleOfRadius: 7)
        ring.strokeColor = color
        ring.lineWidth = 2
        ring.fillColor = .clear
        ring.alpha = 0
        boProgressHost.addChild(ring)
        ring.run(.sequence([
            .wait(forDuration: 0.56),
            .group([.fadeIn(withDuration: 0.08), .scale(to: 1.8, duration: 0.22)]),
            .fadeOut(withDuration: 0.18),
            .removeFromParent(),
        ]))
    }

    private func buildBoProgressLabel(
        _ text: String,
        y: CGFloat,
        startDelay: TimeInterval,
        visibleDuration: TimeInterval
    ) {
        let container = SKNode()
        container.position = CGPoint(x: 0, y: y)
        container.alpha = 0

        let label = SKLabelNode(fontNamed: "PingFangSC-Medium")
        label.text = text
        label.fontSize = 13
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        let background = SKShapeNode(
            rectOf: CGSize(width: max(132, label.frame.width + 22), height: 30),
            cornerRadius: 15
        )
        background.fillColor = SKColor(white: 0.12, alpha: 0.78)
        background.strokeColor = SKColor(white: 1, alpha: 0.22)
        background.lineWidth = 1
        container.addChild(background)
        container.addChild(label)
        boProgressHost.addChild(container)

        let rise = SKAction.moveBy(x: 0, y: 5, duration: 0.20)
        rise.timingMode = .easeOut
        container.run(.sequence([
            .wait(forDuration: startDelay),
            .group([.fadeIn(withDuration: 0.16), rise]),
            .wait(forDuration: visibleDuration),
            .group([.fadeOut(withDuration: 0.20), .moveBy(x: 0, y: 3, duration: 0.20)]),
            .removeFromParent(),
        ]))
    }

    /// Keep the head 毛 glued to the body while the body squash-stretches (拍一拍)
    /// or scales for a state change. The head is a *sibling* of the body under
    /// `rootNode`, so without this it floats in place while the body deforms — the
    /// 毛 visibly detaches from the head. The body scales about its own centre
    /// (which sits at `rootNode`'s origin), so re-mapping the head's rest offset
    /// through the body's live scale reproduces a rigid attachment at the body top.
    /// Runs every frame; at rest (scale 1) it resolves to the layout position.
    private func followBodyDeformation() {
        guard usesArt, !isCloseupActive,
              let body = bodySprite,
              let rest = placement?.head?.position else { return }
        headNode.position = CGPoint(x: rest.x * body.xScale, y: rest.y * body.yScale)
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

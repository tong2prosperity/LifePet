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
    /// Interaction transforms pivot around the authored character frame's
    /// lower support point (50% × 80% in top-left design coordinates), matching
    /// HarmonyOS. Keeping placement outside these nodes prevents a pat from
    /// pulling hammock poses away from the hammock.
    private let interactionPivotNode = SKNode()
    private let contextualActionNode = SKNode()
    private let contactFeedbackNode = SKNode()
    private let characterContentNode = SKNode()
    let overheadNode = SKSpriteNode()
    let effectsNode = SKNode()

    var onSproutTouched: () -> Void = {}
    /// Decision 048: the ledger's ripe fact. Only a ripe container can release.
    var hasRipeBo = false
    /// Commits one collection. Returns whether the ledger really collected.
    var onCollectBo: () -> Bool = { false }
    /// True from the committed release until its presentation ends, so the
    /// SwiftUI layer can keep the unified collection pose on screen.
    var onHarvestActiveChanged: (Bool) -> Void = { _ in }
    /// Short text beside the balance ("已收取 1 bo" / failure).
    var onHarvestHint: (String) -> Void = { _ in }
    /// Where collected energy lands (the balance chip), in scene space.
    var balanceTargetInScene: CGPoint?
    private var harvest = PiboBoHarvestTimeline()
    private let harvestSound = OrnamentUnlockSoundService()
    private let energyFlightNode: SKShapeNode = {
        let node = SKShapeNode(ellipseOf: CGSize(width: 15, height: 18))
        node.fillColor = SKColor(red: 0xD7 / 255, green: 0xF4 / 255, blue: 0xA3 / 255, alpha: 1)
        node.strokeColor = SKColor(red: 0xCD / 255, green: 0xEB / 255, blue: 0x98 / 255, alpha: 0.55)
        node.glowWidth = 5
        node.zPosition = 60
        node.alpha = 0
        return node
    }()
    private var energyFlightStart: CGPoint = .zero
    /// Seconds into the maturity motion, nil when it is not playing.
    private var boRipeElapsed: Double?
    private var boRipeFrom: CGFloat = 0
    var isHarvesting: Bool { harvest.isReleasing }
    /// Top of the current pose's bo container in scene space, reported only when
    /// the pose settles or moves ≥ 4 design units — never per frame, so pat
    /// squash, wind sway and growth cannot make the speech bubble wobble.
    var onSpeechAnchorChanged: (CGPoint?) -> Void = { _ in }
    private var speechAnchorStateID: String?
    private var speechAnchor: CGPoint?
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
    /// Persisted Core progress rendered as content inside the fixed `bo` shell.
    private var boFillProgress: CGFloat = 0
    private var headArtwork: PiboSVGArtwork?
    private var hairDragOrigin: CGPoint?
    private var surface: [CGPoint] = []
    private(set) var isCloseupActive = false

    /// Immediate, non-semantic acknowledgement of a finger resting on Pibo.
    /// No haptic, analytics, speech, or state transition is coupled to this.
    func beginContactFeedback() {
        contactFeedbackNode.removeAction(forKey: "contactFeedback")
        if UIAccessibility.isReduceMotionEnabled {
            let fade = SKAction.fadeAlpha(to: 0.90, duration: 0.06)
            fade.timingMode = .easeOut
            contactFeedbackNode.run(fade, withKey: "contactFeedback")
        } else {
            let press = SKAction.scaleX(to: 1.035, y: 0.97, duration: 0.06)
            press.timingMode = .easeOut
            contactFeedbackNode.run(press, withKey: "contactFeedback")
        }
    }

    func endContactFeedback() {
        contactFeedbackNode.removeAction(forKey: "contactFeedback")
        let scale = SKAction.scaleX(to: 1, y: 1, duration: 0.12)
        scale.timingMode = .easeOut
        let fade = SKAction.fadeAlpha(to: 1, duration: 0.12)
        fade.timingMode = .easeOut
        let restore = SKAction.group([scale, fade])
        contactFeedbackNode.run(restore, withKey: "contactFeedback")
    }

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
        effectsNode.addChild(energyFlightNode)
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
        installInteractionHierarchyIfNeeded()
        guard characterContentNode.children.isEmpty else { return }
        if usesVector, buildVector() { return }
        buildBody()
        rebuildHead()
        layout()
        applyState(animated: false)
        startIdleBob()
        startHeadIdle()
    }

    private func installInteractionHierarchyIfNeeded() {
        guard interactionPivotNode.parent == nil else { return }
        rootNode.addChild(interactionPivotNode)
        interactionPivotNode.addChild(contextualActionNode)
        contextualActionNode.addChild(contactFeedbackNode)
        contactFeedbackNode.addChild(characterContentNode)
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
                let local = scene.convert(point, to: characterContentNode)
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
                let local = scene.convert(point, to: characterContentNode)
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
        guard !harvest.isReleasing else { return }
        hairDragOrigin = point
        harvest.beginDrag()
        headNode.removeAction(forKey: "headIdle")
        headNode.removeAction(forKey: "hairSettle")
        headRig.beginInteraction()
    }

    func moveHairDrag(to point: CGPoint) {
        guard let origin = hairDragOrigin else { return }
        let dx = point.x - origin.x
        let up = max(0, point.y - origin.y)
        let result = harvest.drag(upward: up, ripe: hasRipeBo)
        if result.armed {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            harvestSound.playHarvest(.ready)
        }
        if result.shouldRelease {
            releaseBoEnergy()
            return
        }
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
        let travelled = hypot(point.x - origin.x, point.y - origin.y)
        if travelled < 8 { harvest.tap() } else { harvest.cancelDrag() }
        if headRig.isEnabled {
            // Below the release threshold the container springs back and nothing
            // is collected; the pull never detaches or spends anything.
            headRig.endInteraction(pulled: false)
            if !cancelled { onSproutTouched() }
            return
        }
        let pulled = !cancelled && travelled > 30
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

    /// Commits one collection. Also the VoiceOver path, which needs no drag.
    func releaseBoEnergy() {
        guard !harvest.isReleasing, hasRipeBo else { return }
        if hairDragOrigin != nil {
            hairDragOrigin = nil
            headRig.endInteraction(pulled: false)
        }
        guard onCollectBo() else {
            harvest.cancelDrag()
            onHarvestHint(AppLocalization.text("暂时没有收好，请再试一次"))
            return
        }
        cancelBoProgressFeedback()
        harvest.beginRelease()
        onHarvestActiveChanged(true)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        harvestSound.playHarvest(.release)
        onHarvestHint(AppLocalization.text("已收取 1 bo"))
        if let root = sproutAnchorInScene() {
            let lift = 95 * designUnitScale
            energyFlightStart = CGPoint(x: root.x, y: root.y + lift)
        }
    }

    /// Drops any in-flight collection presentation (theme swap, debug reset).
    func cancelHarvest() {
        let wasReleasing = harvest.isReleasing
        harvest.reset()
        headRig.stretch = 1
        vector?.expressionOverlay = .identity
        energyFlightNode.alpha = 0
        harvestSound.stop()
        if wasReleasing { onHarvestActiveChanged(false) }
    }

    private var designUnitScale: CGFloat {
        guard let scene else { return 1 }
        return ForestLayoutMapper(sceneSize: scene.size).scale
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
        contextualActionNode.removeAction(forKey: "squash")
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let first = eased(.scaleX(
            to: reduceMotion ? 1.02 : 1.12,
            y: reduceMotion ? 0.98 : 0.9,
            duration: 0.08
        ))
        let sequence: SKAction
        if reduceMotion {
            sequence = .sequence([first, eased(.scaleX(to: 1, y: 1, duration: 0.08))])
        } else {
            sequence = .sequence([
                first,
                eased(.scaleX(to: 0.94, y: 1.08, duration: 0.10)),
                eased(.scaleX(to: 1, y: 1, duration: 0.12)),
            ])
        }
        contextualActionNode.run(sequence, withKey: "squash")
    }

    func playContextualAction(_ action: PiboCoreAnimationAdapter.ContextualAction) {
        if action == .checkIn, [PiboAnimationResourceID.stable, PiboAnimationResourceID.stableThinking].contains(animationStateID),
           vector != nil, vectorTransition?.isRunning == false {
            vector?.restartExpressionPat()
            vectorIdle?.restartAuthoredPat()
            return
        }
        cancelContextualAction()
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let medium = reduceMotion ? 0.10 : 0.22
        let actor = contextualActionNode
        let sequence: SKAction
        switch action {
        case .checkConnection:
            // 2026-09-07: pat keeps its squash-and-rebound deformation only; no
            // extra sideways tilt or shift layered on top.
            playBodyTap()
            return
        case .letSleep:
            sequence = .sequence([
                eased(.scaleX(
                    to: reduceMotion ? 1.005 : 1.015,
                    y: reduceMotion ? 0.995 : 0.985,
                    duration: medium
                )),
                .wait(forDuration: reduceMotion ? 0.08 : 0.26),
                eased(.scaleX(to: 1, y: 1, duration: medium)),
            ])
        case .morningGreeting:
            sequence = .sequence([
                eased(.scaleX(
                    to: reduceMotion ? 0.99 : 0.96,
                    y: reduceMotion ? 1.02 : 1.08,
                    duration: medium
                )),
                eased(.scaleX(to: 1, y: 1, duration: medium)),
            ])
        case .checkIn:
            playBodyTap()
            return
        case .play:
            playBodyTap()
            return
        case .rest:
            let settle = designLength(1)
            sequence = .sequence([
                eased(.group([
                    .moveBy(x: 0, y: -settle, duration: medium),
                    .scaleX(
                        to: 1,
                        y: 1,
                        duration: medium
                    ),
                ])),
                .wait(forDuration: reduceMotion ? 0.08 : 0.32),
                eased(.group([
                    .moveBy(x: 0, y: settle, duration: medium),
                    .scaleX(to: 1, y: 1, duration: medium),
                ])),
            ])
        }
        actor.run(sequence, withKey: "contextualAction")
    }

    func cancelContextualAction() {
        vector?.cancelExpressionPat()
        vectorIdle?.cancelAuthoredPat()
        contextualActionNode.removeAction(forKey: "contextualAction")
        contextualActionNode.removeAction(forKey: "squash")
        contextualActionNode.position = .zero
        contextualActionNode.zRotation = 0
        contextualActionNode.xScale = 1
        contextualActionNode.yScale = 1
    }

    private func eased(_ action: SKAction) -> SKAction {
        action.timingMode = .easeInEaseOut
        return action
    }

    private func designLength(_ value: CGFloat) -> CGFloat {
        guard let scene else { return value }
        return value * ForestLayoutMapper(sceneSize: scene.size).scale
    }

    func playFoodObservation(onRight: Bool) {
        cancelFoodObservation()
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        if let vector {
            vector.playFoodObservation(onRight: onRight, reduceMotion: reduceMotion)
            return
        }
        guard !reduceMotion else { return }
        let angle: CGFloat = onRight ? -0.045 : 0.045
        rootNode.run(
            .sequence([
                .wait(forDuration: 0.32),
                .rotate(toAngle: angle, duration: 0.42, shortestUnitArc: true),
                .wait(forDuration: 4.18),
                .rotate(toAngle: 0, duration: 0.32, shortestUnitArc: true),
            ]),
            withKey: "foodObservation"
        )
    }

    func cancelFoodObservation() {
        vector?.cancelFoodObservation()
        rootNode.removeAction(forKey: "foodObservation")
        rootNode.zRotation = 0
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

    /// Invalidates queued and playing progress presentations and restores the
    /// real fill (a collection or the last spend makes them stale).
    func cancelBoProgressFeedback() {
        pendingBoProgress = nil
        boProgressHost.removeAllActions()
        boProgressHost.removeAllChildren()
        boRipeElapsed = nil
        vector?.boGlow = 0
        headRig.presentationTilt = 0
        vector?.setBoFillProgress(boFillProgress)
    }

    func setBoFillProgress(_ progress: CGFloat) {
        boFillProgress = PiboBoContainerProgress.normalized(progress)
        // The maturity motion owns the visible fill until it ends.
        guard boRipeElapsed == nil else { return }
        if let vector {
            vector.setBoFillProgress(boFillProgress)
            // The rig now bends the complete container; it no longer reveals the
            // silhouette segment-by-segment as energy arrives.
            headRig.setGrowthProgress(1)
        } else {
            headRig.setGrowthProgress(boFillProgress)
        }
    }

    func playSproutGrowth(from start: CGFloat, to target: CGFloat, duration: TimeInterval) {
        boFillProgress = PiboBoContainerProgress.normalized(target)
        if let vector {
            vector.animateBoFill(from: start, to: boFillProgress, duration: duration)
            headRig.setGrowthProgress(1)
        } else {
            headRig.animateGrowth(from: start, to: boFillProgress, duration: duration)
        }
        headRig.addImpulse(0.8 + (boFillProgress - start) * 2.4)
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
            self.boFillProgress = start
            self.rebuildHead()
            if let vector = self.vector {
                vector.setBoFillProgress(start)
                self.headRig.setGrowthProgress(1)
            } else {
                self.headRig.setGrowthProgress(start)
            }
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
        characterContentNode.addChild(built.rootNode)

        let driver = PiboStateTransition(data: data, stateID: built.currentStateID)
        let animator = PiboIdleAnimator(data: data)
        // 连招在落定后从自己的 0 秒起播，而不是接着上一个状态的时钟跑。
        // 连招从登场结束后才起播；没有登场的状态，登场回调紧跟落定。
        driver.onIntroFinished = { [weak animator] in animator?.restartTimeline() }
        vectorTransition = driver
        vectorIdle = animator
        vectorPlaybook = PiboCharacterPlaybook(transition: driver, ambientStateID: built.currentStateID)
        built.setBoFillProgress(boFillProgress)
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
        let pivotInScene = mapper.point(CGPoint(
            x: authored.midX,
            y: authored.minY + authored.height * 0.8
        ))
        setInteractionPivot(CGPoint(
            x: pivotInScene.x - rootNode.position.x,
            y: pivotInScene.y - rootNode.position.y
        ))
        rootNode.zPosition = player.zPosition
    }

    private func setInteractionPivot(_ pivot: CGPoint) {
        interactionPivotNode.position = pivot
        characterContentNode.position = CGPoint(x: -pivot.x, y: -pivot.y)
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
        let hasExpression = PiboExpressionLibrary.shared?.bindings.values.contains(transition.toStateID) == true
        vector.setTransition(
            from: hasExpression ? transition.toStateID : transition.fromStateID,
            to: transition.toStateID,
            progress: hasExpression ? 1 : transition.progress
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
        let expressionPlaying = vector.updateExpression(stateID: transition.toStateID,
            deltaTime: deltaTime, reduceMotion: reduceMotion)
        if !transition.suppressesIdle && !expressionPlaying {
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
        vector.updateBoFill(deltaTime: deltaTime, reduceMotion: reduceMotion)
        vector.syncBoContainerPresentation()
        reportSpeechAnchorIfNeeded(transition: transition)
        updateVectorRig(time: time, deltaTime: deltaTime, wind: wind, reduceMotion: reduceMotion)
        if let view = scene?.view { vector.refreshReflectionSnapshotIfNeeded(in: view) }
    }

    private func reportSpeechAnchorIfNeeded(transition: PiboStateTransition) {
        guard let vector, let scene, !transition.isRunning else { return }
        let stateID = transition.displayStateID
        guard let path = vector.sproutPath() else { return }
        let box = path.boundingBoxOfPath
        guard !box.isNull else { return }
        // Body transform is Y-up in node space; the container's top is maxY.
        let local = vector.rootPoint(forBodyPathPoint: CGPoint(x: box.midX, y: box.maxY))
        let point = scene.convert(local, from: vector.rootNode)
        let threshold = 4 * designUnitScale
        if stateID == speechAnchorStateID, let previous = speechAnchor,
           hypot(point.x - previous.x, point.y - previous.y) < threshold { return }
        speechAnchorStateID = stateID
        speechAnchor = point
        onSpeechAnchorChanged(point)
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
        characterContentNode.removeAllChildren()
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
            characterContentNode.addChild(body)
            headNode.zPosition = 12
            characterContentNode.addChild(headNode)
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
            characterContentNode.addChild(foot)
        }
        characterContentNode.addChild(shadow)
        characterContentNode.addChild(body)
        buildFace()
        characterContentNode.addChild(blush)
        characterContentNode.addChild(leftEye)
        characterContentNode.addChild(rightEye)
        headNode.zPosition = 12
        characterContentNode.addChild(headNode)
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
            headRig.setGrowthProgress(boFillProgress)
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
        setInteractionPivot(CGPoint(x: 0, y: -placement.body.size.height * 0.3))
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
            composePresentation(deltaTime: deltaTime, reduceMotion: reduceMotion)
            updateVector(time: time, deltaTime: deltaTime, wind: wind, reduceMotion: reduceMotion)
            updateBoProgressFeedback()
            return
        }
        composePresentation(deltaTime: deltaTime, reduceMotion: reduceMotion)
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
        guard !isCloseupActive, vectorTransition?.isRunning != true,
              !harvest.isReleasing, boRipeElapsed == nil else { return }
        pendingBoProgress = nil
        guard visible, let anchor = sproutAnchorInScene(), isVisibleInCamera(anchor) else {
            LPLog.bo.debug("progress feedback ignored — sprout anchor is not visible")
            return
        }
        boProgressHost.removeAllActions()
        boProgressHost.removeAllChildren()
        boProgressHost.position = anchor

        // Only a bo that actually ripened now (re-checked against the ledger at
        // play time, not just when queued) earns the reviewed maturity motion.
        // Fractional milestones — and extra energy flowing into the reserve
        // behind a bo that is already ripe — get the light growth hint.
        if hasRipeBo, presentation.mature, !presentation.previousMature {
            playBoRipe(presentation)
        } else {
            playBoGrowthHint(presentation)
        }
    }

    /// Decision 2026-09-16: the container fills, one short halo and eight motes
    /// at the root, and a single line naming what happened.
    private func playBoGrowthHint(_ presentation: BoProgressPresentation) {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let previous = CGFloat(min(1, max(0, presentation.previousProgress)))
        let current = CGFloat(min(1, max(0, presentation.currentProgress)))
        // A ripe bo already fills the container; never draw it smaller.
        if !hasRipeBo {
            if let vector {
                vector.setBoFillProgress(previous)
                vector.animateBoFill(from: previous, to: current, duration: reduceMotion ? 0.15 : 0.9)
                headRig.setGrowthProgress(1)
            } else {
                headRig.animateGrowth(from: previous, to: current, duration: reduceMotion ? 0.15 : 0.9)
            }
            boFillProgress = current
        }
        if !reduceMotion {
            let ring = SKShapeNode(circleOfRadius: 7)
            ring.strokeColor = SKColor(theme.scene.groundAccent)
            ring.lineWidth = 2
            ring.fillColor = .clear
            ring.alpha = 0
            ring.setScale(0.6)
            boProgressHost.addChild(ring)
            ring.run(.sequence([
                .group([.fadeAlpha(to: 0.85, duration: 0.18), .scale(to: 1.2, duration: 0.18)]),
                .group([.fadeOut(withDuration: 0.42), .scale(to: 1.7, duration: 0.42)]),
                .removeFromParent(),
            ]))
            if let anchor = sproutAnchorInScene() { emitSparkles(at: anchor, count: 8) }
        }
        buildBoProgressLabel(
            presentation.message,
            y: 108,
            startDelay: 0,
            visibleDuration: reduceMotion ? 1.16 : 1.96
        )
        LPLog.bo.notice(
            "growth hint played milestone=\(presentation.milestone.rawValue, privacy: .public)"
        )
    }

    /// The reviewed 6.8 s maturity motion. The frame clock in `update` drives
    /// fill, halo and pose; pausing the scene pauses it with no catch-up.
    private func playBoRipe(_ presentation: BoProgressPresentation) {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        boRipeFrom = CGFloat(min(1, max(0, presentation.previousProgress)))
        boRipeElapsed = 0
        vector?.setBoFillProgress(boRipeFrom)
        if !presentation.fact.isEmpty {
            buildBoProgressLabel(
                presentation.fact,
                y: 116,
                startDelay: reduceMotion ? 0 : 0.30,
                visibleDuration: reduceMotion ? 0.22 : 3.6
            )
        }
        buildBoProgressLabel(
            presentation.message,
            y: 108,
            startDelay: reduceMotion ? 0.12 : 2.7,
            visibleDuration: reduceMotion ? 0.2 : 3.4
        )
        LPLog.bo.notice("maturity motion started")
    }

    #if DEBUG
    /// Presentation-only replay from 90%: never reads or writes the ledger and
    /// restores the real fill when it ends.
    func debugPlayBoRipePreview() {
        cancelBoProgressFeedback()
        playBoRipe(BoProgressPresentation(
            milestone: .minted,
            message: AppLocalization.text("DEBUG · bo 成熟预览"),
            fact: "",
            previousProgress: 0.9,
            currentProgress: 1,
            previousMature: false,
            mature: true
        ))
    }

    func debugPlayBoGrowthHint() {
        cancelBoProgressFeedback()
        let real = boFillProgress
        let ripe = hasRipeBo
        playBoGrowthHint(BoProgressPresentation(
            milestone: .nearMint,
            message: AppLocalization.text("bo 快形成了"),
            fact: "",
            previousProgress: 0.62,
            currentProgress: 0.9,
            previousMature: false,
            mature: false
        ))
        boProgressHost.run(.sequence([
            .wait(forDuration: 2.4),
            .run { [weak self] in
                guard let self, !ripe else { return }
                self.boFillProgress = real
                self.vector?.setBoFillProgress(real)
            },
        ]), withKey: "debugGrowthHintRestore")
    }
    #endif

    private func finishBoRipe() {
        boRipeElapsed = nil
        vector?.boGlow = 0
        headRig.presentationTilt = 0
        boFillProgress = hasRipeBo ? 1 : boFillProgress
        vector?.setBoFillProgress(boFillProgress)
        attemptBoProgressFeedback()
    }

    /// One writer for everything layered on top of the authored expression:
    /// the pull-to-collect pose and the maturity motion.
    private func composePresentation(deltaTime: TimeInterval, reduceMotion: Bool) {
        let events = harvest.advance(deltaTime: deltaTime, reduceMotion: reduceMotion)
        var overlay = PiboVectorCharacter.ExpressionOverlay.identity

        if var elapsed = boRipeElapsed {
            elapsed += max(0, min(deltaTime, 0.05))
            boRipeElapsed = elapsed
            let pose = PiboBoRipeMotion.pose(
                seconds: elapsed,
                participation: PiboBoRipeMotion.participation(stateID: animationStateID),
                reduced: reduceMotion
            )
            vector?.setBoFillProgress(boRipeFrom + (1 - boRipeFrom) * pose.fill)
            vector?.boGlow = pose.glow
            headRig.presentationTilt = pose.sprout * .pi / 180
            overlay.bodyScale = CGSize(width: 1 / pose.bodyScaleY, height: pose.bodyScaleY)
            overlay.bodyPivotY = 282
            overlay.faceOffset = CGPoint(x: 0, y: pose.faceY)
            overlay.eyeScale = CGSize(width: 1, height: pose.eye)
            overlay.leftHandRaiseDegrees = -pose.arm
            if elapsed >= (reduceMotion ? PiboBoRipeMotion.reducedDuration : PiboBoRipeMotion.duration) {
                finishBoRipe()
                overlay = .identity
            }
        }

        if boRipeElapsed == nil {
            headRig.presentationTilt = (vector?.energeticSproutTilt ?? 0) * .pi / 180
        }
        let pull = reduceMotion ? 0 : harvest.pull
        headRig.stretch = 1 + 1.12 * pull
        if pull > 0 || harvest.gaze > 0 || harvest.blink < 1 {
            overlay.bodyScale = CGSize(
                width: overlay.bodyScale.width * (1 - 0.018 * pull),
                height: overlay.bodyScale.height * (1 + 0.025 * pull)
            )
            overlay.bodyPivotY = 280
            overlay.faceOffset = CGPoint(
                x: overlay.faceOffset.x + harvest.gaze * -3,
                y: overlay.faceOffset.y - 4 * max(pull, harvest.gaze)
            )
            overlay.eyeScale = CGSize(
                width: overlay.eyeScale.width * (1 + pull * 0.12),
                height: overlay.eyeScale.height * harvest.blink * (1 + pull * 0.12)
            )
            overlay.handSwingDegrees = pull * 18
        }
        vector?.expressionOverlay = overlay

        if let progress = harvest.flightProgress, let end = balanceTargetInScene {
            energyFlightNode.position = PiboBoHarvestTimeline.flightPoint(
                start: energyFlightStart, end: end, progress: progress
            )
            energyFlightNode.alpha = harvest.flightOpacity
        } else {
            energyFlightNode.alpha = 0
        }
        for event in events {
            switch event {
            case .received:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                harvestSound.playHarvest(.receive)
            case .finished:
                onHarvestActiveChanged(false)
            }
        }
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

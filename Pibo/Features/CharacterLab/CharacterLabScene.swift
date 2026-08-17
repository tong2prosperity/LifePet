#if DEBUG
import CoreGraphics
import SpriteKit
import UIKit

/// Character Lab —— 角色运行时的验证台。
///
/// 阶段 0 用它定了决策门 G0（结论见 `docs/character-animation-port.md`）；
/// 之后它是 `PiboVectorCharacter` + `PiboStateTransition` 的独立验证环境：
/// 不受森林场景的光照 / 倒影 / 天气干扰，能把角色本身的问题单独暴露出来。
final class CharacterLabScene: SKScene {
    var zoom: CGFloat = 1 { didSet { character?.setScale(baseScale * zoom) } }
    /// Pixel-comparison mode: preserve the authored 300×300 registration at
    /// 1:1 and center it on Figma's neutral preview gray.
    var artboardMode = false {
        didSet {
            backgroundColor = artboardMode
                ? SKColor(white: 192 / 255, alpha: 1)
                : SKColor(white: 0.94, alpha: 1)
            layoutCharacter()
        }
    }
    /// 关掉就完全不驱动芽的 warp。开着时走真实的六段骨骼阻尼弹簧 rig。
    var warpProbe = true
    var autoCycle = false
    var idleEnabled = true
    /// 把倒影代理的快照直接显示出来，用来确认 render-to-texture 抓对了。
    var showReflectionProxy = false

    private(set) var stateIDs: [String] = []
    private(set) var currentStateID = PiboAnimationResourceID.stable

    private var data: PiboCharacterData?
    private var character: PiboVectorCharacter?
    private var transition: PiboStateTransition?
    private var idle: PiboIdleAnimator?
    private var playbook: PiboCharacterPlaybook?
    private let sproutRig = PiboHeadRigDeformer()
    private var rigAttachedInverted: Bool?
    private let groundLine = SKShapeNode()
    private var lastUpdate: TimeInterval = 0
    private var cycleElapsed: TimeInterval = 0

    /// 300 设计单位映射到多少点。首页上 Pibo 大约这个量级。
    private let baseScale: CGFloat = 260.0 / 300.0

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(white: 0.94, alpha: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func didMove(to view: SKView) {
        guard character == nil, let data = PiboCharacterData.shared else { return }
        self.data = data
        // 固定顺序，让自动巡演与分段选择器的下标稳定。
        let preferred = [
            PiboAnimationResourceID.stable, "weak",
            PiboAnimationResourceID.workoutCelebrate,
            PiboAnimationResourceID.activityMilestoneCelebrate,
            PiboAnimationResourceID.tired, "angry", "dive", "boring", "coolhide",
            PiboAnimationResourceID.sleepingGroundA,
            PiboAnimationResourceID.wakingGroundRecovering,
            PiboAnimationResourceID.sleepingHammockA,
            PiboAnimationResourceID.sleepingHammockB,
            PiboAnimationResourceID.wakingHammock,
        ]
        stateIDs = preferred.filter { data.states[$0] != nil }

        let built = PiboVectorCharacter(stateID: currentStateID, data: data)
        built?.setScale(baseScale * zoom)
        if let built {
            addChild(built.rootNode)
        }
        character = built
        let driver = PiboStateTransition(data: data, stateID: currentStateID)
        let animator = PiboIdleAnimator(data: data)
        // 连招在落定后从自己的 0 秒起播，而不是接着上一个状态的时钟跑。
        // 连招从登场结束后才起播；没有登场的状态，登场回调紧跟落定。
        driver.onIntroFinished = { [weak animator] in animator?.restartTimeline() }
        transition = driver
        idle = animator
        playbook = PiboCharacterPlaybook(transition: driver, ambientStateID: currentStateID)
        layoutCharacter()
    }

    /// 「运动完成 → 秀肌肉 → 娇羞 → 回常驻态」，产品要的那条链路。
    func playWorkoutCelebration() {
        playbook?.play([
            .init(PiboAnimationResourceID.activityMilestoneCelebrate, hold: 2.0),
            .init(PiboAnimationResourceID.workoutCelebrate, hold: 2.0),
        ])
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutCharacter()
    }

    /// 用森林场景里已经调好的落脚点定位，而不是简单地居中 —— 这样 Lab 里看到的
    /// 站位就是首页的站位。
    private func layoutCharacter() {
        guard let character else { return }
        if artboardMode {
            character.setScale(1)
            character.rootNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
            groundLine.removeFromParent()
            return
        }
        let mapper = ForestLayoutMapper(sceneSize: size)
        let foot = mapper.point(ForestSceneManifest.piboFootPoint)
        character.fit(bodyWidth: 181.1602 * mapper.scale, footPoint: foot)

        groundLine.removeFromParent()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: foot.y))
        path.addLine(to: CGPoint(x: size.width, y: foot.y))
        groundLine.path = path
        groundLine.strokeColor = SKColor(red: 1, green: 0.18, blue: 0.33, alpha: 0.55)
        groundLine.lineWidth = 1
        groundLine.zPosition = 500
        addChild(groundLine)
    }

    func request(stateID: String) {
        guard stateIDs.contains(stateID) else { return }
        currentStateID = stateID
        // 走 playbook 的 ambient 通道：表演进行中只记下要回到哪，不打断表演。
        playbook?.setAmbient(stateID)
    }

    override func update(_ currentTime: TimeInterval) {
        let delta = lastUpdate > 0 ? currentTime - lastUpdate : 0
        lastUpdate = currentTime

        if autoCycle {
            cycleElapsed += delta
            if cycleElapsed > 1.8 {
                cycleElapsed = 0
                let next = stateIDs.firstIndex(of: currentStateID).map { ($0 + 1) % stateIDs.count } ?? 0
                request(stateID: stateIDs[next])
            }
        }

        guard let transition, let character else { return }
        playbook?.update(deltaTime: delta)
        transition.update(deltaTime: delta)
        character.setTransition(
            from: transition.fromStateID,
            to: transition.toStateID,
            progress: transition.progress
        )
        character.setSettleScale(transition.settleScale * transition.introScale)
        character.setGlow(colorHex: transition.introGlowColor, intensity: transition.introGlow)
        layoutCharacter()

        // 顺序是有讲究的：先把上一帧的待机姿态与形变全部归位（路径也还原成
        // rebuild 写下的基准形状），再叠加这一帧的待机。这样待机原语永远从一份
        // 干净的基准出发，不需要自己缓存「静止形状」—— Web 引擎那个「变形尾段
        // 启动的原语把中间帧缓存成基准、角色永久走形」的坑在这个结构下不成立。
        character.resetIdleTransforms()
        if idleEnabled, !transition.suppressesIdle {
            idle?.apply(
                idle: data?.states[transition.toStateID]?.idle,
                stateID: transition.toStateID,
                character: character,
                time: currentTime,
                amplitude: transition.idleAmplitude
            )
        }
        applyRig(time: currentTime, delta: delta, character: character)

        if let view {
            character.refreshReflectionSnapshotIfNeeded(in: view)
        }
        character.reflectionSource.isHidden = !showReflectionProxy
        if showReflectionProxy {
            character.reflectionSource.position.y = -size.height * 0.28
            character.reflectionSource.zPosition = 100
        }
    }

    /// 接真实的六段骨骼阻尼弹簧 rig（首页拖毛 / 拔毛 / 风吹用的同一套），
    /// 目标从贴图换成矢量角色的芽宿主。根梢方向随状态变化，翻转时要重挂。
    private func applyRig(time: TimeInterval, delta: TimeInterval, character: PiboVectorCharacter) {
        guard warpProbe else {
            if character.sproutNode.warpGeometry != nil { character.sproutNode.warpGeometry = nil }
            rigAttachedInverted = nil
            return
        }
        guard let anchor = character.sproutWarpAnchor else { return }
        if rigAttachedInverted != anchor.axisInverted {
            rigAttachedInverted = anchor.axisInverted
            sproutRig.attach(
                toSprout: character.sproutNode,
                axisInverted: anchor.axisInverted,
                pivotFraction: anchor.pivotFraction
            )
        } else {
            sproutRig.setPivotFraction(anchor.pivotFraction)
        }
        sproutRig.update(
            time: time,
            deltaTime: delta,
            wind: StageWind(direction: CGVector(dx: 1, dy: 0), strength: 0.55, gustiness: 0.7),
            reduceMotion: false
        )
    }
}
#endif

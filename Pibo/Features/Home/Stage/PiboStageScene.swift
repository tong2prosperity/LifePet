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
// a drag on the head sprout bends it and fires `onSproutTouched` on release —
// the SwiftUI layer may open the next common-item investment when `bo` is ripe.
// No camera pan / 横向逛场景 — the stage is a single fixed portrait world.
//
// Node tree (z back→front): backdrop(sky → ground) → 场景 icons → pibo(shadow,
// body, eyes, blush, head 毛) → overhead 黑洞 → fx (Zzz / sparkles / seeds). A
// `SKCameraNode` frames the scene; the 发芽 close-up zooms it onto the head.

/// Phases of the 发芽 close-up (Figma《识别到用户的活动》74:6102), reported back
/// so the SwiftUI overlay can swap its caption in sync.
enum SproutCloseupPhase {
    case shaking    // 毛抖动 — a newly synced workout record
    case sprouted   // 长出叶片 — "Pibo...发芽了啵！"
    case finished   // 缩回主页面 — show the workout-sync result pop
}

final class PiboStageScene: SKScene {

    // — Inputs (set by the SwiftUI wrapper) —
    private(set) var theme: PiboTheme = PiboThemeCatalog.defaultTheme
    private(set) var activityState: PiboActivityState = .dataUnknown
    private(set) var animationStateID: String?
    private(set) var growth: PiboGrowthStage = .mystery
    private(set) var stageEnvironment: PiboStageEnvironment = .daylight
    /// Fired on a tap that lands on Pibo's body (拍一拍).
    var onPat: (() -> Void)?
    /// Fired after a tap or drag on the sprout settles. The gesture never
    /// detaches artwork; a ripe `bo` remains visible until directly invested.
    var onSproutTouched: (() -> Void)? {
        didSet { configureCharacterCallbacks() }
    }
    /// Direct manipulation asks the SwiftUI bridge for the display's maximum
    /// cadence until the touch ends or is cancelled.
    var onDirectManipulationChanged: ((Bool) -> Void)?
    /// Fired when a tap lights one of an ornament's lamps (铃兰灯的一盏铃铛).
    /// The scene only reports it — 亮多久、什么时候熄 由 `OrnamentLightStore` 决定。
    var onOrnamentLightTapped: ((PiboOrnament.ID, Int) -> Void)?
    /// Fired when a forest common item is itself an interaction entry.
    var onOrnamentTapped: ((PiboOrnament.ID) -> Void)?

    // — Nodes —
    private let backdrop = SKNode()
    private let themeForegroundLayer = SKNode()
    private let themeAtmosphereLayer = SKNode()
    private let character = PiboCharacterRenderer()
    private let rainBack = SKNode()      // 雨幕(Pibo 之后 — 景深层)
    private let rainFront = SKNode()     // 水花 + 滴在 Pibo(Pibo 之前)
    private let cam = SKCameraNode()
    private var lastUpdateTime: TimeInterval = 0
    private var lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var tuning: StageRenderTuning = .standard
    private var themeRenderer: (any PiboThemeRenderer)?
    /// 用 `bo` 换来的物件。存在 scene 上而不是只转发给渲染器，是因为主题切换和
    /// 重建之后要能重新交代一遍。
    private var unlockedOrnaments: Set<PiboOrnament.ID> = []
    private var presentedOrnaments: Set<PiboOrnament.ID> = []
    /// 同上：物件身上已点亮的灯，重建之后也要重新交代。
    private var litOrnamentLights: [PiboOrnament.ID: Set<Int>] = [:]
    private lazy var weatherController = PiboWeatherEffectController(
        backLayer: rainBack,
        frontLayer: rainFront
    )

    private var built = false

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
        cancelActiveTouches()
        themeRenderer?.layout(sceneSize: size)
        layoutAll()
        themeRenderer?.apply(environment: stageEnvironment)
        themeRenderer?.apply(renderPolicy: themeRenderPolicy)
        themeRenderer?.apply(
            presentedOrnaments: presentedOrnaments,
            unlockedOrnaments: unlockedOrnaments
        )
        themeRenderer?.apply(litOrnamentLights: litOrnamentLights)
        if stageEnvironment.rainIntensity > 0 { applyWeather() }
    }

    override func update(_ currentTime: TimeInterval) {
        // Belt-and-suspenders: if the scene wasn't built by didMove/didChangeSize
        // (SwiftUI SpriteView size timing), build as soon as a valid size lands.
        if !built, size.width > 1, size.height > 1 { buildIfNeeded() }
        guard built else { return }
        let delta = lastUpdateTime > 0 ? min(currentTime - lastUpdateTime, 1.0 / 15.0) : 0
        lastUpdateTime = currentTime
        themeRenderer?.update(
            time: currentTime,
            deltaTime: delta,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )
        var characterWind = themeRenderer?.wind ?? StageWind(
            direction: CGVector(dx: -0.9, dy: -0.08),
            strength: 0.3,
            gustiness: 0.2
        )
        characterWind.strength *= CGFloat(tuning.ambientMotionScale)
        character.update(
            time: currentTime,
            deltaTime: delta,
            wind: characterWind,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )
    }

    override func didEvaluateActions() {
        guard built else { return }
        themeRenderer?.didEvaluateActions()
    }

    // MARK: Public API (called from the SwiftUI wrapper)

    func apply(
        theme newTheme: PiboTheme,
        state newState: PiboActivityState,
        animationStateID newAnimationStateID: String? = nil,
        growth newGrowth: PiboGrowthStage
    ) {
        let themeChanged = newTheme.id != theme.id
        let growthChanged = newGrowth != growth
        let stateChanged = newState != activityState
        let animationStateChanged = newAnimationStateID != animationStateID
        if themeChanged, built { cancelActiveTouches() }
        theme = newTheme
        activityState = newState
        animationStateID = newAnimationStateID
        growth = newGrowth
        if stateChanged { character.cancelContextualAction() }
        if themeChanged { backgroundColor = SKColor(newTheme.scene.skyBottom) }
        guard built else { return }
        // A theme may switch between art and procedural Pibo, so rebuild the body
        // group (not just the backdrop/head) when the theme changes.
        if themeChanged {
            themeRenderer?.teardown()
            themeRenderer = PiboThemeCatalog.makeRenderer(for: newTheme)
            character.apply(
                theme: newTheme,
                state: newState,
                animationStateID: newAnimationStateID,
                growth: newGrowth,
                placement: characterPlacement,
                animated: false
            )
            installThemeRenderer()
            layoutAll()
            themeRenderer?.apply(environment: stageEnvironment)
            themeRenderer?.apply(renderPolicy: themeRenderPolicy)
            themeRenderer?.apply(
                presentedOrnaments: presentedOrnaments,
                unlockedOrnaments: unlockedOrnaments
            )
            themeRenderer?.apply(litOrnamentLights: litOrnamentLights)
            if stageEnvironment.rainIntensity > 0 { applyWeather() }
        } else if growthChanged {
            character.apply(
                theme: newTheme,
                state: newState,
                animationStateID: newAnimationStateID,
                growth: newGrowth,
                placement: characterPlacement,
                animated: false
            )
            layoutAll()
        }
        if stateChanged || animationStateChanged || themeChanged {
            character.apply(
                theme: newTheme,
                state: newState,
                animationStateID: newAnimationStateID,
                growth: newGrowth,
                placement: characterPlacement,
                animated: true
            )
        }
    }

    func setEnvironment(_ newEnvironment: PiboStageEnvironment) {
        guard newEnvironment != stageEnvironment else { return }
        let rainChanged = newEnvironment.rainIntensity != stageEnvironment.rainIntensity
        stageEnvironment = newEnvironment
        guard built else { return }
        themeRenderer?.apply(environment: newEnvironment)
        if rainChanged || newEnvironment.rainIntensity > 0 { applyWeather() }
    }

    func setOrnaments(
        presented: Set<PiboOrnament.ID>,
        unlocked: Set<PiboOrnament.ID>
    ) {
        guard presented != presentedOrnaments || unlocked != unlockedOrnaments else { return }
        presentedOrnaments = presented
        unlockedOrnaments = unlocked
        guard built else { return }
        themeRenderer?.apply(
            presentedOrnaments: presented,
            unlockedOrnaments: unlocked
        )
    }

    func setLitOrnamentLights(_ lights: [PiboOrnament.ID: Set<Int>]) {
        guard lights != litOrnamentLights else { return }
        litOrnamentLights = lights
        guard built else { return }
        themeRenderer?.apply(litOrnamentLights: lights)
    }

    func setOrnamentConstructionMode(enabled: Bool, selected: PiboOrnament.ID?) {
        guard built else { return }
        (themeRenderer as? ForestThemeRenderer)?.setOrnamentConstructionMode(
            enabled: enabled,
            selected: selected
        )
    }

    func setOrnamentPlacementPreview(_ id: PiboOrnament.ID?) {
        guard built else { return }
        (themeRenderer as? ForestThemeRenderer)?.setOrnamentPlacementPreview(id)
    }

    func prepareOrnamentReveal(_ id: PiboOrnament.ID) {
        guard built else { return }
        (themeRenderer as? ForestThemeRenderer)?.prepareOrnamentReveal(id)
    }

    func ornamentTargetFrame(_ id: PiboOrnament.ID) -> CGRect? {
        guard built,
              let sceneFrame = (themeRenderer as? ForestThemeRenderer)?.ornamentTargetFrame(id),
              let view else { return nil }

        // The unlock overlay measures its source in SwiftUI's global space.
        // Convert all four corners through SpriteKit so camera transforms,
        // aspect fill, safe areas, and the SKView's window origin are honored.
        let viewPoints = [
            CGPoint(x: sceneFrame.minX, y: sceneFrame.minY),
            CGPoint(x: sceneFrame.maxX, y: sceneFrame.minY),
            CGPoint(x: sceneFrame.minX, y: sceneFrame.maxY),
            CGPoint(x: sceneFrame.maxX, y: sceneFrame.maxY),
        ].map { convertPoint(toView: $0) }
        guard let first = viewPoints.first else { return nil }
        let viewFrame = viewPoints.dropFirst().reduce(
            CGRect(origin: first, size: .zero)
        ) { partial, point in
            partial.union(CGRect(origin: point, size: .zero))
        }
        return view.convert(viewFrame, to: nil)
    }

    func completeOrnamentReveal(_ id: PiboOrnament.ID) {
        guard built else { return }
        (themeRenderer as? ForestThemeRenderer)?.completeOrnamentReveal(id)
    }

    func cancelOrnamentPresentation() {
        guard built else { return }
        (themeRenderer as? ForestThemeRenderer)?.cancelOrnamentPresentation()
    }

    func transitionAnimation(
        to stateID: String,
        intent: PiboCoreAnimationAdapter.TransitionIntent
    ) {
        guard PiboAnimationStateMap.available.contains(stateID), stateID != animationStateID else { return }
        animationStateID = stateID
        guard built else { return }
        character.transition(to: stateID, intent: intent)
    }

    func performAnimationEvent(_ stateID: String) {
        guard built else { return }
        character.performEvent(stateID: stateID)
    }

    func setLowPowerMode(_ enabled: Bool) {
        guard lowPowerModeEnabled != enabled else { return }
        lowPowerModeEnabled = enabled
        themeRenderer?.apply(renderPolicy: themeRenderPolicy)
        if stageEnvironment.rainIntensity > 0 { applyWeather() }
    }

    func setTuning(_ newTuning: StageRenderTuning) {
        let sanitized = newTuning.sanitized
        guard sanitized != tuning else { return }
        let visibilityChanged = sanitized.piboVisible != tuning.piboVisible
        tuning = sanitized
        guard built else { return }
        applyTuning(visibilityChanged: visibilityChanged)
        themeRenderer?.apply(renderPolicy: themeRenderPolicy)
    }

    #if DEBUG
    /// WaterLab uses the production scene, texture, and shader. Keeping tuning
    /// here prevents the debug page from drifting into a second water renderer.
    func setWaterDebugTuning(
        speed: Double,
        rippleStrength: Double,
        highlightStrength: Double,
        reflectionIntensity: Double = 1,
        reflectionCompression: Double = 0.52,
        reflectionTipScale: Double = 0.72,
        showMask: Bool
    ) {
        (themeRenderer as? WaterDebugTunable)?.applyWaterDebugTuning(
            WaterDebugTuning(
                speed: speed,
                rippleStrength: rippleStrength,
                highlightStrength: highlightStrength,
                reflectionIntensity: reflectionIntensity,
                reflectionCompression: reflectionCompression,
                reflectionTipScale: reflectionTipScale,
                showMask: showMask
            )
        )
    }
    #endif

    /// 能量收集 — the head 毛 senses new energy: shake → grow → settle, with a
    /// little sparkle burst (spec §3.4). The small in-place animation, used when
    /// the head is already sprouted (the first collection plays the close-up).
    func playEnergyGain() {
        guard built else { return }
        character.playEnergyGain()
    }

    func playSproutTouch() {
        guard built else { return }
        character.playSproutTouch()
    }

    @discardableResult
    func playBoProgressFeedback(_ presentation: BoProgressPresentation) -> Bool {
        guard built else { return false }
        return character.playBoProgressFeedback(presentation)
    }

    func setSproutGrowthProgress(_ progress: Double) {
        character.setSproutGrowthProgress(CGFloat(progress))
    }

    func playSproutGrowth(from start: Double, to target: Double) {
        guard built else { return }
        character.playSproutGrowth(
            from: CGFloat(start),
            to: CGFloat(target),
            duration: UIAccessibility.isReduceMotionEnabled ? 0.01 : 1.35
        )
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
    func playSproutCloseup(
        growthFrom start: Double,
        growthTo target: Double,
        onPhase: @escaping (SproutCloseupPhase) -> Void
    ) {
        guard built, !character.isCloseupActive else { onPhase(.finished); return }
        cancelThemeInteraction()
        character.playSproutCloseup(
            growthFrom: CGFloat(start),
            growthTo: CGFloat(target),
            onPhase: onPhase
        )
    }

    /// 拍一拍 不理睬 — Pibo 扭过头背对用户 (Figma 76:7115): hop, swap the body to
    /// the turned-away art, hold, turn back. Procedural themes just swivel.
    #if DEBUG
    func replayAnimationIntro() {
        guard built else { return }
        character.replayIntro()
    }

    func setPlaysAchievementCombo(_ enabled: Bool) {
        character.debugPlaysAchievementCombo = enabled
    }
    #endif

    func playTurnAway() {
        guard built else { return }
        character.playTurnAway()
    }

    func playContextualAction(_ action: PiboCoreAnimationAdapter.ContextualAction) {
        guard built else { return }
        character.playContextualAction(action)
    }

    func cancelContextualAction() {
        guard built else { return }
        character.cancelContextualAction()
    }

    /// 拔毛 — the sprout takes an impulse as the bo is taken off it.
    func playPluck() {
        guard built else { return }
        character.playPluck()
    }

    // MARK: Touch → 拍一拍 (body) / 拖毛 (hair) / 拨开树叶

    // — 拖毛 drag state —
    private var hairTouch: UITouch?
    // — tap candidate (non-毛) — a began→ended on roughly the same point is a tap
    // that routes to 拍一拍; a small movement tolerance absorbs jitter.
    private var tapTouch: UITouch?
    private var tapOrigin: CGPoint = .zero
    /// Beyond this move a touch is a drag/scroll, not a tap.
    private static let tapSlop: CGFloat = 16

    private var themeTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard built, !character.isCloseupActive, hairTouch == nil, themeTouch == nil, tapTouch == nil,
              let t = touches.first else { return }
        let p = t.location(in: self)
        let piboRegion = character.hitRegion(at: p, in: self)
        // 毛 is the smallest critical target, so it wins even when foreground
        // art overlaps it. Opaque foliage otherwise wins over the body.
        if piboRegion == .hair {
            hairTouch = t
            onDirectManipulationChanged?(true)
            character.beginHairDrag(at: p)
            return
        }
        if themeRenderer?.beginInteraction(at: p, timestamp: t.timestamp) == true {
            themeTouch = t
            onDirectManipulationChanged?(true)
            return
        }
        tapTouch = t
        tapOrigin = p
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = hairTouch, touches.contains(t) {
            let p = t.location(in: self)
            character.moveHairDrag(to: p)
            return
        }
        if let t = themeTouch, touches.contains(t) {
            let samples = event?.coalescedTouches(for: t) ?? [t]
            for sample in samples {
                themeRenderer?.moveInteraction(
                    to: sample.location(in: self),
                    timestamp: sample.timestamp
                )
            }
            return
        }
        // A tap candidate that wanders too far is no longer a tap.
        if let t = tapTouch, touches.contains(t) {
            let p = t.location(in: self)
            if hypot(p.x - tapOrigin.x, p.y - tapOrigin.y) > Self.tapSlop {
                tapTouch = nil
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = hairTouch, touches.contains(t) {
            let p = t.location(in: self)
            hairTouch = nil
            character.endHairDrag(at: p, cancelled: false)
            onDirectManipulationChanged?(false)
            return
        }
        if let t = themeTouch, touches.contains(t) {
            themeRenderer?.moveInteraction(to: t.location(in: self), timestamp: t.timestamp)
            themeRenderer?.endInteraction(
                at: t.location(in: self),
                timestamp: t.timestamp,
                cancelled: false
            )
            themeTouch = nil
            onDirectManipulationChanged?(false)
            return
        }
        guard let t = tapTouch, touches.contains(t) else { return }
        tapTouch = nil
        handleTap(at: t.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // System interruption (call banner, app switcher).
        if let t = hairTouch, touches.contains(t) {
            hairTouch = nil
            character.endHairDrag(at: t.location(in: self), cancelled: true)
            onDirectManipulationChanged?(false)
            return
        }
        if let t = themeTouch, touches.contains(t) {
            themeRenderer?.endInteraction(
                at: t.location(in: self),
                timestamp: t.timestamp,
                cancelled: true
            )
            themeTouch = nil
            onDirectManipulationChanged?(false)
            return
        }
        if let t = tapTouch, touches.contains(t) {
            tapTouch = nil
        }
    }

    private func cancelThemeInteraction() {
        guard let touch = themeTouch else { return }
        themeRenderer?.endInteraction(
            at: touch.location(in: self),
            timestamp: touch.timestamp,
            cancelled: true
        )
        themeTouch = nil
        onDirectManipulationChanged?(false)
    }

    private func cancelActiveTouches() {
        if let touch = hairTouch {
            hairTouch = nil
            character.endHairDrag(at: touch.location(in: self), cancelled: true)
            onDirectManipulationChanged?(false)
        }
        cancelThemeInteraction()
        if tapTouch != nil {
            tapTouch = nil
        }
    }

    // MARK: Tap routing

    /// Only Pibo itself handles stage touches. Feature entries live in SwiftUI.
    private func handleTap(at p: CGPoint) {
        if character.hitRegion(at: p, in: self) == .body {
            onPat?()
            return
        }
        // Pibo 先判、主题后判，顺序是有意的。铃兰灯的左侧铃铛落在 Pibo 身体范围
        // 里，而灯 z=18、Pibo z=20 —— 灯在后面。反过来判就会出现「点了看起来是
        // Pibo 肚子的地方、背后那盏看不见的灯亮了」。
        //
        // 也刻意**不**走 `beginInteraction`：那条路是给可拖拽的叶子用的，会在
        // `touchesBegan` 抢在 Pibo 之前，还会顺手把刷新率拉满 —— 对一次点击是白给的。
        switch themeRenderer?.handleTap(at: p) {
        case .ornament(let id):
            onOrnamentTapped?(id)
        case .ornamentLight(let id, let index):
            onOrnamentLightTapped?(id, index)
        case nil:
            break
        }
    }

    // MARK: - Build

    private func buildIfNeeded() {
        guard !built, size.width > 1, size.height > 1 else { return }
        built = true
        themeRenderer = PiboThemeCatalog.makeRenderer(for: theme)
        addChild(backdrop)
        addChild(themeForegroundLayer)
        addChild(character.rootNode)
        addChild(character.overheadNode)
        themeAtmosphereLayer.zPosition = 40
        addChild(themeAtmosphereLayer)
        addChild(character.effectsNode)
        addChild(rainBack)
        rainFront.zPosition = 60
        addChild(rainFront)
        cam.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cam)
        camera = cam
        character.install(scene: self, camera: cam)
        configureCharacterCallbacks()
        character.apply(
            theme: theme,
            state: activityState,
            animationStateID: animationStateID,
            growth: growth,
            placement: characterPlacement,
            animated: false
        )
        character.buildIfNeeded()
        installThemeRenderer()
        layoutAll()
        themeRenderer?.apply(environment: stageEnvironment)
        themeRenderer?.apply(renderPolicy: themeRenderPolicy)
        themeRenderer?.apply(
            presentedOrnaments: presentedOrnaments,
            unlockedOrnaments: unlockedOrnaments
        )
        themeRenderer?.apply(litOrnamentLights: litOrnamentLights)
        if stageEnvironment.rainIntensity > 0 { applyWeather() }
        applyTuning(visibilityChanged: true)
    }

    /// When the active theme carries body art, the stage shows a sprite instead
    /// of the procedural egg/face geometry.
    private var characterPlacement: PiboCharacterPlacement {
        let renderer = themeRenderer ?? BasicThemeRenderer(theme: theme)
        return renderer.characterPlacement(
            theme: theme,
            growth: growth,
            headNaturalSize: character.headNaturalSize,
            overheadNaturalSize: character.overheadNaturalSize,
            sceneSize: size
        )
    }

    private var themeRenderPolicy: PiboThemeRenderPolicy {
        PiboThemeRenderPolicy(
            ambientMotionScale: tuning.ambientMotionScale,
            lowPowerMode: lowPowerModeEnabled
        )
    }

    // Art bodies size to the Figma frame proportions (image 239.262×235 on a
    // 393-wide frame, node 74:5954); procedural bodies keep the prior sizing.
    private func installThemeRenderer() {
        guard let themeRenderer else { return }
        let context = PiboThemeRendererContext(
            layers: PiboStageThemeLayers(
                background: backdrop,
                foreground: themeForegroundLayer,
                atmosphere: themeAtmosphereLayer
            ),
            scene: self,
            characterRoot: character.rootNode,
            characterHead: character.headForReflection,
            characterBody: { [weak self] in self?.character.bodyForReflection },
            applyCharacterShader: { [weak self] shader in
                self?.character.applyShader(shader)
            }
        )
        themeRenderer.install(context: context, sceneSize: size)
    }

    private func configureCharacterCallbacks() {
        character.onSproutTouched = { [weak self] in self?.onSproutTouched?() }
    }

    private func applyTuning(visibilityChanged: Bool) {
        character.setVisible(tuning.piboVisible)
        character.setHeadRigFlexibility(CGFloat(tuning.headSproutFlexibility))
    }

    private func layoutAll() {
        let placement = characterPlacement
        character.apply(
            theme: theme,
            state: activityState,
            animationStateID: animationStateID,
            growth: growth,
            placement: placement,
            animated: false
        )
        rainBack.zPosition = placement.weatherBackZ
        if !character.isCloseupActive {
            cam.position = CGPoint(x: size.width / 2, y: size.height / 2)
            cam.setScale(1)
        }
        themeRenderer?.didEvaluateActions()
    }

    // MARK: - Weather

    private func applyWeather() {
        weatherController.apply(
            environment: stageEnvironment,
            lowPowerMode: lowPowerModeEnabled,
            size: size,
            wind: themeRenderer?.wind ?? StageWind(
                direction: CGVector(dx: -0.9, dy: -0.08),
                strength: 0.3,
                gustiness: 0.2
            ),
            themeImpact: { [weak self] in
                guard let self else { return nil }
                return self.themeRenderer?.precipitationImpact(in: self)
            },
            characterImpactPoint: { [weak self] in
                self?.character.randomPrecipitationPoint()
            }
        )
    }

}

import SpriteKit
import UIKit

final class ForestThemeRenderer: PiboThemeRenderer {
    let themeID = PiboTheme.forest.id
    private(set) var wind = StageWind(direction: CGVector(dx: -0.9, dy: -0.08), strength: 0.35, gustiness: 0.28)

    private static let waterTextureName = "forest_water_static"

    private var context: PiboThemeRendererContext?
    private var size: CGSize = .zero
    private var environment: ForestEnvironmentSnapshot = .daylight
    private let configuration: ForestRenderConfiguration = .standard
    private var renderPolicy = PiboThemeRenderPolicy(
        ambientMotionScale: 1,
        lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
    )
    private var flowTime: Float = 0
    private var reflectionUpdateAccumulator: TimeInterval = .infinity

    private var foliage: [ForestFoliageNode] = []
    private var layerNodes: [String: SKSpriteNode] = [:]
    private var foliageNodes: [String: ForestFoliageNode] = [:]
    private let reflectionLayer = SKCropNode()
    private var reflectionProxies: [ForestReflectionProxy] = []
    private var waterBaseNode: SKSpriteNode?
    private var waterNode: SKSpriteNode?
    private var baseNode: SKSpriteNode?
    private var morningLightNode: SKSpriteNode?
    private var duskLightNode: SKSpriteNode?
    private var materialShaders: [ForestLightingGroup: SKShader] = [:]
    private var fireflyEmitter: SKEmitterNode?

    /// 用 `bo` 换来的物件。它们是长期状态，不随环境或帧变化 —— 所以用一份集合 +
    /// 定向增删，而不是每次都重扫清单。
    private var unlockedOrnaments: Set<PiboOrnament.ID> = []
    private var ornamentNodes: [PiboOrnament.ID: SKSpriteNode] = [:]
    /// 物件身上那些可以被点亮的灯。**没有自动夜光** —— 一盏灯不亮到用户亲手点它
    /// 为止（决定 013/014：这盏灯的意义就在于是用户点的）。
    private var ornamentLights: [PiboOrnament.ID: [OrnamentLight]] = [:]
    private var litOrnamentLights: [PiboOrnament.ID: Set<Int>] = [:]

    /// 一盏灯的两层加色节点 + 它在场景里的落点。
    ///
    /// 两层是必要的：`core` 让铃铛本体成为光源，`halo` 让光**溢出剪影之外**。
    /// 灯之所以读起来像灯靠的是后者 —— 只把贴图本身加亮，无论调到多少都只是
    /// 「这张贴纸变白了」。
    private struct OrnamentLight {
        let index: Int
        /// 场景坐标。
        let position: CGPoint
        /// 命中半径（场景 pt），比发光体本身大得多。
        let hitRadius: CGFloat
        let halo: SKSpriteNode
        let core: SKSpriteNode
    }

    private static let lightActionKey = "ornament.light"
    private static let haloPeak: CGFloat = 0.62
    private static let corePeak: CGFloat = 0.92

    #if DEBUG
    private var waterDebugTuning: WaterDebugTuning?
    #endif

    private struct FoliageDragState {
        let node: ForestFoliageNode
        let origin: CGPoint
        let pivot: CGPoint
        let initialVector: CGVector
        let initialInteractionAngle: CGFloat
        var latestTargetAngle: CGFloat
        var latestTimestamp: TimeInterval
        var releaseVelocity: CGFloat = 0
        var activated = false
        var hapticTriggered = false
    }

    private var foliageDrag: FoliageDragState?
    private lazy var foliageImpactFeedback = UIImpactFeedbackGenerator(style: .soft)
    private static let foliageDragSlop: CGFloat = 6
    private static let foliageHapticAngle: CGFloat = .pi / 15

    func install(context: PiboThemeRendererContext, sceneSize: CGSize) {
        self.context = context
        size = sceneSize
        rebuild()
    }

    func teardown() {
        cancelInteraction()
        context?.layers.background.removeAllChildren()
        context?.layers.foreground.removeAllChildren()
        context?.layers.atmosphere.removeAllChildren()
        context?.applyCharacterShader(nil)
        context = nil
        clearReferences()
    }

    func layout(sceneSize: CGSize) {
        guard sceneSize.width > 1, sceneSize.height > 1, sceneSize != size else { return }
        size = sceneSize
        rebuild()
    }

    func apply(environment input: PiboStageEnvironment) {
        environment = ForestEnvironmentAdapter.resolve(input)
        wind = environment.wind
        applyLighting()
        refreshOrnamentLights(igniting: [])
    }

    func apply(renderPolicy: PiboThemeRenderPolicy) {
        self.renderPolicy = renderPolicy
        applyWaterPerformanceUniforms()
        updateFireflies()
    }

    func apply(unlockedOrnaments ids: Set<PiboOrnament.ID>) {
        guard ids != unlockedOrnaments else { return }
        unlockedOrnaments = ids
        // 定向增删，不走 `rebuild()` —— 那会连水面 shader、反射代理和全部枝叶一起
        // 重建，为了挂一盏灯把整片森林闪一下。
        syncOrnaments()
    }

    func apply(litOrnamentLights lights: [PiboOrnament.ID: Set<Int>]) {
        guard lights != litOrnamentLights else { return }
        // 只有**这一次新增**的那些灯才播点亮动画。整份重发（重建之后、前台恢复
        // 之后）不该让昨晚点的四盏灯一起再"啪"地亮一遍。
        var igniting: Set<LightKey> = []
        for (id, indices) in lights {
            let previous = litOrnamentLights[id] ?? []
            for index in indices.subtracting(previous) { igniting.insert(LightKey(id: id, index: index)) }
        }
        litOrnamentLights = lights
        refreshOrnamentLights(igniting: igniting)
    }

    private struct LightKey: Hashable {
        let id: PiboOrnament.ID
        let index: Int
    }

    func update(time: TimeInterval, deltaTime: TimeInterval, reduceMotion: Bool) {
        flowTime.formTruncatingRemainder(dividingBy: 120)
        flowTime += Float(deltaTime)
        reflectionUpdateAccumulator += deltaTime
        waterBaseNode?.shader?.uniformNamed("u_flow_time")?.floatValue = flowTime
        waterNode?.shader?.uniformNamed("u_flow_time")?.floatValue = flowTime

        var tunedWind = wind
        tunedWind.strength *= CGFloat(renderPolicy.ambientMotionScale)
        updateFoliageNeighborTargets(reduceMotion: reduceMotion)
        for leaf in foliage {
            leaf.update(time: time, deltaTime: deltaTime, wind: tunedWind, reduceMotion: reduceMotion)
        }
    }

    func didEvaluateActions() {
        updateReflections()
    }

    func characterPlacement(
        theme: PiboTheme,
        growth: PiboGrowthStage,
        headNaturalSize: CGSize?,
        overheadNaturalSize: CGSize?,
        sceneSize: CGSize
    ) -> PiboCharacterPlacement {
        let mapper = ForestLayoutMapper(sceneSize: sceneSize)
        let bodyWidth = 181.1602 * mapper.scale
        let bodyHeight = 199.592 / 181.1602 * bodyWidth
        let foot = mapper.point(ForestSceneManifest.piboFootPoint)
        let body = PiboNodePlacement(
            position: CGPoint(x: foot.x, y: foot.y + bodyHeight * 0.5),
            size: CGSize(width: bodyWidth, height: bodyHeight)
        )

        let resolved = theme.resolvedHead(for: growth)
        let head = resolved.head.map { sprite in
            let natural = headNaturalSize ?? CGSize(width: 30.716, height: 66.573)
            return PiboNodePlacement(
                position: CGPoint(
                    x: (sprite.centerX - theme.bodyCenterX) * mapper.scale,
                    y: (theme.bodyCenterY - sprite.centerY) * mapper.scale
                ),
                size: mapper.size(natural)
            )
        }
        let overhead = resolved.overhead.map { sprite in
            let natural = overheadNaturalSize ?? CGSize(width: 234, height: 64)
            let scale = sceneSize.height / 852.0
            return PiboNodePlacement(
                position: CGPoint(
                    x: sceneSize.width * (sprite.centerX / 393.0),
                    y: sceneSize.height * (1 - sprite.centerY / 852.0)
                ),
                size: CGSize(width: natural.width * scale, height: natural.height * scale)
            )
        }
        return PiboCharacterPlacement(
            body: body,
            head: head,
            overhead: overhead,
            groundLineY: mapper.point(CGPoint(x: 0, y: 610)).y,
            characterZ: 20,
            overheadZ: 33,
            weatherBackZ: 24,
            usesCanonicalMotion: true
        )
    }

    func beginInteraction(at point: CGPoint, timestamp: TimeInterval) -> Bool {
        guard foliageDrag == nil, let scene = context?.scene,
              let leaf = foliage
                .filter(\.acceptsDirectManipulation)
                .sorted(by: { $0.zPosition > $1.zPosition })
                .first(where: { $0.containsOpaquePoint(point, in: scene) }) else { return false }
        let pivot = leaf.convert(CGPoint.zero, to: scene)
        foliageDrag = FoliageDragState(
            node: leaf,
            origin: point,
            pivot: pivot,
            initialVector: CGVector(dx: point.x - pivot.x, dy: point.y - pivot.y),
            initialInteractionAngle: leaf.displayedInteractionAngle,
            latestTargetAngle: leaf.displayedInteractionAngle,
            latestTimestamp: timestamp
        )
        leaf.beginDirectManipulation()
        foliageImpactFeedback.prepare()
        return true
    }

    func moveInteraction(to point: CGPoint, timestamp: TimeInterval) {
        guard var drag = foliageDrag else { return }
        let distance = hypot(point.x - drag.origin.x, point.y - drag.origin.y)
        if !drag.activated, distance < Self.foliageDragSlop { return }
        drag.activated = true

        let currentVector = CGVector(dx: point.x - drag.pivot.x, dy: point.y - drag.pivot.y)
        let mapperScale = ForestLayoutMapper(sceneSize: size).scale
        let minimumRadius = 24 * mapperScale
        let rawAngle: CGFloat
        if hypot(drag.initialVector.dx, drag.initialVector.dy) < minimumRadius
            || hypot(currentVector.dx, currentVector.dy) < minimumRadius {
            rawAngle = drag.initialInteractionAngle
                - (point.x - drag.origin.x) / max(90 * mapperScale, 1) * drag.node.maximumInteractionAngle
        } else {
            let cross = drag.initialVector.dx * currentVector.dy - drag.initialVector.dy * currentVector.dx
            let dot = drag.initialVector.dx * currentVector.dx + drag.initialVector.dy * currentVector.dy
            rawAngle = drag.initialInteractionAngle + atan2(cross, dot)
        }
        let targetAngle = constrainedAngle(rawAngle, maximum: drag.node.maximumInteractionAngle)
        let elapsed = timestamp - drag.latestTimestamp
        if elapsed > 0.001 {
            let instantaneous = (targetAngle - drag.latestTargetAngle) / CGFloat(elapsed)
            let blend = 1 - exp(-CGFloat(elapsed) / 0.04)
            drag.releaseVelocity += (instantaneous - drag.releaseVelocity) * blend
        }
        drag.latestTargetAngle = targetAngle
        drag.latestTimestamp = timestamp
        drag.node.setDirectTargetAngle(targetAngle)
        if !drag.hapticTriggered, abs(targetAngle) >= Self.foliageHapticAngle {
            foliageImpactFeedback.impactOccurred(intensity: 0.35)
            drag.hapticTriggered = true
        }
        foliageDrag = drag
    }

    func endInteraction(at point: CGPoint, timestamp: TimeInterval, cancelled: Bool) {
        guard let drag = foliageDrag else { return }
        let tapDirection: CGFloat? = !cancelled && !drag.activated
            ? (point.x < drag.pivot.x ? 1 : -1)
            : nil
        let velocityScale: CGFloat = UIAccessibility.isReduceMotionEnabled ? 0.35 : 1
        drag.node.endDirectManipulation(
            releaseVelocity: cancelled ? 0 : drag.releaseVelocity * velocityScale,
            tapDirection: tapDirection
        )
        foliageDrag = nil
        for leaf in foliage { leaf.setNeighborTargetAngle(0) }
    }

    func precipitationImpact(in scene: SKScene) -> ThemePrecipitationImpact? {
        let roll = CGFloat.random(in: 0...1)
        if roll < 0.48, let point = randomWaterPoint() {
            return ThemePrecipitationImpact(
                point: point,
                splashScale: CGFloat.random(in: 0.75...1.15),
                flatten: 0.35
            )
        }
        if roll < 0.72, let leaf = foliage.randomElement() {
            let frame = leaf.calculateAccumulatedFrame()
            let point = CGPoint(
                x: CGFloat.random(in: frame.minX...frame.maxX),
                y: CGFloat.random(in: frame.midY...frame.maxY)
            )
            let side: CGFloat = point.x < frame.midX ? -1 : 1
            let strength = environment.rainIntensity
            return ThemePrecipitationImpact(
                point: point,
                splashScale: 0.52,
                flatten: 0.64,
                reaction: { [weak leaf] in leaf?.receiveRainImpact(strength: strength, side: side) }
            )
        }
        let mapper = ForestLayoutMapper(sceneSize: size)
        return ThemePrecipitationImpact(
            point: mapper.point(CGPoint(
                x: CGFloat.random(in: 24...369),
                y: CGFloat.random(in: 570...625)
            )),
            splashScale: CGFloat.random(in: 0.65...1.0),
            flatten: 0.45
        )
    }

    #if DEBUG
    func applyWaterDebugTuning(_ tuning: WaterDebugTuning) {
        waterDebugTuning = tuning.sanitized
        applyWaterPerformanceUniforms()
        updateWaterLighting()
        updateReflections(force: true)
        waterNode?.shader?.uniformNamed("u_mask_preview")?.floatValue = tuning.sanitized.showMask ? 1 : 0
    }
    #endif

    private func rebuild() {
        guard let context, size.width > 1, size.height > 1 else { return }
        cancelInteraction()
        context.layers.background.removeAllChildren()
        context.layers.foreground.removeAllChildren()
        context.layers.atmosphere.removeAllChildren()
        clearReferences()
        context.scene?.backgroundColor = SKColor(red: 0.827, green: 0.933, blue: 0.890, alpha: 1)
        let mapper = ForestLayoutMapper(sceneSize: size)

        let base = SKSpriteNode(color: context.scene?.backgroundColor ?? .clear, size: size)
        base.position = CGPoint(x: size.width / 2, y: size.height / 2)
        base.zPosition = -1
        context.layers.background.addChild(base)
        baseNode = base

        for definition in ForestSceneManifest.backgroundLayers {
            let sprite = forestSprite(for: definition, mapper: mapper)
            sprite.shader = materialShader(for: definition.lightingGroup)
            context.layers.background.addChild(sprite)
            layerNodes[definition.image] = sprite
        }

        let waterDefinition = ForestSceneManifest.river
        let waterBase = forestSprite(for: waterDefinition, mapper: mapper)
        waterBase.texture = SKTexture(imageNamed: Self.waterTextureName)
        waterBase.texture?.filteringMode = .linear
        waterBase.shader = makeWaterBaseShader()
        context.layers.background.addChild(waterBase)
        waterBaseNode = waterBase

        let riverMask = forestSprite(for: waterDefinition, mapper: mapper)
        riverMask.texture = SKTexture(imageNamed: Self.waterTextureName)
        riverMask.texture?.filteringMode = .linear
        riverMask.zPosition = 0
        reflectionLayer.maskNode = riverMask
        reflectionLayer.zPosition = waterDefinition.zPosition + 0.2
        context.layers.background.addChild(reflectionLayer)

        let waterSurface = forestSprite(for: waterDefinition, mapper: mapper)
        waterSurface.texture = SKTexture(imageNamed: Self.waterTextureName)
        waterSurface.texture?.filteringMode = .linear
        waterSurface.zPosition = waterDefinition.zPosition + 0.6
        waterSurface.blendMode = .screen
        waterSurface.shader = makeWaterShader()
        context.layers.background.addChild(waterSurface)
        waterNode = waterSurface

        for definition in ForestSceneManifest.foliage {
            let texture = SKTexture(imageNamed: definition.image)
            texture.filteringMode = .linear
            let leaf = ForestFoliageNode(texture: texture, definition: definition)
            leaf.size = mapper.size(definition.frame.size)
            leaf.position = mapper.point(CGPoint(
                x: definition.frame.minX + definition.frame.width * definition.anchor.x,
                y: definition.frame.minY + definition.frame.height * definition.anchor.y
            ))
            leaf.shader = materialShader(for: definition.lightingGroup)
            context.layers.foreground.addChild(leaf)
            foliage.append(leaf)
            foliageNodes[definition.image] = leaf
        }

        let morning = forestSprite(for: ForestSceneManifest.morningLight, mapper: mapper)
        morning.blendMode = .screen
        context.layers.background.addChild(morning)
        morningLightNode = morning

        let dusk = forestSprite(for: ForestSceneManifest.morningLight, mapper: mapper)
        dusk.position.x = size.width - morning.position.x
        dusk.xScale = -1
        dusk.blendMode = .screen
        context.layers.background.addChild(dusk)
        duskLightNode = dusk

        rebuildReflectionProxies()
        applyWaterPerformanceUniforms()
        applyLighting()
        syncOrnaments()
    }

    // MARK: 兑换来的物件

    /// 把已解锁物件补齐、把不该在的移除。`rebuild()` 之后也要跑一次 ——
    /// 那一步清空了 background，物件得重新挂上去。
    private func syncOrnaments() {
        guard let context, size.width > 1, size.height > 1 else { return }
        let mapper = ForestLayoutMapper(sceneSize: size)

        // 先收集再删。直接在遍历字典的同时改它，靠的是 Swift 的写时复制语义 ——
        // 能跑，但读的人得先想明白这一点才敢确认它是对的。
        for id in ornamentNodes.keys.filter({ !unlockedOrnaments.contains($0) }) {
            ornamentNodes.removeValue(forKey: id)?.removeFromParent()
            // 发光层也得摘掉。只把引用置 nil 会把节点孤儿化在场景里：
            // `refreshOrnamentLights` 再也看不见它，于是它冻在最后一次的 alpha 上，
            // 夜里就成了一片没有灯的加色光斑。
            for light in ornamentLights.removeValue(forKey: id) ?? [] {
                light.halo.removeFromParent()
                light.core.removeFromParent()
            }
        }

        for ornament in PiboOrnament.ordered {
            guard unlockedOrnaments.contains(ornament.id),
                  ornamentNodes[ornament.id] == nil,
                  // 没有落位 = 美术还没到（或者像椰壳那样本来就是底图的一部分）。
                  // 安静跳过，不要往用户的森林里放占位方块。
                  let placement = ornament.placement,
                  UIImage(named: placement.image) != nil
            else { continue }

            let definition = ForestSceneManifest.Layer(
                image: placement.image,
                frame: placement.frame,
                zPosition: placement.zPosition,
                lightingGroup: placement.lightingGroup
            )
            let sprite = forestSprite(for: definition, mapper: mapper)
            sprite.shader = materialShader(for: placement.lightingGroup)
            context.layers.background.addChild(sprite)
            ornamentNodes[ornament.id] = sprite
            // 刻意**不**写进 `layerNodes` —— 那是清单图层的索引（反射代理按名字从里面
            // 取源节点）。把物件混进去既没人用，删除时又不会被清掉，只会留下一个指向
            // 已脱离场景的节点的悬挂引用。

            if !placement.lights.isEmpty {
                ornamentLights[ornament.id] = placement.lights.enumerated().map { index, light in
                    makeOrnamentLight(
                        index: index,
                        light: light,
                        placement: placement,
                        mapper: mapper,
                        parent: context.layers.background
                    )
                }
            }
        }
        refreshOrnamentLights(igniting: [])
    }

    private func makeOrnamentLight(
        index: Int,
        light: PiboOrnament.Placement.Light,
        placement: PiboOrnament.Placement,
        mapper: ForestLayoutMapper,
        parent: SKNode
    ) -> OrnamentLight {
        // `light.center` 是素材局部 pt、原点在素材左上角；`frame.origin` 也是设计
        // 画板的左上角坐标。两者同向，直接相加就是设计画板绝对坐标。
        let designPoint = CGPoint(
            x: placement.frame.minX + light.center.x,
            y: placement.frame.minY + light.center.y
        )
        let position = mapper.point(designPoint)

        func glow(texture: SKTexture, diameter: CGFloat, z: CGFloat) -> SKSpriteNode {
            let node = SKSpriteNode(texture: texture)
            node.size = mapper.size(CGSize(width: diameter, height: diameter))
            node.position = position
            node.zPosition = z
            node.blendMode = .add
            node.alpha = 0
            parent.addChild(node)
            return node
        }

        return OrnamentLight(
            index: index,
            position: position,
            // 铃铛本身只有 15–29pt 宽，直接拿它当判定圆会小到点不中。放到 44pt
            // 触控目标级别是安全的：四个铃铛最近的中心距是 48.7pt，而命中取的是
            // **最近者**而非先到者，判定圆重叠也不会有歧义。
            hitRadius: max(light.radius * 1.7, 22) * mapper.scale,
            halo: glow(texture: Self.haloTexture, diameter: light.radius * 6.4, z: placement.zPosition + 0.05),
            core: glow(texture: Self.coreTexture, diameter: light.radius * 3.0, z: placement.zPosition + 0.1)
        )
    }

    /// 把每盏灯推到它该有的亮度。`igniting` 里的那些额外播一次点亮动画。
    private func refreshOrnamentLights(igniting: Set<LightKey>) {
        guard !ornamentLights.isEmpty else { return }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        // 白天点灯也要看得见 —— 用户可以在任何时候点亮。但正午的一盏小灯本来
        // 就该只是一点微光，压到 45% 是诚实的，不是把交互做废。
        let strength = 0.45 + 0.55 * environment.lighting.nightness

        for (id, lights) in ornamentLights {
            let lit = litOrnamentLights[id] ?? []
            for light in lights {
                let isLit = lit.contains(light.index)
                let flare = igniting.contains(LightKey(id: id, index: light.index))
                apply(
                    peak: Self.haloPeak * strength,
                    to: light.halo, lit: isLit, igniting: flare,
                    phase: Double(light.index) * 0.29, reduceMotion: reduceMotion
                )
                apply(
                    peak: Self.corePeak * strength,
                    to: light.core, lit: isLit, igniting: flare,
                    phase: Double(light.index) * 0.29, reduceMotion: reduceMotion
                )
            }
        }
    }

    private func apply(
        peak: CGFloat,
        to node: SKSpriteNode,
        lit: Bool,
        igniting: Bool,
        phase: Double,
        reduceMotion: Bool
    ) {
        node.removeAction(forKey: Self.lightActionKey)
        guard lit else {
            node.run(.fadeAlpha(to: 0, duration: 0.55), withKey: Self.lightActionKey)
            return
        }

        var steps: [SKAction] = []
        if igniting, !reduceMotion {
            // 起得快、过冲一点、再落回来。线性淡入会读成「有人调了透明度」，
            // 而不是「灯点着了」。
            let rise = SKAction.fadeAlpha(to: min(peak * 1.22, 1), duration: 0.14)
            rise.timingMode = .easeOut
            let settle = SKAction.fadeAlpha(to: peak, duration: 0.32)
            settle.timingMode = .easeInEaseOut
            steps += [rise, settle]
        } else {
            let fade = SKAction.fadeAlpha(to: peak, duration: igniting ? 0.26 : 0.45)
            fade.timingMode = .easeInEaseOut
            steps.append(fade)
        }

        if !reduceMotion {
            // 极慢的呼吸。这是「活的光」和「贴纸」的分界；逐灯错相，四盏才不会
            // 整齐地一起喘气。
            steps.append(.wait(forDuration: phase))
            steps.append(.repeatForever(.sequence([
                .fadeAlpha(to: peak * 0.90, duration: 1.15),
                .fadeAlpha(to: peak, duration: 1.25),
            ])))
        }
        node.run(.sequence(steps), withKey: Self.lightActionKey)
    }

    func handleTap(at point: CGPoint) -> PiboThemeTapResult? {
        var best: (id: PiboOrnament.ID, index: Int, distance: CGFloat)?
        for (id, lights) in ornamentLights {
            for light in lights {
                let distance = hypot(point.x - light.position.x, point.y - light.position.y)
                guard distance <= light.hitRadius else { continue }
                guard let current = best else {
                    best = (id, light.index, distance)
                    continue
                }
                // **最近者胜**，不是先到者胜。判定圆因此可以放心开到触控目标级别，
                // 即便相邻两盏的圆重叠也不会互相偷点击。
                if distance < current.distance { best = (id, light.index, distance) }
            }
        }
        guard let best else { return nil }
        // 已经亮着的灯照样上报。渲染器这份 `litOrnamentLights` 是存储的镜像、
        // 可能慢一帧，在这里私自吞掉点击会比让存储做一次空操作更难查。
        return .ornamentLight(best.id, index: best.index)
    }

    private func clearReferences() {
        foliage.removeAll(keepingCapacity: true)
        layerNodes.removeAll(keepingCapacity: true)
        foliageNodes.removeAll(keepingCapacity: true)
        ornamentNodes.removeAll(keepingCapacity: true)
        ornamentLights.removeAll(keepingCapacity: true)
        reflectionLayer.removeAllChildren()
        reflectionLayer.maskNode = nil
        reflectionProxies.removeAll(keepingCapacity: true)
        reflectionUpdateAccumulator = .infinity
        waterBaseNode = nil
        waterNode = nil
        baseNode = nil
        morningLightNode = nil
        duskLightNode = nil
        fireflyEmitter = nil
        materialShaders.removeAll(keepingCapacity: true)
    }

    private func cancelInteraction() {
        guard let drag = foliageDrag else { return }
        drag.node.endDirectManipulation(releaseVelocity: 0, tapDirection: nil)
        foliageDrag = nil
    }

    private func updateFoliageNeighborTargets(reduceMotion: Bool) {
        guard let drag = foliageDrag, drag.activated else {
            for leaf in foliage { leaf.setNeighborTargetAngle(0) }
            return
        }
        let source = drag.node
        let radius = 160 * ForestLayoutMapper(sceneSize: size).scale
        for leaf in foliage {
            guard leaf !== source else {
                leaf.setNeighborTargetAngle(0)
                continue
            }
            let distance = hypot(leaf.position.x - source.position.x, leaf.position.y - source.position.y)
            let linear = max(0, 1 - distance / max(radius, 1))
            let smooth = linear * linear * (3 - 2 * linear)
            leaf.setNeighborTargetAngle(
                source.displayedInteractionAngle
                    * leaf.neighborInfluence
                    * smooth
                    * (reduceMotion ? 0.5 : 1)
            )
        }
    }

    private func constrainedAngle(_ angle: CGFloat, maximum: CGFloat) -> CGFloat {
        guard maximum > 0 else { return 0 }
        let magnitude = abs(angle)
        let knee = maximum * 0.72
        guard magnitude > knee else { return angle }
        let remaining = maximum - knee
        let excess = magnitude - knee
        let constrained = knee + remaining * excess / (excess + remaining)
        return angle < 0 ? -constrained : constrained
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
        shader.addUniform(SKUniform(name: "u_highlight_strength", float: 0.82))
        shader.addUniform(SKUniform(name: "u_low_power", float: lowPowerModeEnabled ? 1 : 0))
        #if DEBUG
        shader.addUniform(SKUniform(name: "u_mask_preview", float: waterDebugTuning?.showMask == true ? 1 : 0))
        #else
        shader.addUniform(SKUniform(name: "u_mask_preview", float: 0))
        #endif
        return shader
    }

    private func makeWaterBaseShader() -> SKShader {
        let shader = SKShader(fileNamed: "ForestWaterBase.fsh")
        shader.addUniform(SKUniform(name: "u_flow_time", float: flowTime))
        shader.addUniform(SKUniform(name: "u_flow_speed", float: waterFlowSpeed))
        shader.addUniform(SKUniform(name: "u_ripple_strength", float: rippleStrength))
        shader.addUniform(SKUniform(name: "u_darkness", float: 0))
        shader.addUniform(SKUniform(name: "u_tint", vectorFloat3: vector_float3(1, 1, 1)))
        shader.addUniform(SKUniform(name: "u_tint_amount", float: 0))
        shader.addUniform(SKUniform(name: "u_low_power", float: lowPowerModeEnabled ? 1 : 0))
        return shader
    }

    private func materialShader(for group: ForestLightingGroup) -> SKShader? {
        guard group != .water, group != .emissive else { return nil }
        if let shader = materialShaders[group] { return shader }
        let shader = SKShader(fileNamed: "ForestMaterial.fsh")
        shader.addUniform(SKUniform(name: "u_darkness", float: 0))
        shader.addUniform(SKUniform(name: "u_tint", vectorFloat3: vector_float3(1, 1, 1)))
        shader.addUniform(SKUniform(name: "u_tint_amount", float: 0))
        shader.addUniform(SKUniform(name: "u_saturation", float: 1))
        shader.addUniform(SKUniform(name: "u_lift", float: 0))
        materialShaders[group] = shader
        return shader
    }

    private var waterFlowSpeed: Float {
        #if DEBUG
        if let waterDebugTuning { return Float(waterDebugTuning.speed) }
        #endif
        return Float(configuration.waterFlowSpeed)
    }

    private var rippleStrength: Float {
        #if DEBUG
        let base = Float(waterDebugTuning?.rippleStrength ?? 0.78)
        #else
        let base: Float = 0.78
        #endif
        return base * (lowPowerModeEnabled ? 0.68 : 1)
    }

    private func applyWaterPerformanceUniforms() {
        for shader in [waterBaseNode?.shader, waterNode?.shader].compactMap({ $0 }) {
            shader.uniformNamed("u_flow_speed")?.floatValue = waterFlowSpeed
            shader.uniformNamed("u_ripple_strength")?.floatValue = rippleStrength
            shader.uniformNamed("u_low_power")?.floatValue = lowPowerModeEnabled ? 1 : 0
        }
    }

    private var lowPowerModeEnabled: Bool { renderPolicy.lowPowerMode }

    private func applyLighting() {
        let profiles: [(ForestLightingGroup, ForestMaterialLighting)] = [
            (.far, environment.lighting.far),
            (.midground, environment.lighting.midground),
            (.foreground, environment.lighting.foreground),
            (.pibo, environment.lighting.pibo),
        ]
        for (group, profile) in profiles {
            guard let shader = materialShader(for: group) else { continue }
            shader.uniformNamed("u_darkness")?.floatValue = Float(profile.darkness)
            shader.uniformNamed("u_tint")?.vectorFloat3Value = vector_float3(
                Float(profile.tint.red), Float(profile.tint.green), Float(profile.tint.blue)
            )
            shader.uniformNamed("u_tint_amount")?.floatValue = Float(profile.tintAmount)
            shader.uniformNamed("u_saturation")?.floatValue = Float(profile.saturation)
            shader.uniformNamed("u_lift")?.floatValue = Float(profile.lift)
        }

        let far = environment.lighting.far
        let authored = ForestRGB(red: 0.827, green: 0.933, blue: 0.890)
        let shaded = ForestRGB(
            red: authored.red * (1 - far.darkness) * (1 + (far.tint.red - 1) * far.tintAmount),
            green: authored.green * (1 - far.darkness) * (1 + (far.tint.green - 1) * far.tintAmount),
            blue: authored.blue * (1 - far.darkness) * (1 + (far.tint.blue - 1) * far.tintAmount)
        )
        let color = SKColor(red: shaded.red, green: shaded.green, blue: shaded.blue, alpha: 1)
        context?.scene?.backgroundColor = color
        baseNode?.color = color
        context?.applyCharacterShader(materialShader(for: .pibo))
        morningLightNode?.alpha = environment.lighting.morningBeam
        duskLightNode?.alpha = environment.lighting.duskBeam
        updateWaterLighting()
        updateFireflies()
    }

    private func updateWaterLighting() {
        let water = environment.lighting.water
        waterBaseNode?.shader?.uniformNamed("u_darkness")?.floatValue = Float(water.darkness)
        waterBaseNode?.shader?.uniformNamed("u_tint")?.vectorFloat3Value = vector_float3(
            Float(water.tint.red), Float(water.tint.green), Float(water.tint.blue)
        )
        waterBaseNode?.shader?.uniformNamed("u_tint_amount")?.floatValue = Float(water.tintAmount)
        #if DEBUG
        let highlight = Float(waterDebugTuning?.highlightStrength ?? Double(water.highlightStrength))
        #else
        let highlight = Float(water.highlightStrength)
        #endif
        waterNode?.shader?.uniformNamed("u_highlight_strength")?.floatValue = highlight
    }

    private func updateFireflies() {
        guard let context else { return }
        let emitter = fireflyEmitter ?? makeFireflyEmitter(in: context.layers.atmosphere)
        emitter.position = CGPoint(x: size.width / 2, y: size.height * 0.36)
        emitter.particlePositionRange = CGVector(dx: size.width * 0.92, dy: size.height * 0.32)
        emitter.particleBirthRate = environment.lighting.fireflyBirthRate
            * (lowPowerModeEnabled ? 1 / 3 : 1)
    }

    private func makeFireflyEmitter(in parent: SKNode) -> SKEmitterNode {
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
        parent.addChild(emitter)
        fireflyEmitter = emitter
        return emitter
    }

    private func rebuildReflectionProxies() {
        reflectionLayer.removeAllChildren()
        reflectionProxies.removeAll(keepingCapacity: true)
        guard reflectionLayer.parent != nil else { return }

        func append(
            source: SKSpriteNode,
            contact: CGPoint,
            height: CGFloat,
            sourceVRange: ClosedRange<CGFloat> = 0 ... 1,
            alpha: CGFloat,
            z: CGFloat,
            motionResponse: ForestReflectionProjection.MotionResponse = .mirrored,
            geometryIsStatic: Bool = false
        ) {
            let proxy = ForestReflectionProxy(
                source: source,
                contactPoint: contact,
                projectionHeight: height,
                sourceVRange: sourceVRange,
                baseAlpha: alpha,
                zPosition: z,
                motionResponse: motionResponse,
                geometryIsStatic: geometryIsStatic
            )
            reflectionLayer.addChild(proxy.reflected)
            reflectionProxies.append(proxy)
        }

        for image in ["forest_bg_tree", "forest_secondary_tree"] {
            guard let source = layerNodes[image],
                  let definition = ForestSceneManifest.backgroundLayers.first(where: { $0.image == image }) else {
                continue
            }
            let contact = CGPoint(x: definition.frame.midX, y: ForestSceneManifest.river.frame.minY)
            let lowerV = min(max((definition.frame.maxY - contact.y) / definition.frame.height, 0), 1)
            append(source: source, contact: contact, height: contact.y - definition.frame.minY,
                   sourceVRange: lowerV ... 1, alpha: 0.24, z: 0, geometryIsStatic: true)
        }

        for item in [
            ("forest_main_leaf_1", CGFloat(730), CGFloat(0.26)),
            ("forest_main_leaf_2", CGFloat(730), CGFloat(0.26)),
            ("forest_front_leaf_1", CGFloat(825), CGFloat(0.22)),
            ("forest_front_leaf_2", CGFloat(820), CGFloat(0.22)),
        ] {
            guard let source = foliageNodes[item.0],
                  let definition = ForestSceneManifest.foliage.first(where: { $0.image == item.0 }) else {
                continue
            }
            let contactY = min(max(item.1, definition.frame.minY), definition.frame.maxY)
            let contact = CGPoint(x: definition.frame.midX, y: contactY)
            let lowerV = min(max((definition.frame.maxY - contact.y) / definition.frame.height, 0), 1)
            append(source: source, contact: contact, height: max(contact.y - definition.frame.minY, 1),
                   sourceVRange: lowerV ... 1, alpha: item.2, z: 1,
                   motionResponse: .followSourceDeformation)
        }

        let contact = ForestSceneManifest.piboFootPoint
        if let body = context?.characterBody() as? SKSpriteNode {
            append(source: body, contact: contact, height: 265, alpha: 0.16, z: 2)
        }
        if let head = context?.characterHead {
            append(source: head, contact: contact, height: 265, alpha: 0.16, z: 3)
        }
        updateReflections(force: true)
    }

    private func updateReflections(force: Bool = false) {
        guard !reflectionProxies.isEmpty, size.width > 1, size.height > 1 else { return }
        let cadence = lowPowerModeEnabled ? 1.0 / 15.0 : 1.0 / 30.0
        guard force || reflectionUpdateAccumulator >= cadence else { return }
        reflectionUpdateAccumulator = 0
        let mapper = ForestLayoutMapper(sceneSize: size)
        let phase = CGFloat(flowTime * waterFlowSpeed)
        let style: ForestReflectionProjection.Style
        let intensity: CGFloat
        #if DEBUG
        if let debug = waterDebugTuning {
            style = ForestReflectionProjection.Style(
                verticalCompression: CGFloat(debug.reflectionCompression),
                tipWidthScale: CGFloat(debug.reflectionTipScale),
                outwardDrift: ForestReflectionProjection.Style.strong.outwardDrift,
                rippleStrength: CGFloat(debug.rippleStrength)
            )
            intensity = CGFloat(debug.reflectionIntensity)
        } else {
            style = .init(
                verticalCompression: ForestReflectionProjection.Style.strong.verticalCompression,
                tipWidthScale: ForestReflectionProjection.Style.strong.tipWidthScale,
                outwardDrift: ForestReflectionProjection.Style.strong.outwardDrift,
                rippleStrength: CGFloat(rippleStrength)
            )
            intensity = 1
        }
        #else
        style = .init(
            verticalCompression: ForestReflectionProjection.Style.strong.verticalCompression,
            tipWidthScale: ForestReflectionProjection.Style.strong.tipWidthScale,
            outwardDrift: ForestReflectionProjection.Style.strong.outwardDrift,
            rippleStrength: CGFloat(rippleStrength)
        )
        intensity = 1
        #endif
        for proxy in reflectionProxies {
            proxy.update(
                in: reflectionLayer,
                sceneSize: size,
                mapper: mapper,
                phase: phase,
                style: style,
                intensity: intensity,
                dayPhaseMultiplier: environment.lighting.water.reflectionStrength,
                lowPower: lowPowerModeEnabled
            )
        }
    }

    private func randomWaterPoint() -> CGPoint? {
        guard let waterNode, let scene = context?.scene,
              let normalized = Self.waterSamples.randomElement() else { return nil }
        return waterNode.convert(
            CGPoint(
                x: (normalized.x - 0.5) * waterNode.size.width,
                y: (normalized.y - 0.5) * waterNode.size.height
            ),
            to: scene
        )
    }

    private static let waterSamples = normalizedAlphaSamples(
        imageNamed: waterTextureName,
        maximumSamplesPerAxis: 64
    )

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
                if pixels[(row * width + column) * 4 + 3] > 80 {
                    result.append(CGPoint(
                        x: (CGFloat(column) + 0.5) / CGFloat(width),
                        y: (CGFloat(row) + 0.5) / CGFloat(height)
                    ))
                }
            }
        }
        return result
    }

    /// 灯光的两张程序化径向渐变。和萤火虫一样是画出来的，不占美术工时。
    ///
    /// 两张的差别在**衰减形状**，不是大小：`core` 中心实、边缘收得快，把铃铛本体
    /// 坐实成光源；`halo` 从一开始就淡、拖一条很长的尾巴，负责光溢出剪影之外。
    /// 用同一张贴图缩放两次做不到这件事 —— 缩放只改尺寸，不改衰减。
    private static let coreTexture: SKTexture = radialGlowTexture(
        stops: [
            (0.00, SKColor(red: 1, green: 0.99, blue: 0.94, alpha: 1)),
            (0.42, SKColor(red: 1, green: 0.94, blue: 0.72, alpha: 0.82)),
            (1.00, .clear),
        ]
    )

    private static let haloTexture: SKTexture = radialGlowTexture(
        stops: [
            (0.00, SKColor(red: 1, green: 0.95, blue: 0.76, alpha: 0.52)),
            (0.30, SKColor(red: 1, green: 0.90, blue: 0.62, alpha: 0.24)),
            (1.00, .clear),
        ]
    )

    private static func radialGlowTexture(stops: [(CGFloat, SKColor)]) -> SKTexture {
        let size = CGSize(width: 128, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: stops.map(\.1.cgColor) as CFArray,
                locations: stops.map(\.0)
            ) else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: size.width / 2,
                options: []
            )
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

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
}

#if DEBUG
extension ForestThemeRenderer: WaterDebugTunable {}
#endif

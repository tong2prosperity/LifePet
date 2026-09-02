import CoreGraphics
import SpriteKit
import UIKit

/// The vector Pibo. Owns one node per element of the current state and drives
/// them through state transitions.
///
/// Layout mirrors the design package's contract exactly (SPEC §2): array order
/// in the data is render order is the source SVG's layer order, so z is just the
/// element's index. Only `body` / `bo` / `boline` morph; everything else
/// crossfades, which is a data fact rather than a shortcut — `angry` and `dive`
/// have no face at all, so five-organ elements cannot correspond across states.
@MainActor
final class PiboVectorCharacter {
    struct ProjectionStyle: Equatable {
        let bodyColor: UIColor
        let handColor: UIColor
        let outlineColor: UIColor
        let outlineDesignWidth: CGFloat
        let paperGrain: CGFloat

        static let friendShadow = ProjectionStyle(
            bodyColor: UIColor(red: 229 / 255, green: 229 / 255, blue: 245 / 255, alpha: 1),
            handColor: UIColor(red: 136 / 255, green: 210 / 255, blue: 198 / 255, alpha: 1),
            outlineColor: UIColor(red: 35 / 255, green: 190 / 255, blue: 148 / 255, alpha: 1),
            outlineDesignWidth: 5,
            paperGrain: 0.09
        )
    }
    /// Container for the settle pulse. The pulse must not touch path data, so it
    /// rides a node above the geometry (SPEC §5).
    let rootNode = SKNode()

    /// The 毛. Lives in its own effect node so the existing six-bone spring rig
    /// can keep driving it through `SKWarpGeometryGrid` while the paths inside
    /// morph. The warp deforms a render mesh and never reads path data, so the
    /// two systems compose without knowing about each other.
    let sproutNode = SKEffectNode()
    /// Keeps 3× path tessellation inside the effect while the warp host itself
    /// stays in the same 1× coordinate system as Pibo's body. Scaling the
    /// `SKEffectNode` used to offset its offscreen texture, so the authored root
    /// was mathematically inside the body but visibly floated above it.
    private let sproutGeometryNode = SKNode()

    /// Scaling happens about a node's own origin, and the design package anchors
    /// the settle pulse at 50% / 80% — near Pibo's feet, so the "biu" reads as
    /// landing rather than as the whole body breathing. This node sits at that
    /// anchor with the geometry offset back out of it.
    /// Business `bounceCut` scales the complete 460×460 player around its
    /// authored 50% / 58% origin. In artboard coordinates that origin is
    /// 50% / 62.266…% because the 300×300 artboard has 80 px player padding.
    private let presentationNode = SKNode()
    private let pulseNode = SKNode()
    private let contentNode = SKNode()
    private let bodyLayer = SKNode()
    /// A `bo` is a persistent container, not a leaf that scales into existence.
    /// The authored solid fill and highlight live under one root-to-tip crop; a
    /// translucent shell remains outside the crop even when progress is zero.
    private let boContentCrop = SKCropNode()
    private let boRevealMask = SKShapeNode()
    private let boGhostNode = SKShapeNode()
    private let boGhostOutlineNode = SKShapeNode()
    private let boRootGhostNode = SKShapeNode()
    private let boRootContentNode = SKShapeNode()
    private var boContainerProgress = PiboBoContainerProgress()
    private var boContainerShapeBounds = CGRect.null
    private var boContainerBounds = CGRect.null
    private var boContainerRoot = CGPoint.zero
    private var boContainerLeafRoot = CGPoint.zero
    private var boContainerTip = CGPoint.zero
    private var boConnectionRootDesign = CGPoint.zero
    private var boLeafRootDesign = CGPoint.zero
    private var boConnectorStartDesign = CGPoint.zero
    private var boConnectorEndDesign = CGPoint.zero
    private var boConnectorStart = CGPoint.zero
    private var boConnectorEnd = CGPoint.zero
    /// 闪亮登场的金光。两层描边 + `glowWidth`，对应设计包的双层 drop-shadow：
    /// 外层宽而淡、内层窄而亮。垫在角色底下，不参与命中也不进倒影快照的主体。
    private let glowLayer = SKNode()
    private let glowOuter = SKShapeNode()
    private let glowInner = SKShapeNode()

    /// The effect node rasterises its children to an offscreen texture whose
    /// resolution loses the shape antialiasing. Building the sprout's paths at
    /// this multiple and scaling the host back down restores it — measured in
    /// the Character Lab, see `docs/character-animation-port.md` G0 ②.
    private static let sproutSupersample: CGFloat = 3

    private static let sproutElementIDs: Set<String> = ["bo", "boline"]

    private struct ElementNode {
        let node: SKShapeNode
        let element: PiboCharacterData.Element
        let stateID: String
        /// The path `rebuild` last wrote. Path-level idle primitives deform a
        /// copy of this every frame rather than caching a "rest shape" of their
        /// own — which is what made the web engine permanently deform the
        /// character when a primitive started mid-morph (SPEC §7.6).
        let basePath: CGPath
    }

    private let data: PiboCharacterData
    private let projectionStyle: ProjectionStyle?
    private let projectionGrainShader: SKShader?
    private var elementNodes: [String: ElementNode] = [:]
    private var scale: CGFloat = 1
    private var lighting: PiboCharacterLighting = .neutral
    /// Where the content node sits when nothing is hopping.
    private var contentRest: CGPoint = .zero
    private(set) var currentStateID: String
    private var targetStateID: String
    private var progress: CGFloat = 0
    /// Shared-path control points captured when a morph is redirected before it
    /// settles. They remain the source for the new transition's full duration.
    private var capturedTransitionSource: [String: [CGFloat]]?
    private var capturedTransitionTargetID: String?

    init?(
        stateID: String,
        data: PiboCharacterData?,
        projectionStyle: ProjectionStyle? = nil
    ) {
        guard let data, data.states[stateID] != nil else { return nil }
        self.data = data
        self.projectionStyle = projectionStyle
        projectionGrainShader = projectionStyle?.makeGrainShader()
        currentStateID = stateID
        targetStateID = stateID
        rootNode.addChild(presentationNode)
        presentationNode.addChild(pulseNode)
        pulseNode.addChild(contentNode)
        for glow in [glowOuter, glowInner] {
            glow.fillColor = .clear
            glow.lineCap = .round
            glow.lineJoin = .round
            glow.isAntialiased = true
            glowLayer.addChild(glow)
        }
        glowLayer.alpha = 0
        glowLayer.zPosition = -1
        contentNode.addChild(glowLayer)
        bodyLayer.zPosition = 0
        contentNode.addChild(bodyLayer)
        sproutNode.shouldEnableEffects = true
        sproutNode.shouldRasterize = false
        // The sprout geometry is authored at 3× for antialiasing and this inner
        // node always scales back to 1/3. Modal artboards use exactly scale == 1;
        // relying on `setScale` to install it would hit the equality fast-path
        // and leave bo/boline three times too large, outside the 300×300 frame.
        sproutGeometryNode.setScale(1 / Self.sproutSupersample)
        contentNode.addChild(sproutNode)
        sproutNode.addChild(sproutGeometryNode)
        if projectionStyle == nil {
            boRevealMask.fillColor = .white
            boRevealMask.strokeColor = .clear
            boContentCrop.maskNode = boRevealMask
            boGhostNode.isAntialiased = true
            boGhostOutlineNode.isAntialiased = true
            boRootGhostNode.isAntialiased = true
            sproutGeometryNode.addChild(boRootGhostNode)
            sproutGeometryNode.addChild(boGhostNode)
            boRootContentNode.isAntialiased = true
            boContentCrop.addChild(boRootContentNode)
            sproutGeometryNode.addChild(boContentCrop)
            sproutGeometryNode.addChild(boGhostOutlineNode)
        }
        // The proxy is a sibling of contentNode under the animated presentation
        // containers. It therefore follows bounce/settle scale in the water
        // reflection, while `texture(from: contentNode)` still cannot capture
        // the hidden proxy recursively.
        reflectionSource.isHidden = true
        pulseNode.addChild(reflectionSource)
        applyPulseAnchor()
        // The initial state is already the transition driver's settled state,
        // so its first `setTransition` call is intentionally a no-op. Build the
        // authored geometry here instead of relying on a later state change to
        // make the character appear.
        rebuild()
    }

    /// Damped scale about the design package's anchor, applied to the container
    /// rather than to path data — which is why it can never introduce the spikes
    /// that killed the overshoot-easing experiment.
    func setSettleScale(_ value: CGFloat) {
        pulseNode.setScale(value)
    }

    func setPresentationScale(x: CGFloat, y: CGFloat) {
        presentationNode.xScale = x
        presentationNode.yScale = y
    }

    /// A deliberately small look-toward gesture for the verified food sticker.
    /// It rotates the authored presentation container around Pibo's standing
    /// anchor, so every state keeps its own silhouette and resource set.
    func playFoodObservation(onRight: Bool, reduceMotion: Bool) {
        cancelFoodObservation()
        guard !reduceMotion else { return }
        let angle: CGFloat = onRight ? -0.045 : 0.045
        presentationNode.run(
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
        presentationNode.removeAction(forKey: "foodObservation")
        presentationNode.zRotation = 0
    }

    private func applyPulseAnchor() {
        let anchor = data.settlePulse.anchor
        let ax = anchor.count > 0 ? CGFloat(anchor[0]) : 0.5
        let ay = anchor.count > 1 ? CGFloat(anchor[1]) : 0.8
        // Design anchor → rootNode coordinates (the design frame is Y-down and
        // the character is centred on the origin).
        let offset = CGPoint(
            x: (ax - 0.5) * designFrame.width * scale,
            y: (0.5 - ay) * designFrame.height * scale
        )
        let playerOriginY = CGFloat((460 * 0.58 - 80) / 300)
        let presentationOffset = CGPoint(
            x: 0,
            y: (0.5 - playerOriginY) * designFrame.height * scale
        )
        presentationNode.position = presentationOffset
        pulseNode.position = CGPoint(
            x: offset.x - presentationOffset.x,
            y: offset.y - presentationOffset.y
        )
        contentRest = CGPoint(x: -offset.x, y: -offset.y)
        contentNode.position = contentRest
    }

    // MARK: - Geometry frame

    /// `pointsPerDesignUnit` maps the 300-unit design frame onto the stage. The
    /// character is centred on `rootNode`'s origin.
    func setScale(_ pointsPerDesignUnit: CGFloat) {
        guard pointsPerDesignUnit != scale else { return }
        scale = pointsPerDesignUnit
        sproutGeometryNode.setScale(1 / Self.sproutSupersample)
        applyPulseAnchor()
        rebuild()
    }

    /// Applies the scene's time-of-day lighting. Cheap because the profile
    /// changes with the clock, not with the frame — the resolved colours are
    /// recomputed only when it actually moves.
    func setLighting(_ newLighting: PiboCharacterLighting) {
        guard newLighting != lighting else { return }
        lighting = newLighting
        rebuild()
    }

    private var designFrame: CGSize {
        CGSize(width: data.designFrame.width, height: data.designFrame.height)
    }

    /// 设计坐标 → `rootNode` 局部坐标。外部要把设计空间里的锚点（比如芽根）
    /// 映射到场景里时用它。
    var designToNodeTransform: CGAffineTransform { bodyTransform }

    private var bodyTransform: CGAffineTransform {
        PiboCharacterGeometry.designTransform(scale: scale, frame: designFrame)
    }

    private var sproutTransform: CGAffineTransform {
        PiboCharacterGeometry.designTransform(
            scale: scale * Self.sproutSupersample,
            frame: designFrame
        )
    }

    // MARK: - State

    /// Snaps to a state with no transition.
    func setState(_ stateID: String) {
        guard data.states[stateID] != nil else { return }
        currentStateID = stateID
        targetStateID = stateID
        progress = 0
        capturedTransitionSource = nil
        capturedTransitionTargetID = nil
        rebuild()
    }

    /// Drives a transition. `progress` is the eased value, not raw time — the
    /// easing is the design package's pure-acceleration curve and belongs to the
    /// caller so intro/settle sequencing stays in one place.
    func setTransition(from: String, to: String, progress: CGFloat) {
        guard data.states[from] != nil, data.states[to] != nil else { return }
        let clamped = min(max(progress, 0), 1)
        // Geometry only depends on these three, so at rest this is a no-op and
        // the per-frame cost collapses to the idle animator's transform writes.
        guard from != currentStateID || to != targetStateID || clamped != self.progress else { return }
        if to != targetStateID {
            captureCurrentMorphSourceIfNeeded(for: to)
        }
        currentStateID = from
        targetStateID = to
        self.progress = clamped
        rebuild()
        if clamped >= 1 {
            capturedTransitionSource = nil
            capturedTransitionTargetID = nil
        }
    }

    private func captureCurrentMorphSourceIfNeeded(for newTargetID: String) {
        guard currentStateID != targetStateID,
              progress > 0,
              progress < 1 else {
            capturedTransitionSource = nil
            capturedTransitionTargetID = nil
            return
        }
        var captured: [String: [CGFloat]] = [:]
        for (id, morph) in data.morph {
            if let values = currentMorphValues(id: id, morph: morph) {
                captured[id] = values
            }
        }
        capturedTransitionSource = captured.isEmpty ? nil : captured
        capturedTransitionTargetID = captured.isEmpty ? nil : newTargetID
    }

    private func currentMorphValues(
        id: String,
        morph: PiboCharacterData.Morph
    ) -> [CGFloat]? {
        if capturedTransitionTargetID == targetStateID,
           let source = capturedTransitionSource?[id],
           let target = morph.values(for: targetStateID),
           source.count == target.count {
            return zip(source, target).map { first, second in
                first + (second - first) * progress
            }
        }
        return PiboCharacterGeometry.interpolatedValues(
            for: morph,
            from: currentStateID,
            to: targetStateID,
            progress: progress
        )
    }

    /// Sprout skeleton for the current blend, in design coordinates. The rig
    /// bends root → tip, and `awake` hangs out of the coconut hole with its root
    /// *above* its tip, so an axis is required rather than a canvas-aligned box.
    var sproutAxis: (root: CGPoint, tip: CGPoint)? {
        guard let from = data.states[currentStateID]?.sprout,
              let to = data.states[targetStateID]?.sprout else { return nil }
        func blend(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
        }
        return (blend(from.rootPoint, to.rootPoint), blend(from.tipPoint, to.tipPoint))
    }

    /// Current sprout root in `rootNode` presentation coordinates. The
    /// conversion includes content breathing, settle pulse and business bounce
    /// transforms, so an external effect follows the pixels users actually see.
    func presentedSproutRootPoint() -> CGPoint? {
        guard let root = sproutAxis?.root else { return nil }
        let contentPoint = root.applying(bodyTransform)
        return rootNode.convert(contentPoint, from: contentNode)
    }

    /// The body silhouette in `rootNode`'s coordinates. Feeds hit testing and the
    /// weather system's impact sampling, so the visible shape and the
    /// interactive shape cannot drift apart.
    func bodyPath() -> CGPath? {
        guard let morph = data.morph["body"] else { return nil }
        return interpolatedPath(id: "body", morph: morph, transform: bodyTransform)
    }

    /// Converts a point sampled from `bodyPath()` into the character root's
    /// current presentation space. Weather impacts use this so breathing,
    /// landing pulse and business bounce transforms all move the target point
    /// with the pixels on screen.
    func rootPoint(forBodyPathPoint point: CGPoint) -> CGPoint {
        rootNode.convert(point, from: contentNode)
    }

    func sproutPath() -> CGPath? {
        guard let morph = data.morph["bo"] else { return nil }
        return interpolatedPath(id: "bo", morph: morph, transform: bodyTransform)
    }

    private func interpolatedPath(
        id: String,
        morph: PiboCharacterData.Morph,
        transform: CGAffineTransform
    ) -> CGPath? {
        if capturedTransitionTargetID == targetStateID,
           let source = capturedTransitionSource?[id],
           let target = morph.values(for: targetStateID) {
            return PiboCharacterGeometry.interpolatedPath(
                for: morph,
                fromValues: source,
                toValues: target,
                progress: progress,
                transform: transform
            )
        }
        return PiboCharacterGeometry.interpolatedPath(
            for: morph,
            from: currentStateID,
            to: targetStateID,
            progress: progress,
            transform: transform
        )
    }

    // MARK: - Sprout layer

    /// 芽的层级。
    ///
    /// `bodyLayer` 里每个元素都带 `zPosition = 元素下标`，而整个 `SKEffectNode`
    /// 只有一个 z —— 所以宿主的 z 必须跟元素下标处在同一把尺子上，不能想当然地写 0
    /// 或 1。写 0/1 的后果不是"芽整体消失"，而是**只有埋在头里的那截草根被身体盖掉**，
    /// 于是草看起来像浮在头顶上方而不是长在头里（0801 走查截图里的那一处）。
    ///
    /// 具体在前还是在后按**每个状态自己的元素顺序**判：设计包里 11 个状态把 bo/boline
    /// 排在 body 之后（草在前，草根那条渐尖的尾巴压在白色头顶上），只有 `sleep-2`
    /// 反过来。宿主是一个整体，所以只能整体跟随，做不到状态内穿插——好在 bo/boline
    /// 在每个状态里本来就是相邻的两层。
    private static let sproutFrontZ: CGFloat = 100
    private static let sproutBackZ: CGFloat = -0.5

    private func syncSproutLayer(stateID: String) {
        guard let elements = data.states[stateID]?.elements else { return }
        let boIndex = elements.firstIndex { Self.sproutElementIDs.contains($0.id) }
        let bodyIndex = elements.firstIndex { $0.id == "body" }
        guard let boIndex, let bodyIndex else {
            sproutNode.zPosition = Self.sproutFrontZ
            return
        }
        sproutNode.zPosition = boIndex < bodyIndex ? Self.sproutBackZ : Self.sproutFrontZ
    }

    // MARK: - Build

    /// Rebuilds every element for the current blend.
    ///
    /// During a transition both states' decorations must exist at once — one
    /// fading out, one fading in — so nodes are keyed by state *and* element and
    /// kept until neither state claims them.
    private func rebuild() {
        var live = Set<String>()
        syncSproutLayer(stateID: targetStateID)

        // 不在过渡中时只跑一遍：两个 stage 用同一个 key，跑两遍会让第二遍的
        // 「入场」淡入把已经就位的装饰重新压回 alpha 0。
        let stages: [(stateID: String, isOutgoing: Bool)] =
            currentStateID == targetStateID
                ? [(targetStateID, false)]
                : [(currentStateID, true), (targetStateID, false)]

        for stage in stages {
            guard let state = data.states[stage.stateID] else { continue }
            for (index, element) in state.elements.enumerated() {
                // Shared paths exist once and morph; only the target state's copy
                // is built so the two states do not stack a duplicate silhouette.
                if element.isShared && stage.isOutgoing { continue }
                let key = element.isShared ? "shared:\(element.id)" : "\(stage.stateID):\(element.id)"
                live.insert(key)
                update(
                    key: key,
                    element: element,
                    stateID: stage.stateID,
                    index: index,
                    isOutgoing: stage.isOutgoing,
                    isTransitioning: stages.count > 1
                )
            }
        }

        for (key, entry) in elementNodes where !live.contains(key) {
            entry.node.removeFromParent()
            elementNodes.removeValue(forKey: key)
        }
        reflectionNeedsSnapshot = true
    }

    private func update(
        key: String,
        element: PiboCharacterData.Element,
        stateID: String,
        index: Int,
        isOutgoing: Bool,
        isTransitioning: Bool
    ) {
        let isSprout = Self.sproutElementIDs.contains(element.id)
        let matrix = isSprout ? sproutTransform : bodyTransform
        let strokeScale = isSprout ? scale * Self.sproutSupersample : scale

        let rawPath: CGPath?
        if element.isShared, let morph = data.morph[element.id] {
            rawPath = interpolatedPath(id: element.id, morph: morph, transform: matrix)
        } else {
            rawPath = PiboCharacterGeometry.path(svgPathData: element.d, transform: matrix)
        }
        guard let rawPath else { return }

        let style = ElementStyle(element: element, strokeScale: strokeScale, lighting: lighting)
        let shape = (elementNodes[key]?.node) ?? makeShape(key: key, element: element, stateID: stateID, path: rawPath)
        let drawnPath = style.apply(to: shape, path: rawPath)
        projectionStyle?.apply(
            to: shape,
            elementID: element.id,
            scale: strokeScale,
            grainShader: projectionGrainShader
        )
        shape.zPosition = CGFloat(index)
        shape.alpha = element.idleOwned
            ? 0
            : decorationAlpha(element: element, isOutgoing: isOutgoing, isTransitioning: isTransitioning)
        if projectionStyle == nil, element.id == "bo" {
            configureBoContainer(path: drawnPath, element: element, contentNode: shape)
        }
        elementNodes[key] = ElementNode(
            node: shape,
            element: element,
            stateID: stateID,
            basePath: drawnPath
        )
    }

    private func makeShape(
        key: String,
        element: PiboCharacterData.Element,
        stateID: String,
        path: CGPath
    ) -> SKShapeNode {
        let shape = SKShapeNode()
        shape.isAntialiased = true
        let host: SKNode
        if projectionStyle == nil, Self.sproutElementIDs.contains(element.id) {
            host = boContentCrop
        } else {
            host = Self.sproutElementIDs.contains(element.id) ? sproutGeometryNode : bodyLayer
        }
        host.addChild(shape)
        elementNodes[key] = ElementNode(node: shape, element: element, stateID: stateID, basePath: path)
        return shape
    }

    // MARK: - Bo container

    /// Keeps the complete authored silhouette visible as an empty shell. Only
    /// the solid `bo` and its white inner line are clipped by energy progress.
    private func configureBoContainer(
        path: CGPath,
        element: PiboCharacterData.Element,
        contentNode: SKShapeNode
    ) {
        guard projectionStyle == nil else { return }
        let fill = UIColor(svgColor: element.fill, opacity: 1)
            .map(lighting.applied(to:))
            ?? UIColor(red: 32 / 255, green: 147 / 255, blue: 122 / 255, alpha: 1)
        let shellEdge = lighting.applied(to: UIColor(
            red: 235 / 255,
            green: 255 / 255,
            blue: 248 / 255,
            alpha: 1
        ))

        // `ElementStyle` already installed the production solid colour on the
        // cropped content node. The two shell nodes sit outside that crop.
        contentNode.fillColor = fill
        boGhostNode.path = path
        boGhostNode.fillColor = fill.withAlphaComponent(0.10)
        boGhostNode.strokeColor = .clear
        boGhostOutlineNode.path = path
        boGhostOutlineNode.fillColor = .clear
        boGhostOutlineNode.strokeColor = shellEdge.withAlphaComponent(0.58)
        boGhostOutlineNode.lineWidth = max(0.8 * scale * Self.sproutSupersample, 0.8)
        boGhostOutlineNode.lineCap = .round
        boGhostOutlineNode.lineJoin = .round

        boContainerShapeBounds = path.boundingBoxOfPath.insetBy(
            dx: -1.2 * scale * Self.sproutSupersample,
            dy: -1.2 * scale * Self.sproutSupersample
        )
        boContainerBounds = boContainerShapeBounds
        if let axis = sproutAxis {
            let attachment = bodyDesignPath.flatMap {
                PiboBoContainerProgress.bodyAttachmentPoint(from: axis.root, in: $0)
            } ?? axis.root
            let leafConnection = boDesignPath.flatMap {
                PiboBoContainerProgress.boInteriorConnectionPoint(
                    from: axis.root,
                    toward: axis.tip,
                    in: $0
                )
            } ?? axis.root
            boConnectionRootDesign = attachment
            boLeafRootDesign = axis.root
            boContainerRoot = attachment.applying(sproutTransform)
            boContainerLeafRoot = leafConnection.applying(sproutTransform)
            boContainerTip = axis.tip.applying(sproutTransform)
            configureBoRootConnector(fill: fill, source: contentNode)
        }
        applyBoRevealMask()
        syncBoContainerPresentation()
    }

    /// Makes the authored attachment readable against Pibo's white body. This
    /// remains translucent in the empty state; solid content still appears only
    /// when the ledger reports energy.
    private func configureBoRootConnector(fill: UIColor, source: SKShapeNode) {
        let liveLeafRoot = source.path.flatMap {
            PiboBoContainerProgress.boInteriorConnectionPoint(
                from: boContainerLeafRoot,
                toward: boContainerTip,
                in: $0,
                overlap: 4 * scale * Self.sproutSupersample
            )
        } ?? boContainerLeafRoot
        // Idle primitives rotate and reshape the authored leaf node. Resolve
        // its live endpoint into the common sprout host, while the connector's
        // body endpoint stays fixed inside Pibo. The connector therefore
        // bridges the two silhouettes instead of inheriting a transform that
        // could pull its body end away.
        let resolvedLeafRoot = sproutGeometryNode.convert(liveLeafRoot, from: source)
        let connection = CGVector(
            dx: resolvedLeafRoot.x - boContainerRoot.x,
            dy: resolvedLeafRoot.y - boContainerRoot.y
        )
        let connectionLength = hypot(connection.dx, connection.dy)
        guard connectionLength > 0.001 else {
            boRootGhostNode.path = nil
            boRootContentNode.path = nil
            boConnectorStartDesign = boConnectionRootDesign
            boConnectorEndDesign = boConnectionRootDesign
            boConnectorStart = boContainerRoot
            boConnectorEnd = boContainerRoot
            return
        }
        let unit = scale * Self.sproutSupersample
        // Both endpoints are resolved from the current frame's actual paths:
        // start is inside Pibo's body and end is inside bo. This remains true
        // for upright, lying, downward and every interpolated state.
        let start = boContainerRoot
        let end = resolvedLeafRoot
        boConnectorStart = start
        boConnectorEnd = end
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        let toDesign = sproutTransform.inverted()
        boConnectorStartDesign = start.applying(toDesign)
        boConnectorEndDesign = end.applying(toDesign)
        boRootGhostNode.path = path
        boRootGhostNode.fillColor = .clear
        boRootGhostNode.strokeColor = fill.withAlphaComponent(0.24)
        boRootGhostNode.lineWidth = max(2.2 * unit, 1)
        boRootGhostNode.lineCap = .round
        boRootContentNode.path = path
        boRootContentNode.fillColor = .clear
        boRootContentNode.strokeColor = fill
        boRootContentNode.lineWidth = max(2.2 * unit, 1)
        boRootContentNode.lineCap = .round
        boContainerBounds = boContainerShapeBounds.union(
            path.boundingBoxOfPath.insetBy(dx: -2.2 * unit, dy: -2.2 * unit)
        )
    }

    func setBoFillProgress(_ progress: CGFloat) {
        guard projectionStyle == nil else { return }
        boContainerProgress.set(progress)
        applyBoRevealMask()
        reflectionNeedsSnapshot = true
    }

    func animateBoFill(from start: CGFloat, to target: CGFloat, duration: TimeInterval) {
        guard projectionStyle == nil else { return }
        boContainerProgress.animate(from: start, to: target, duration: duration)
        applyBoRevealMask()
        reflectionNeedsSnapshot = true
    }

    func updateBoFill(deltaTime: TimeInterval, reduceMotion: Bool) {
        guard projectionStyle == nil else { return }
        if boContainerProgress.update(deltaTime: deltaTime, reduceMotion: reduceMotion) {
            applyBoRevealMask()
            reflectionNeedsSnapshot = true
        }
    }

    /// Idle primitives may rotate, scale, or reshape the solid `bo` node after
    /// the state rebuild. Mirror those presentation properties onto the shell so
    /// the empty container and injected content can never drift apart.
    func syncBoContainerPresentation() {
        guard projectionStyle == nil,
              let source = elementNodes["shared:bo"]?.node
        else { return }
        for shell in [boGhostNode, boGhostOutlineNode] {
            shell.path = source.path
            shell.position = source.position
            shell.zRotation = source.zRotation
            shell.xScale = source.xScale
            shell.yScale = source.yScale
            shell.alpha = source.alpha
            shell.isHidden = source.isHidden
        }
        // The crop grows from the fixed body attachment. The leaf moves inside
        // it; the connector itself is rebuilt between that attachment and the
        // leaf's live root every frame.
        boRevealMask.position = .zero
        boRevealMask.zRotation = 0
        boRevealMask.setScale(1)
        boRootGhostNode.position = .zero
        boRootGhostNode.zRotation = 0
        boRootGhostNode.setScale(1)
        boRootContentNode.position = .zero
        boRootContentNode.zRotation = 0
        boRootContentNode.setScale(1)
        boRootGhostNode.alpha = source.alpha
        boRootGhostNode.isHidden = source.isHidden
        boRootContentNode.alpha = source.alpha
        boRootContentNode.isHidden = source.isHidden
        boContainerShapeBounds = source.frame.insetBy(
            dx: -1.2 * scale * Self.sproutSupersample,
            dy: -1.2 * scale * Self.sproutSupersample
        )
        configureBoRootConnector(fill: source.fillColor, source: source)
        boGhostNode.zPosition = source.zPosition - 0.2
        boRootGhostNode.zPosition = source.zPosition - 0.1
        boRootContentNode.zPosition = source.zPosition - 0.1
        boGhostOutlineNode.zPosition = source.zPosition + 0.2
    }

    private func applyBoRevealMask() {
        guard projectionStyle == nil, !boContainerBounds.isNull else { return }
        let reveal = PiboBoContainerProgress.revealPath(
            in: boContainerBounds,
            root: boContainerRoot,
            tip: boContainerTip,
            progress: boContainerProgress.displayed
        )
        boContentCrop.isHidden = reveal == nil
        boRevealMask.path = reveal
        boRevealMask.fillColor = .white
    }

    /// Small verification surface used by renderer tests. It reports presentation
    /// state only and exposes no product thresholds.
    var boContainerPresentation: (progress: CGFloat, shellVisible: Bool, contentVisible: Bool, reveal: CGRect) {
        (
            boContainerProgress.displayed,
            boGhostNode.alpha > 0 && !boGhostNode.isHidden,
            !boContentCrop.isHidden,
            PiboBoContainerProgress.revealPath(
                in: boContainerBounds,
                root: boContainerRoot,
                tip: boContainerTip,
                progress: boContainerProgress.displayed
            )?.boundingBoxOfPath ?? .zero
        )
    }

    /// Verification surface: the warp host must remain at 1× while only its
    /// supersampled child returns the authored paths to their final size.
    var sproutGeometryScale: CGSize {
        CGSize(width: sproutGeometryNode.xScale, height: sproutGeometryNode.yScale)
    }

    /// Verification surface for the semantic body root and the authored leaf
    /// base. They differ only for poses whose generated metadata left a gap.
    var boConnectionDesign: (
        root: CGPoint,
        leafRoot: CGPoint,
        connectorStart: CGPoint,
        connectorEnd: CGPoint
    ) {
        (
            boConnectionRootDesign,
            boLeafRootDesign,
            boConnectorStartDesign,
            boConnectorEndDesign
        )
    }

    /// Verification surface for the final SpriteKit presentation, including
    /// per-state idle transforms and path wiggle. Both ends of the connector
    /// must still intersect the live body/bo silhouettes.
    var boPresentedConnectionIntersections: (body: Bool, bo: Bool) {
        guard let body = bodyPath(),
              let source = elementNodes["shared:bo"]?.node,
              let bo = source.path
        else { return (false, false) }
        let samples = 160
        var hitsBody = false
        var hitsBo = false
        for index in 0 ... samples {
            let amount = CGFloat(index) / CGFloat(samples)
            let point = CGPoint(
                x: boConnectorStart.x + (boConnectorEnd.x - boConnectorStart.x) * amount,
                y: boConnectorStart.y + (boConnectorEnd.y - boConnectorStart.y) * amount
            )
            if body.contains(contentNode.convert(point, from: boRootGhostNode)) {
                hitsBody = true
            }
            if bo.contains(source.convert(point, from: boRootGhostNode)) {
                hitsBo = true
            }
            if hitsBody, hitsBo { break }
        }
        return (hitsBody, hitsBo)
    }

    // MARK: - Idle access

    /// Resolves the design package's selector syntax (`#path-bo`,
    /// `#orphan-lefteye-default`) onto this runtime's element keys.
    func node(forSelector selector: String, stateID: String) -> SKShapeNode? {
        elementNodes[Self.key(forSelector: selector, stateID: stateID)]?.node
    }

    func basePath(forSelector selector: String, stateID: String) -> CGPath? {
        elementNodes[Self.key(forSelector: selector, stateID: stateID)]?.basePath
    }

    /// Design-space → node-space transform for the layer an element lives in.
    /// The sprout is built supersampled, so pivots and centres expressed in
    /// design coordinates need its transform, not the body's.
    func transform(forSelector selector: String) -> CGAffineTransform {
        let id = Self.elementID(forSelector: selector)
        return Self.sproutElementIDs.contains(id) ? sproutTransform : bodyTransform
    }

    func isSproutSelector(_ selector: String) -> Bool {
        Self.sproutElementIDs.contains(Self.elementID(forSelector: selector))
    }

    private static func elementID(forSelector selector: String) -> String {
        let token = selector.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if token.hasPrefix("path-") { return String(token.dropFirst("path-".count)) }
        return token
    }

    private static func key(forSelector selector: String, stateID: String) -> String {
        let token = selector.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if token.hasPrefix("path-") {
            return "shared:\(token.dropFirst("path-".count))"
        }
        // `orphan-<elementID>-<stateID>` — the element id itself can contain
        // dashes (`face-l-Vector376`), so strip the known affixes rather than
        // splitting on the separator.
        var id = token
        if id.hasPrefix("orphan-") { id = String(id.dropFirst("orphan-".count)) }
        if id.hasSuffix("-\(stateID)") { id = String(id.dropLast(stateID.count + 1)) }
        return "\(stateID):\(id)"
    }

    /// Where the sprout's root sits inside the warp box, and whether the leaf
    /// points down. The rig pins row zero to the root and softens toward the tip,
    /// so it needs both — `awake` hangs out of the coconut hole with its tip
    /// *below* its root, and without the flag it would bend from the wrong end.
    ///
    /// Measured against the effect node's own content bounds, because that is
    /// what `SKWarpGeometryGrid` normalises over.
    var sproutWarpAnchor: (pivotFraction: CGFloat, axisInverted: Bool)? {
        guard let axis = sproutAxis else { return nil }
        var bounds = CGRect.null
        for child in sproutNode.children { bounds = bounds.union(child.frame) }
        guard !bounds.isNull, bounds.width > 0 else { return nil }

        // The warp host is 1×; only its child geometry is supersampled.
        let matrix = bodyTransform
        let root = axis.root.applying(matrix)
        let tip = axis.tip.applying(matrix)
        return (
            pivotFraction: (root.x - bounds.minX) / bounds.width,
            axisInverted: root.y > tip.y
        )
    }

    /// Body silhouette in design units for the current blend. Y is down, as in
    /// the source artwork, so the character's ground line is `maxY`.
    var bodyDesignBounds: CGRect? {
        let bounds = bodyDesignPath?.boundingBoxOfPath ?? .null
        return bounds.isNull ? nil : bounds
    }

    var bodyDesignPath: CGPath? {
        guard let morph = data.morph["body"] else { return nil }
        return interpolatedPath(id: "body", morph: morph, transform: .identity)
    }

    var boDesignPath: CGPath? {
        guard let morph = data.morph["bo"] else { return nil }
        return interpolatedPath(id: "bo", morph: morph, transform: .identity)
    }

    /// Visible vector bounds in the root node's coordinate system. This is a
    /// verification surface for the authored 300×300 Figma artboards; scene
    /// placement must never infer a new per-state scale from these bounds.
    var renderedContentBounds: CGRect {
        var local = CGRect.null
        for entry in elementNodes.values
        where entry.node.alpha > 0.001 && Self.hasVisiblePaint(entry.element) {
            guard let path = entry.node.path else { continue }
            let frame = path.boundingBoxOfPath
            let corners = [
                CGPoint(x: frame.minX, y: frame.minY),
                CGPoint(x: frame.maxX, y: frame.minY),
                CGPoint(x: frame.minX, y: frame.maxY),
                CGPoint(x: frame.maxX, y: frame.maxY),
            ].map { contentNode.convert($0, from: entry.node) }
            for point in corners {
                local = local.union(CGRect(origin: point, size: .zero))
            }
        }
        guard !local.isNull else { return .null }
        let corners = [
            CGPoint(x: local.minX, y: local.minY),
            CGPoint(x: local.maxX, y: local.minY),
            CGPoint(x: local.minX, y: local.maxY),
            CGPoint(x: local.maxX, y: local.maxY),
        ].map { rootNode.convert($0, from: contentNode) }
        return corners.reduce(into: CGRect.null) { result, point in
            result = result.union(CGRect(origin: point, size: .zero))
        }
    }

    private static func hasVisiblePaint(_ element: PiboCharacterData.Element) -> Bool {
        let fill = element.fill?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let stroke = element.stroke?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasFill = fill != nil && fill != "none" && fill != "transparent"
        let hasStroke = stroke != nil
            && stroke != "none"
            && stroke != "transparent"
            && (element.strokeWidth ?? 0) > 0
        return hasFill || hasStroke
    }

    /// Stands the character on `footPoint` at a given body width.
    ///
    /// Placement is per **zone**, not per state: the states of a zone are already
    /// registered against each other inside their own 300×300 artboards, and
    /// ground ⇄ nest is a hard cut precisely because the two zones sit in
    /// completely different places. So the stage only supplies one anchor per
    /// zone, and the forest's existing, already-tuned `piboFootPoint` is exactly
    /// that anchor for the ground.
    func fit(bodyWidth targetWidth: CGFloat, footPoint: CGPoint) {
        guard let bounds = bodyDesignBounds, bounds.width > 0 else { return }
        setScale(targetWidth / bounds.width)
        let footLocal = CGPoint(x: bounds.midX, y: bounds.maxY).applying(bodyTransform)
        rootNode.position = CGPoint(x: footPoint.x - footLocal.x, y: footPoint.y - footLocal.y)
    }

    /// 闪亮登场的金光。强度由过渡驱动给出（快起慢收，自行消散）。
    func setGlow(colorHex: String?, intensity: CGFloat) {
        guard let colorHex,
              intensity > 0.002,
              let color = UIColor(svgColor: colorHex, opacity: 1),
              let body = bodyPath() else {
            if glowLayer.alpha != 0 { glowLayer.alpha = 0 }
            return
        }
        glowLayer.alpha = 1
        let width = 16 * scale
        glowOuter.path = body
        glowOuter.strokeColor = color.withAlphaComponent(0.30 * intensity)
        glowOuter.lineWidth = width
        glowOuter.glowWidth = width * 1.6
        glowInner.path = body
        glowInner.strokeColor = color.withAlphaComponent(0.55 * intensity)
        glowInner.lineWidth = width * 0.4
        glowInner.glowWidth = width * 0.7
    }

    // MARK: - Reflection source

    /// Texture-and-placement stand-in for the water reflection.
    ///
    /// `ForestReflectionProxy` mirrors an `SKSpriteNode` by sampling its texture,
    /// and a tree of shape nodes has no texture. So the character keeps a hidden
    /// sprite that carries a periodic snapshot of itself, handed to the
    /// projection with `treatsSourceAsInvisibleProxy: true` — the proxy supplies
    /// geometry and pixels while staying out of the main pass.
    let reflectionSource = SKSpriteNode()

    /// The snapshot only tracks *geometry* changes — a state change or a morph
    /// frame. Idle motion is a few points of sway, and the reflection is a dim,
    /// rippled mirror under water: paying a render-to-texture every frame to
    /// carry that would cost far more than it shows.
    private var reflectionNeedsSnapshot = true

    func refreshReflectionSnapshotIfNeeded(in view: SKView) {
        guard reflectionNeedsSnapshot else { return }
        reflectionNeedsSnapshot = false
        guard let texture = view.texture(from: contentNode) else { return }
        reflectionSource.texture = texture
        reflectionSource.size = texture.size()
        let frame = contentNode.calculateAccumulatedFrame()
        reflectionSource.position = CGPoint(x: frame.midX, y: frame.midY)
    }

    // MARK: - Idle transforms
    // Element paths are authored in the parent's coordinates with the node itself
    // at the origin, so "rotate about point P" becomes a rotation plus the
    // translation that pins P — the same trick for scaling and squashing. Doing
    // it this way keeps path data untouched, so idle motion and morphing can
    // never contend for the same property.

    /// The whole-body idle pose, written to the content node — the settle pulse
    /// sits above it, so the two compose instead of overwriting each other.
    ///
    /// It is one struct rather than four setters because the design engine
    /// writes a single CSS `transform` on the SVG root: breathing, the hop, the
    /// sway and the sigh all share it, and each is authored about a
    /// `transform-origin` that is the character's contact point (the engine's
    /// `BOTTOM_CENTER` default, or an explicit per-state `origin` — 11 of the 12
    /// states carry one). Scaling about the artboard centre instead slides the
    /// feet up and down with every breath.
    struct BodyTransform: Equatable {
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        /// Radians in SpriteKit's sense — the caller has already converted from
        /// the design frame's Y-down degrees.
        var rotation: CGFloat = 0
        /// Translation in **design units, Y-down**, so it can be written exactly
        /// as the source `translate(...)` is.
        var offset: CGPoint = .zero
        /// Pivot in design coordinates. `nil` = the engine's `BOTTOM_CENTER`.
        var origin: CGPoint?
    }

    func setBodyTransform(_ transform: BodyTransform) {
        let pivot = (transform.origin ?? Self.bottomCentre(of: designFrame))
            .applying(bodyTransform)
        contentNode.xScale = transform.scaleX
        contentNode.yScale = transform.scaleY
        contentNode.zRotation = transform.rotation
        // SKNode maps a child point p to `position + R·S·p`. Holding p = pivot
        // fixed is what makes the authored transform-origin mean the same thing
        // here as it does in the source.
        let scaled = CGPoint(x: pivot.x * transform.scaleX, y: pivot.y * transform.scaleY)
        let cosAngle = cos(transform.rotation)
        let sinAngle = sin(transform.rotation)
        let rotated = CGPoint(
            x: cosAngle * scaled.x - sinAngle * scaled.y,
            y: sinAngle * scaled.x + cosAngle * scaled.y
        )
        contentNode.position = CGPoint(
            x: contentRest.x + pivot.x - rotated.x + transform.offset.x * scale,
            y: contentRest.y + pivot.y - rotated.y - transform.offset.y * scale
        )
    }

    /// The design engine's default whole-body pivot (`BOTTOM_CENTER`, "50% 100%").
    static func bottomCentre(of frame: CGSize) -> CGPoint {
        CGPoint(x: frame.width / 2, y: frame.height)
    }

    func setRotation(_ angle: CGFloat, about anchor: CGPoint, for node: SKShapeNode) {
        node.zRotation = angle
        let cosA = cos(angle)
        let sinA = sin(angle)
        node.position = CGPoint(
            x: anchor.x - (cosA * anchor.x - sinA * anchor.y),
            y: anchor.y - (sinA * anchor.x + cosA * anchor.y)
        )
    }

    func setVerticalSquash(
        _ scale: CGFloat,
        originY designY: CGFloat?,
        for node: SKShapeNode,
        selector: String
    ) {
        let anchorY: CGFloat
        if let designY {
            anchorY = CGPoint(x: 0, y: designY).applying(transform(forSelector: selector)).y
        } else {
            anchorY = node.path?.boundingBoxOfPath.midY ?? 0
        }
        node.yScale = scale
        node.position = CGPoint(x: node.position.x, y: anchorY - scale * anchorY)
    }

    func setUniformScale(
        _ scale: CGFloat,
        pivot designPivot: [Double]?,
        selector: String,
        for node: SKShapeNode
    ) {
        let anchor: CGPoint
        if let designPivot, designPivot.count == 2 {
            anchor = CGPoint(x: designPivot[0], y: designPivot[1])
                .applying(transform(forSelector: selector))
        } else {
            let box = node.path?.boundingBoxOfPath ?? .zero
            anchor = CGPoint(x: box.midX, y: box.midY)
        }
        node.setScale(scale)
        node.position = CGPoint(x: anchor.x - scale * anchor.x, y: anchor.y - scale * anchor.y)
    }

    func setSparkleTransform(
        offset: CGPoint,
        rotation: CGFloat,
        scale: CGFloat,
        selector: String,
        for node: SKShapeNode
    ) {
        let matrix = transform(forSelector: selector)
        let box = node.path?.boundingBoxOfPath ?? .zero
        let anchor = CGPoint(x: box.midX, y: box.midY)
        node.zRotation = rotation
        node.setScale(scale)
        let cosA = cos(rotation) * scale
        let sinA = sin(rotation) * scale
        // Design Y points down; the transform's negative `d` carries the flip.
        let travel = CGPoint(x: offset.x * matrix.a, y: offset.y * matrix.d)
        node.position = CGPoint(
            x: anchor.x - (cosA * anchor.x - sinA * anchor.y) + travel.x,
            y: anchor.y - (sinA * anchor.x + cosA * anchor.y) + travel.y
        )
    }

    /// Resets everything the idle animator writes, so a state whose choreography
    /// does not mention an element cannot inherit the previous state's pose, and
    /// a path primitive whose gate has closed hands its outline back.
    ///
    /// Restoring from the stored base path is also what lets `setTransition`
    /// skip work when nothing changed: at rest the character costs one pass of
    /// transform resets instead of a full geometry rebuild.
    func resetIdleTransforms() {
        contentNode.xScale = 1
        contentNode.yScale = 1
        contentNode.zRotation = 0
        contentNode.position = contentRest
        for entry in elementNodes.values {
            entry.node.zRotation = 0
            entry.node.xScale = 1
            entry.node.yScale = 1
            entry.node.position = .zero
            entry.node.path = entry.basePath
            if let index = data.states[entry.stateID]?.elements.firstIndex(where: {
                $0.id == entry.element.id
            }) {
                entry.node.zPosition = CGFloat(index)
            }
        }
    }

    /// Decoration fade timings (SPEC §4). Leaving decorations at half opacity
    /// while they travel with the body looked wrong, which is why the exit is
    /// front-loaded to 22% and the entrance waits until the body is 85% there —
    /// arriving on the settle pulse instead of ahead of it.
    private func decorationAlpha(
        element: PiboCharacterData.Element,
        isOutgoing: Bool,
        isTransitioning: Bool
    ) -> CGFloat {
        guard isTransitioning, !element.isShared else { return element.opacity }
        let exit = CGFloat(data.transition.decorationExitFraction)
        let enterDelay = CGFloat(data.transition.decorationEnterDelayFraction)
        let enter = CGFloat(data.transition.decorationEnterFraction)

        let visibility: CGFloat
        if isOutgoing {
            // Fade out over the first `exit` of the transition.
            let t = exit > 0 ? min(1, progress / exit) : 1
            visibility = cos(t * .pi / 2)
        } else {
            // Hold hidden until the body is nearly there, then ease in.
            let t = enter > 0 ? min(1, max(0, (progress - enterDelay) / enter)) : 1
            visibility = easeOutBack(t)
        }
        return element.opacity * min(max(visibility, 0), 1)
    }

    private func easeOutBack(_ t: CGFloat) -> CGFloat {
        guard t > 0 else { return 0 }
        let c1: CGFloat = 1.70158
        let c3 = c1 + 1
        let u = t - 1
        return 1 + c3 * u * u * u + c1 * u * u
    }
}

private extension PiboVectorCharacter.ProjectionStyle {
    func apply(
        to shape: SKShapeNode,
        elementID: String,
        scale: CGFloat,
        grainShader: SKShader?
    ) {
        let bodyElements: Set<String> = ["body", "rightleg", "leftleg"]
        let hand = elementID.hasPrefix("lefthand") || elementID.hasPrefix("righthand")
        if bodyElements.contains(elementID) {
            shape.fillColor = bodyColor
            shape.fillShader = elementID == "body" ? grainShader : nil
        } else if hand {
            shape.fillColor = handColor
            shape.fillShader = nil
        }

        if bodyElements.contains(elementID) || elementID == "bo" {
            shape.strokeColor = outlineColor
            shape.lineWidth = outlineDesignWidth * scale
            shape.lineCap = .round
            shape.lineJoin = .round
        }
    }

    func makeGrainShader() -> SKShader {
        let shader = SKShader(source: """
        void main() {
            vec4 mask = texture2D(u_texture, v_tex_coord);
            vec2 cell = floor(v_tex_coord * vec2(72.0, 68.0));
            float noise = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
            float fleck = step(0.90, noise) * u_grain;
            vec3 paper = vec3(0.898, 0.898, 0.961);
            vec3 ink = vec3(0.141, 0.306, 0.263);
            vec3 color = mix(paper, ink, fleck);
            gl_FragColor = vec4(color * mask.a, mask.a);
        }
        """)
        shader.uniforms = [SKUniform(name: "u_grain", float: Float(paperGrain))]
        return shader
    }
}

/// Resolves an element's paint once so the per-frame path update stays cheap.
private struct ElementStyle {
    let fill: UIColor?
    let stroke: UIColor?
    let strokeWidth: CGFloat
    let lineCap: CGLineCap
    let lineJoin: CGLineJoin
    let angryGradientScale: CGFloat?
    /// Whether the stroke is converted to a filled outline before drawing.
    let outlinesStroke: Bool

    init(element: PiboCharacterData.Element, strokeScale: CGFloat, lighting: PiboCharacterLighting) {
        let rawFill = UIColor(svgColor: element.fill, opacity: 1).map(lighting.applied(to:))
        let rawStroke = UIColor(svgColor: element.stroke, opacity: 1).map(lighting.applied(to:))
        let width = (element.strokeWidth ?? 0) * strokeScale
        angryGradientScale = element.fill == "url(#angryShade)" ? strokeScale : nil
        lineCap = PiboCharacterGeometry.lineCap(element.lineCap)
        lineJoin = PiboCharacterGeometry.lineJoin(element.lineJoin)

        // A sub-point stroke is the shape SpriteKit's tessellating renderer
        // handles worst, and short segments mid-morph produce line-cap
        // artefacts. Interpolating the centreline and outlining the result keeps
        // the exact structural correspondence while handing over a filled sliver.
        if rawStroke != nil, width > 0, rawFill == nil {
            fill = rawStroke
            stroke = nil
            strokeWidth = width
            outlinesStroke = true
        } else {
            fill = rawFill
            stroke = rawStroke
            strokeWidth = width
            outlinesStroke = false
        }
    }

    /// Returns the path actually handed to the renderer, which is not always the
    /// path passed in — a stroked centreline is outlined first.
    @discardableResult
    func apply(to shape: SKShapeNode, path: CGPath) -> CGPath {
        if outlinesStroke {
            let outline = PiboCharacterGeometry.outlined(
                path,
                width: strokeWidth,
                lineCap: lineCap,
                lineJoin: lineJoin
            )
            shape.path = outline
            shape.fillColor = fill ?? .clear
            shape.fillShader = nil
            shape.strokeColor = .clear
            shape.lineWidth = 0
            return outline
        }
        shape.path = path
        if let angryGradientScale {
            shape.fillColor = .white
            shape.fillShader = Self.makeAngryGradientShader(
                pathBounds: path.boundingBoxOfPath,
                scale: angryGradientScale
            )
        } else {
            shape.fillColor = fill ?? .clear
            shape.fillShader = nil
        }
        shape.strokeColor = stroke ?? .clear
        shape.lineWidth = stroke == nil ? 0 : strokeWidth
        shape.lineCap = lineCap
        shape.lineJoin = lineJoin
        return path
    }

    /// The source artwork clips a blurred black ellipse to the angry body.
    /// `SKShapeNode` cannot parse its SVG `url(...)` paint, so this deterministic
    /// elliptical falloff preserves the same visible end state; without it the
    /// entire angry body becomes transparent.
    private static func makeAngryGradientShader(
        pathBounds: CGRect,
        scale: CGFloat
    ) -> SKShader {
        let source = """
        void main() {
            vec4 mask = texture2D(u_texture, v_tex_coord);
            vec2 point = vec2(
                u_min_x + v_tex_coord.x * u_width,
                u_min_y + v_tex_coord.y * u_height
            );
            vec2 ellipse = (point - vec2(u_center_x, u_center_y))
                / vec2(u_radius_x, u_radius_y);
            float mixAmount = smoothstep(0.1, 1.8, length(ellipse));
            vec3 color = vec3(mixAmount);
            gl_FragColor = vec4(color * mask.a, mask.a);
        }
        """
        let shader = SKShader(source: source)
        shader.uniforms = [
            SKUniform(name: "u_min_x", float: Float(pathBounds.minX)),
            SKUniform(name: "u_min_y", float: Float(pathBounds.minY)),
            SKUniform(name: "u_width", float: Float(pathBounds.width)),
            SKUniform(name: "u_height", float: Float(pathBounds.height)),
            SKUniform(name: "u_center_x", float: Float((151.9 - 150) * scale)),
            SKUniform(name: "u_center_y", float: Float((150 - 63.1) * scale)),
            SKUniform(name: "u_radius_x", float: Float(101.506 * scale)),
            SKUniform(name: "u_radius_y", float: Float(92.6974 * scale)),
        ]
        return shader
    }
}

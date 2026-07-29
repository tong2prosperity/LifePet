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
    /// Container for the settle pulse. The pulse must not touch path data, so it
    /// rides a node above the geometry (SPEC §5).
    let rootNode = SKNode()

    /// The 毛. Lives in its own effect node so the existing six-bone spring rig
    /// can keep driving it through `SKWarpGeometryGrid` while the paths inside
    /// morph. The warp deforms a render mesh and never reads path data, so the
    /// two systems compose without knowing about each other.
    let sproutNode = SKEffectNode()

    /// Scaling happens about a node's own origin, and the design package anchors
    /// the settle pulse at 50% / 80% — near Pibo's feet, so the "biu" reads as
    /// landing rather than as the whole body breathing. This node sits at that
    /// anchor with the geometry offset back out of it.
    private let pulseNode = SKNode()
    private let contentNode = SKNode()
    private let bodyLayer = SKNode()
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
    private var elementNodes: [String: ElementNode] = [:]
    private var scale: CGFloat = 1
    private var lighting: PiboCharacterLighting = .neutral
    /// Where the content node sits when nothing is hopping.
    private var contentRest: CGPoint = .zero
    private(set) var currentStateID: String
    private var targetStateID: String
    private var progress: CGFloat = 0

    init?(stateID: String = "default", data: PiboCharacterData? = PiboCharacterData.shared) {
        guard let data, data.states[stateID] != nil else { return nil }
        self.data = data
        currentStateID = stateID
        targetStateID = stateID
        rootNode.addChild(pulseNode)
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
        contentNode.addChild(bodyLayer)
        sproutNode.shouldEnableEffects = true
        sproutNode.shouldRasterize = false
        contentNode.addChild(sproutNode)
        // 挂在 rootNode 而不是 contentNode 上：快照拍的是 contentNode，代理本身
        // 必须留在镜头外，否则会把上一帧的自己拍进去。
        reflectionSource.isHidden = true
        rootNode.addChild(reflectionSource)
        applyPulseAnchor()
    }

    /// Damped scale about the design package's anchor, applied to the container
    /// rather than to path data — which is why it can never introduce the spikes
    /// that killed the overshoot-easing experiment.
    func setSettleScale(_ value: CGFloat) {
        pulseNode.setScale(value)
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
        pulseNode.position = offset
        contentRest = CGPoint(x: -offset.x, y: -offset.y)
        contentNode.position = contentRest
    }

    // MARK: - Geometry frame

    /// `pointsPerDesignUnit` maps the 300-unit design frame onto the stage. The
    /// character is centred on `rootNode`'s origin.
    func setScale(_ pointsPerDesignUnit: CGFloat) {
        guard pointsPerDesignUnit != scale else { return }
        scale = pointsPerDesignUnit
        sproutNode.setScale(1 / Self.sproutSupersample)
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
        currentStateID = from
        targetStateID = to
        self.progress = clamped
        rebuild()
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

    /// The body silhouette in `rootNode`'s coordinates. Feeds hit testing and the
    /// weather system's impact sampling, so the visible shape and the
    /// interactive shape cannot drift apart.
    func bodyPath() -> CGPath? {
        guard let morph = data.morph["body"] else { return nil }
        return PiboCharacterGeometry.interpolatedPath(
            for: morph,
            from: currentStateID,
            to: targetStateID,
            progress: progress,
            transform: bodyTransform
        )
    }

    func sproutPath() -> CGPath? {
        guard let morph = data.morph["bo"] else { return nil }
        return PiboCharacterGeometry.interpolatedPath(
            for: morph,
            from: currentStateID,
            to: targetStateID,
            progress: progress,
            transform: bodyTransform
        )
    }

    // MARK: - Build

    /// Rebuilds every element for the current blend.
    ///
    /// During a transition both states' decorations must exist at once — one
    /// fading out, one fading in — so nodes are keyed by state *and* element and
    /// kept until neither state claims them.
    private func rebuild() {
        var live = Set<String>()

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
            rawPath = PiboCharacterGeometry.interpolatedPath(
                for: morph,
                from: currentStateID,
                to: targetStateID,
                progress: progress,
                transform: matrix
            )
        } else {
            rawPath = PiboCharacterGeometry.path(svgPathData: element.d, transform: matrix)
        }
        guard let rawPath else { return }

        let style = ElementStyle(element: element, strokeScale: strokeScale, lighting: lighting)
        let shape = (elementNodes[key]?.node) ?? makeShape(key: key, element: element, stateID: stateID, path: rawPath)
        let drawnPath = style.apply(to: shape, path: rawPath)
        shape.zPosition = CGFloat(index)
        shape.alpha = element.idleOwned
            ? 0
            : decorationAlpha(element: element, isOutgoing: isOutgoing, isTransitioning: isTransitioning)
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
        let host: SKNode = Self.sproutElementIDs.contains(element.id) ? sproutNode : bodyLayer
        host.addChild(shape)
        elementNodes[key] = ElementNode(node: shape, element: element, stateID: stateID, basePath: path)
        return shape
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

        let matrix = sproutTransform
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
        guard let morph = data.morph["body"],
              let path = PiboCharacterGeometry.interpolatedPath(
                  for: morph,
                  from: currentStateID,
                  to: targetStateID,
                  progress: progress,
                  transform: .identity
              ) else { return nil }
        let bounds = path.boundingBoxOfPath
        return bounds.isNull ? nil : bounds
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
        reflectionSource.position = rootNode.convert(
            CGPoint(x: frame.midX, y: frame.midY),
            from: pulseNode
        )
    }

    // MARK: - Idle transforms
    // Element paths are authored in the parent's coordinates with the node itself
    // at the origin, so "rotate about point P" becomes a rotation plus the
    // translation that pins P — the same trick for scaling and squashing. Doing
    // it this way keeps path data untouched, so idle motion and morphing can
    // never contend for the same property.

    /// Whole-body breathing. Written to the content node, which the settle pulse
    /// sits above — the two compose instead of overwriting each other.
    func setBreath(x: CGFloat, y: CGFloat) {
        contentNode.xScale = x
        contentNode.yScale = y
    }

    func setHopOffset(_ dy: CGFloat) {
        contentNode.position = CGPoint(x: contentRest.x, y: contentRest.y + dy)
    }

    func setBodyRotation(_ angle: CGFloat) {
        contentNode.zRotation = angle
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
        rotationDegrees: CGFloat,
        scale: CGFloat,
        selector: String,
        for node: SKShapeNode
    ) {
        let matrix = transform(forSelector: selector)
        let box = node.path?.boundingBoxOfPath ?? .zero
        let anchor = CGPoint(x: box.midX, y: box.midY)
        let angle = rotationDegrees * .pi / 180
        node.zRotation = angle
        node.setScale(scale)
        let cosA = cos(angle) * scale
        let sinA = sin(angle) * scale
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

/// Resolves an element's paint once so the per-frame path update stays cheap.
private struct ElementStyle {
    let fill: UIColor?
    let stroke: UIColor?
    let strokeWidth: CGFloat
    let lineCap: CGLineCap
    let lineJoin: CGLineJoin
    /// Whether the stroke is converted to a filled outline before drawing.
    let outlinesStroke: Bool

    init(element: PiboCharacterData.Element, strokeScale: CGFloat, lighting: PiboCharacterLighting) {
        let rawFill = UIColor(svgColor: element.fill, opacity: 1).map(lighting.applied(to:))
        let rawStroke = UIColor(svgColor: element.stroke, opacity: 1).map(lighting.applied(to:))
        let width = (element.strokeWidth ?? 0) * strokeScale
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
            shape.strokeColor = .clear
            shape.lineWidth = 0
            return outline
        }
        shape.path = path
        shape.fillColor = fill ?? .clear
        shape.strokeColor = stroke ?? .clear
        shape.lineWidth = stroke == nil ? 0 : strokeWidth
        shape.lineCap = lineCap
        shape.lineJoin = lineJoin
        return path
    }
}

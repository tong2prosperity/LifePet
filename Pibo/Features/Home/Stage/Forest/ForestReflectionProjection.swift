import CoreGraphics
import simd
import SpriteKit

/// Art-directed planar reflection used by the portrait forest.
///
/// The source artwork is authored in the 393×852 Figma projection. Rather than
/// applying a screen-space `yScale = -1`, each texture is sampled by a small
/// mesh whose vertices are mirrored from an authored water contact point and
/// then compressed toward the viewer. This keeps every reflected object on the
/// same perspective while remaining a normal SpriteKit draw.
enum ForestReflectionProjection {
    static let designCenterX: CGFloat = ForestSceneManifest.designSize.width / 2
    static let farWaterY: CGFloat = ForestSceneManifest.river.frame.minY
    static let nearWaterY: CGFloat = ForestSceneManifest.designSize.height

    static let columns = 3
    static let rows = 4
    static let vertexCount = (columns + 1) * (rows + 1)
    static let sourcePositions: [SIMD2<Float>] = {
        var positions: [SIMD2<Float>] = []
        positions.reserveCapacity(vertexCount)
        for row in 0 ... rows {
            let v = Float(row) / Float(rows)
            for column in 0 ... columns {
                let u = Float(column) / Float(columns)
                positions.append(SIMD2(u, v))
            }
        }
        return positions
    }()

    struct Style: Equatable {
        var verticalCompression: CGFloat
        var tipWidthScale: CGFloat
        var outwardDrift: CGFloat
        var rippleStrength: CGFloat

        static let strong = Style(
            verticalCompression: 0.52,
            tipWidthScale: 0.72,
            outwardDrift: 0.08,
            rippleStrength: 1
        )
    }

    enum MotionResponse: Equatable {
        /// Recompute the mirrored position against a fixed water contact. This
        /// remains appropriate for static trees and the character.
        case mirrored
        /// Keep the authored rest-pose projection, then transfer live vertex
        /// deformation in the same visual direction. Interactive foliage uses
        /// this so dragging a leaf down also moves its reflection down.
        case followSourceDeformation
    }

    static func destination(
        for source: CGPoint,
        contact: CGPoint,
        sourceHeight: CGFloat,
        style: Style
    ) -> CGPoint {
        let height = max(sourceHeight, 1)
        let normalizedHeight = min(max((contact.y - source.y) / height, 0), 1)
        let reflectedDepth = height
            * (style.verticalCompression * normalizedHeight)
            / (1 + 0.35 * normalizedHeight)

        let widthScale = 1 - (1 - style.tipWidthScale) * normalizedHeight
        let centerDrift = (contact.x - designCenterX)
            * style.outwardDrift
            * normalizedHeight
        return CGPoint(
            x: contact.x + centerDrift + (source.x - contact.x) * widthScale,
            y: contact.y + reflectedDepth
        )
    }

    static func destination(
        for source: CGPoint,
        restingAt restSource: CGPoint,
        contact: CGPoint,
        sourceHeight: CGFloat,
        style: Style,
        motionResponse: MotionResponse
    ) -> CGPoint {
        let projectionSource = motionResponse == .followSourceDeformation
            ? restSource
            : source
        var destination = destination(
            for: projectionSource,
            contact: contact,
            sourceHeight: sourceHeight,
            style: style
        )
        guard motionResponse == .followSourceDeformation else { return destination }

        let normalizedHeight = min(max(
            (contact.y - projectionSource.y) / max(sourceHeight, 1),
            0
        ), 1)
        let widthScale = 1 - (1 - style.tipWidthScale) * normalizedHeight
        destination.x += (source.x - restSource.x) * widthScale
        destination.y += (source.y - restSource.y) * style.verticalCompression
        return destination
    }
}

/// One live texture proxy inside the river crop. The proxy itself spans the
/// scene; its small warp mesh moves only the sampled texture area into the
/// reflected destination. Values outside 0...1 are valid SKWarp coordinates.
final class ForestReflectionProxy {
    let source: SKSpriteNode
    let reflected: SKSpriteNode

    let contactPoint: CGPoint
    let projectionHeight: CGFloat
    let baseAlpha: CGFloat

    private let sourceVRange: ClosedRange<CGFloat>
    private let motionResponse: ForestReflectionProjection.MotionResponse
    private let geometryIsStatic: Bool
    private let treatsSourceAsInvisibleProxy: Bool
    private var lastTexture: SKTexture?
    private var lastSceneSize: CGSize = .zero
    private var lastStyle: ForestReflectionProjection.Style?
    private var lastSourceGeometry: SourceGeometry?
    private var lastHidden: Bool?
    private var lastAlpha: CGFloat?
    private var lastHeightRange: ClosedRange<Float>?
    private var lastRipplePhase: Float?
    private var lastRippleStrength: Float?
    private var lastRippleScale: Float?
    private var lastRippleDetail: Float?
    private var restSourceDesignPositions: [CGPoint] = []
    private var destinationPositions: [SIMD2<Float>] = []

    private struct SourceGeometry: Equatable {
        let size: CGSize
        let anchorPoint: CGPoint
        let origin: CGPoint
        let xAxis: CGPoint
        let yAxis: CGPoint
    }

    init(
        source: SKSpriteNode,
        contactPoint: CGPoint,
        projectionHeight: CGFloat,
        sourceVRange: ClosedRange<CGFloat> = 0 ... 1,
        baseAlpha: CGFloat,
        zPosition: CGFloat,
        motionResponse: ForestReflectionProjection.MotionResponse = .mirrored,
        geometryIsStatic: Bool = false,
        treatsSourceAsInvisibleProxy: Bool = false
    ) {
        self.source = source
        self.contactPoint = contactPoint
        self.projectionHeight = max(projectionHeight, 1)
        self.sourceVRange = sourceVRange
        self.baseAlpha = baseAlpha
        self.motionResponse = motionResponse
        self.geometryIsStatic = geometryIsStatic
        self.treatsSourceAsInvisibleProxy = treatsSourceAsInvisibleProxy

        let texture = Self.croppedTexture(source.texture, vRange: sourceVRange)
        reflected = SKSpriteNode(texture: texture)
        reflected.anchorPoint = .zero
        reflected.position = .zero
        reflected.zPosition = zPosition
        reflected.blendMode = .alpha
        reflected.shader = Self.makeShader()
        lastTexture = source.texture
        restSourceDesignPositions.reserveCapacity(ForestReflectionProjection.vertexCount)
        destinationPositions.reserveCapacity(ForestReflectionProjection.vertexCount)
    }

    func update(
        in target: SKNode,
        sceneSize: CGSize,
        mapper: ForestLayoutMapper,
        phase: CGFloat,
        style: ForestReflectionProjection.Style,
        intensity: CGFloat,
        dayPhaseMultiplier: CGFloat,
        lowPower: Bool,
        inheritedVisible: Bool = true
    ) {
        let textureChanged = source.texture !== lastTexture
        if textureChanged {
            reflected.texture = Self.croppedTexture(source.texture, vRange: sourceVRange)
            lastTexture = source.texture
        }

        if reflected.size != sceneSize { reflected.size = sceneSize }
        let hidden = !inheritedVisible || !sourceHierarchyVisible || source.texture == nil
        if lastHidden != hidden {
            reflected.isHidden = hidden
            lastHidden = hidden
        }
        let sourceAlpha = treatsSourceAsInvisibleProxy ? 1 : source.alpha
        let alpha = baseAlpha * intensity * dayPhaseMultiplier * sourceAlpha
        if lastAlpha != alpha {
            reflected.alpha = alpha
            lastAlpha = alpha
        }
        guard !hidden, sceneSize.width > 1, sceneSize.height > 1 else { return }

        updateRippleUniforms(
            phase: Float(phase),
            strength: Float(style.rippleStrength),
            scale: Float(mapper.scale / sceneSize.width),
            lowPower: lowPower
        )

        let sceneChanged = sceneSize != lastSceneSize
        if sceneChanged {
            restSourceDesignPositions.removeAll(keepingCapacity: true)
        }
        let sourceGeometry = geometryIsStatic && lastSourceGeometry != nil && !sceneChanged
            ? lastSourceGeometry!
            : captureSourceGeometry(in: target)
        let geometryChanged = lastSourceGeometry != sourceGeometry
        guard reflected.warpGeometry == nil
                || textureChanged
                || sceneChanged
                || lastStyle != style
                || (!geometryIsStatic && geometryChanged) else { return }

        lastSceneSize = sceneSize
        lastStyle = style
        lastSourceGeometry = sourceGeometry

        destinationPositions.removeAll(keepingCapacity: true)

        var minHeight: CGFloat = 1
        var maxHeight: CGFloat = 0
        for row in 0 ... ForestReflectionProjection.rows {
            let v = CGFloat(row) / CGFloat(ForestReflectionProjection.rows)
            let originalV = sourceVRange.lowerBound
                + v * (sourceVRange.upperBound - sourceVRange.lowerBound)
            for column in 0 ... ForestReflectionProjection.columns {
                let u = CGFloat(column) / CGFloat(ForestReflectionProjection.columns)
                let local = CGPoint(
                    x: (u - source.anchorPoint.x) * source.size.width,
                    y: (originalV - source.anchorPoint.y) * source.size.height
                )
                let targetPoint = source.convert(local, to: target)
                let sourceDesign = mapper.designPoint(targetPoint)
                let vertexIndex = row * (ForestReflectionProjection.columns + 1) + column
                if restSourceDesignPositions.count <= vertexIndex {
                    restSourceDesignPositions.append(sourceDesign)
                }
                let restSourceDesign = restSourceDesignPositions[vertexIndex]
                let projectionSource = motionResponse == .followSourceDeformation
                    ? restSourceDesign
                    : sourceDesign
                let normalizedHeight = min(max(
                    (contactPoint.y - projectionSource.y) / projectionHeight,
                    0
                ), 1)
                minHeight = min(minHeight, normalizedHeight)
                maxHeight = max(maxHeight, normalizedHeight)

                let reflectedDesign = ForestReflectionProjection.destination(
                    for: sourceDesign,
                    restingAt: restSourceDesign,
                    contact: contactPoint,
                    sourceHeight: projectionHeight,
                    style: style,
                    motionResponse: motionResponse
                )
                let reflectedPoint = mapper.point(reflectedDesign)
                destinationPositions.append(SIMD2(
                    Float(reflectedPoint.x / sceneSize.width),
                    Float(reflectedPoint.y / sceneSize.height)
                ))
            }
        }

        if let grid = reflected.warpGeometry as? SKWarpGeometryGrid {
            reflected.warpGeometry = grid.replacingByDestinationPositions(
                positions: destinationPositions
            )
        } else {
            reflected.warpGeometry = SKWarpGeometryGrid(
                columns: ForestReflectionProjection.columns,
                rows: ForestReflectionProjection.rows,
                sourcePositions: ForestReflectionProjection.sourcePositions,
                destinationPositions: destinationPositions
            )
        }
        let heightRange = Float(minHeight) ... Float(maxHeight)
        if lastHeightRange != heightRange {
            reflected.shader?.uniformNamed("u_height_min")?.floatValue = heightRange.lowerBound
            reflected.shader?.uniformNamed("u_height_max")?.floatValue = heightRange.upperBound
            lastHeightRange = heightRange
        }
    }

    private func captureSourceGeometry(in target: SKNode) -> SourceGeometry {
        SourceGeometry(
            size: source.size,
            anchorPoint: source.anchorPoint,
            origin: source.convert(.zero, to: target),
            xAxis: source.convert(CGPoint(x: 1, y: 0), to: target),
            yAxis: source.convert(CGPoint(x: 0, y: 1), to: target)
        )
    }

    private func updateRippleUniforms(
        phase: Float,
        strength: Float,
        scale: Float,
        lowPower: Bool
    ) {
        let detail: Float = lowPower ? 0 : 1
        if lastRipplePhase != phase {
            reflected.shader?.uniformNamed("u_ripple_phase")?.floatValue = phase
            lastRipplePhase = phase
        }
        if lastRippleStrength != strength {
            reflected.shader?.uniformNamed("u_ripple_strength")?.floatValue = strength
            lastRippleStrength = strength
        }
        if lastRippleScale != scale {
            reflected.shader?.uniformNamed("u_ripple_scale")?.floatValue = scale
            lastRippleScale = scale
        }
        if lastRippleDetail != detail {
            reflected.shader?.uniformNamed("u_ripple_detail")?.floatValue = detail
            lastRippleDetail = detail
        }
    }

    private var sourceHierarchyVisible: Bool {
        // A proxied source is deliberately invisible: it exists only to carry a
        // texture and a placement for something drawn by other means (the vector
        // character is a tree of shape nodes and has no texture of its own).
        // Its own hidden/alpha state therefore says nothing about whether the
        // reflection should show — start the walk at its parent.
        var node: SKNode? = treatsSourceAsInvisibleProxy ? source.parent : source
        while let current = node {
            if current.isHidden || current.alpha <= 0 { return false }
            node = current.parent
        }
        return true
    }

    private static func croppedTexture(
        _ texture: SKTexture?,
        vRange: ClosedRange<CGFloat>
    ) -> SKTexture? {
        guard let texture else { return nil }
        let lower = min(max(vRange.lowerBound, 0), 1)
        let upper = min(max(vRange.upperBound, lower), 1)
        guard lower > 0 || upper < 1 else { return texture }
        return SKTexture(
            rect: CGRect(x: 0, y: lower, width: 1, height: upper - lower),
            in: texture
        )
    }

    private static func makeShader() -> SKShader {
        let shader = SKShader(fileNamed: "ForestReflection.fsh")
        shader.addUniform(SKUniform(name: "u_height_min", float: 0))
        shader.addUniform(SKUniform(name: "u_height_max", float: 1))
        shader.addUniform(SKUniform(name: "u_ripple_phase", float: 0))
        shader.addUniform(SKUniform(name: "u_ripple_strength", float: 1))
        shader.addUniform(SKUniform(name: "u_ripple_scale", float: Float(1 / ForestSceneManifest.designSize.width)))
        shader.addUniform(SKUniform(name: "u_ripple_detail", float: 1))
        return shader
    }
}

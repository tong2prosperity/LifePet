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

    static let columns = 4
    static let rows = 6
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

    static func destination(
        for source: CGPoint,
        contact: CGPoint,
        sourceHeight: CGFloat,
        phase: CGFloat,
        style: Style,
        lowPower: Bool
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
        var destination = CGPoint(
            x: contact.x + centerDrift + (source.x - contact.x) * widthScale,
            y: contact.y + reflectedDepth
        )

        let waterDepth = min(max(
            (destination.y - farWaterY) / max(nearWaterY - farWaterY, 1),
            0
        ), 1)
        let amplitude = (0.6 + 1.8 * waterDepth)
            * style.rippleStrength
            * (lowPower ? 0.52 : 1)
        let broad = sin(waterDepth * 13.2 + source.x * 0.018 - phase * 5.7)
        let fine = lowPower
            ? 0
            : sin(waterDepth * 31.0 + source.x * 0.041 - phase * 10.4) * 0.34
        destination.x += (broad + fine) * amplitude
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
    private var lastTexture: SKTexture?
    private var destinationPositions: [SIMD2<Float>] = []

    init(
        source: SKSpriteNode,
        contactPoint: CGPoint,
        projectionHeight: CGFloat,
        sourceVRange: ClosedRange<CGFloat> = 0 ... 1,
        baseAlpha: CGFloat,
        zPosition: CGFloat
    ) {
        self.source = source
        self.contactPoint = contactPoint
        self.projectionHeight = max(projectionHeight, 1)
        self.sourceVRange = sourceVRange
        self.baseAlpha = baseAlpha

        let texture = Self.croppedTexture(source.texture, vRange: sourceVRange)
        reflected = SKSpriteNode(texture: texture)
        reflected.anchorPoint = .zero
        reflected.position = .zero
        reflected.zPosition = zPosition
        reflected.blendMode = .alpha
        reflected.shader = Self.makeShader()
        lastTexture = source.texture
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
        if source.texture !== lastTexture {
            reflected.texture = Self.croppedTexture(source.texture, vRange: sourceVRange)
            lastTexture = source.texture
        }

        reflected.size = sceneSize
        reflected.isHidden = !inheritedVisible || !sourceHierarchyVisible || source.texture == nil
        reflected.alpha = baseAlpha * intensity * dayPhaseMultiplier * source.alpha
        guard !reflected.isHidden, sceneSize.width > 1, sceneSize.height > 1 else { return }

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
                let normalizedHeight = min(max(
                    (contactPoint.y - sourceDesign.y) / projectionHeight,
                    0
                ), 1)
                minHeight = min(minHeight, normalizedHeight)
                maxHeight = max(maxHeight, normalizedHeight)

                let reflectedDesign = ForestReflectionProjection.destination(
                    for: sourceDesign,
                    contact: contactPoint,
                    sourceHeight: projectionHeight,
                    phase: phase,
                    style: style,
                    lowPower: lowPower
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
        reflected.shader?.uniformNamed("u_height_min")?.floatValue = Float(minHeight)
        reflected.shader?.uniformNamed("u_height_max")?.floatValue = Float(maxHeight)
    }

    private var sourceHierarchyVisible: Bool {
        var node: SKNode? = source
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
        return shader
    }
}

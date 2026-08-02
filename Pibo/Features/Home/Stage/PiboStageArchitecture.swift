import SpriteKit
import SwiftUI
import UIKit

/// Stable node slots owned by the stage coordinator. Renderers populate these
/// slots but never add permanent nodes directly to the scene root.
struct PiboStageThemeLayers {
    let background: SKNode
    let foreground: SKNode
    let atmosphere: SKNode
}

final class PiboThemeRendererContext {
    let layers: PiboStageThemeLayers
    weak var scene: SKScene?
    weak var characterRoot: SKNode?
    weak var characterHead: SKSpriteNode?
    var characterBody: () -> SKNode?
    var applyCharacterShader: (SKShader?) -> Void

    init(
        layers: PiboStageThemeLayers,
        scene: SKScene,
        characterRoot: SKNode,
        characterHead: SKSpriteNode,
        characterBody: @escaping () -> SKNode?,
        applyCharacterShader: @escaping (SKShader?) -> Void
    ) {
        self.layers = layers
        self.scene = scene
        self.characterRoot = characterRoot
        self.characterHead = characterHead
        self.characterBody = characterBody
        self.applyCharacterShader = applyCharacterShader
    }
}

struct PiboNodePlacement: Equatable {
    var position: CGPoint
    var size: CGSize
}

struct PiboCharacterPlacement: Equatable {
    var body: PiboNodePlacement
    var head: PiboNodePlacement?
    var overhead: PiboNodePlacement?
    var groundLineY: CGFloat
    var characterZ: CGFloat
    var overheadZ: CGFloat
    var weatherBackZ: CGFloat
    var usesCanonicalMotion: Bool
}

/// A renderer-provided precipitation target. The weather system owns visuals;
/// a theme optionally reacts when the impact is emitted (for example, a leaf
/// receives a small impulse).
struct ThemePrecipitationImpact {
    let point: CGPoint
    var splashScale: CGFloat
    var flatten: CGFloat
    var reaction: (() -> Void)? = nil
}

#if DEBUG
/// Optional water-renderer capability used by Water Lab. Keeping it separate
/// prevents water concepts from leaking into every production theme renderer.
struct WaterDebugTuning: Equatable {
    var speed: Double
    var rippleStrength: Double
    var highlightStrength: Double
    var reflectionIntensity: Double
    var reflectionCompression: Double
    var reflectionTipScale: Double
    var showMask: Bool

    var sanitized: WaterDebugTuning {
        WaterDebugTuning(
            speed: min(max(speed, 0), 1.4),
            rippleStrength: min(max(rippleStrength, 0), 1.25),
            highlightStrength: min(max(highlightStrength, 0), 1.3),
            reflectionIntensity: min(max(reflectionIntensity, 0), 1.6),
            reflectionCompression: min(max(reflectionCompression, 0.25), 0.85),
            reflectionTipScale: min(max(reflectionTipScale, 0.45), 1),
            showMask: showMask
        )
    }
}

protocol WaterDebugTunable: AnyObject {
    func applyWaterDebugTuning(_ tuning: WaterDebugTuning)
}
#endif

/// Plug-in boundary for a production home theme. SpriteKit/UIKit work remains
/// MainActor-isolated by the app target's default isolation.
protocol PiboThemeRenderer: AnyObject {
    var themeID: String { get }
    var wind: StageWind { get }

    func install(context: PiboThemeRendererContext, sceneSize: CGSize)
    func teardown()
    func layout(sceneSize: CGSize)
    func apply(environment: PiboStageEnvironment)
    func apply(renderPolicy: PiboThemeRenderPolicy)
    /// 用 `bo` 换来的物件。主题自己决定怎么画、画不画得了 —— 没有落位的物件
    /// （美术还没到）应当安静跳过，而不是画一个占位方块到用户的森林里。
    func apply(unlockedOrnaments: Set<PiboOrnament.ID>)
    func update(time: TimeInterval, deltaTime: TimeInterval, reduceMotion: Bool)
    func didEvaluateActions()

    func characterPlacement(
        theme: PiboTheme,
        growth: PiboGrowthStage,
        headNaturalSize: CGSize?,
        overheadNaturalSize: CGSize?,
        sceneSize: CGSize
    ) -> PiboCharacterPlacement

    func beginInteraction(at point: CGPoint, timestamp: TimeInterval) -> Bool
    func moveInteraction(to point: CGPoint, timestamp: TimeInterval)
    func endInteraction(at point: CGPoint, timestamp: TimeInterval, cancelled: Bool)
    func precipitationImpact(in scene: SKScene) -> ThemePrecipitationImpact?
}

extension PiboThemeRenderer {
    func didEvaluateActions() {}
    func apply(unlockedOrnaments: Set<PiboOrnament.ID>) {}
    func beginInteraction(at point: CGPoint, timestamp: TimeInterval) -> Bool { false }
    func moveInteraction(to point: CGPoint, timestamp: TimeInterval) {}
    func endInteraction(at point: CGPoint, timestamp: TimeInterval, cancelled: Bool) {}
}

struct PiboThemeRegistration {
    let theme: PiboTheme
    let makeRenderer: () -> any PiboThemeRenderer
}

/// The sole runtime catalog. Adding a production theme extends this table; the
/// stage coordinator and selection state remain closed to theme-specific code.
enum PiboThemeCatalog {
    static let registrations: [PiboThemeRegistration] = {
        let values = [
            PiboThemeRegistration(theme: .forest) { ForestThemeRenderer() },
        ]
        let ids = values.map(\.theme.id)
        precondition(Set(ids).count == ids.count, "Pibo theme IDs must be unique")
        precondition(!values.isEmpty, "Pibo requires at least one registered theme")
        return values
    }()

    static var themes: [PiboTheme] { registrations.map(\.theme) }
    static var defaultTheme: PiboTheme { registrations[0].theme }

    static func theme(id: String) -> PiboTheme? {
        registrations.first(where: { $0.theme.id == id })?.theme
    }

    static func resolvedThemeID(_ persistedID: String?) -> String {
        guard let persistedID, theme(id: persistedID) != nil else {
            return defaultTheme.id
        }
        return persistedID
    }

    static func makeRenderer(for theme: PiboTheme) -> any PiboThemeRenderer {
        if let registration = registrations.first(where: { $0.theme.id == theme.id }) {
            return registration.makeRenderer()
        }
        #if DEBUG
        assertionFailure("Unregistered production theme: \(theme.id)")
        #endif
        return BasicThemeRenderer(theme: theme)
    }
}

/// Fallback renderer for a static image or the existing procedural terrain.
/// It is intentionally not exposed as a product theme.
final class BasicThemeRenderer: PiboThemeRenderer {
    let themeID: String
    var wind = StageWind(direction: CGVector(dx: -0.9, dy: -0.08), strength: 0.3, gustiness: 0.2)

    private let theme: PiboTheme
    private weak var background: SKNode?
    private var size: CGSize = .zero

    init(theme: PiboTheme) {
        self.theme = theme
        themeID = theme.id
    }

    func install(context: PiboThemeRendererContext, sceneSize: CGSize) {
        background = context.layers.background
        size = sceneSize
        rebuildBackdrop()
    }

    func teardown() {
        background?.removeAllChildren()
        background = nil
    }

    func layout(sceneSize: CGSize) {
        guard sceneSize != size else { return }
        size = sceneSize
        rebuildBackdrop()
    }

    func apply(environment: PiboStageEnvironment) {}

    func apply(renderPolicy: PiboThemeRenderPolicy) {}

    func update(time: TimeInterval, deltaTime: TimeInterval, reduceMotion: Bool) {}

    func characterPlacement(
        theme: PiboTheme,
        growth: PiboGrowthStage,
        headNaturalSize: CGSize?,
        overheadNaturalSize: CGSize?,
        sceneSize: CGSize
    ) -> PiboCharacterPlacement {
        let usesArt = theme.bodyImage != nil
        let bodyWidth = usesArt ? sceneSize.width * (239.262 / 393.0) : min(sceneSize.width * 0.34, 150)
        let bodyHeight = usesArt ? bodyWidth * (235.0 / 239.262) : bodyWidth * 1.12
        let bodyCenter = usesArt
            ? CGPoint(x: sceneSize.width * (theme.bodyCenterX / 393.0),
                      y: sceneSize.height * (1 - theme.bodyCenterY / 852.0))
            : CGPoint(x: sceneSize.width / 2, y: sceneSize.height * 0.34 + bodyHeight * 0.18)
        let body = PiboNodePlacement(
            position: bodyCenter,
            size: CGSize(width: bodyWidth, height: bodyHeight)
        )

        let resolved = theme.resolvedHead(for: growth)
        let head = resolved.head.map { sprite in
            let natural = headNaturalSize ?? CGSize(width: 38, height: 89.5)
            let scale = sceneSize.height / 852.0
            return PiboNodePlacement(
                position: CGPoint(
                    x: sceneSize.width * ((sprite.centerX - theme.bodyCenterX) / 393.0),
                    y: sceneSize.height * ((theme.bodyCenterY - sprite.centerY) / 852.0)
                ),
                size: CGSize(width: natural.width * scale, height: natural.height * scale)
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
            groundLineY: sceneSize.height * 0.34,
            characterZ: 0,
            overheadZ: 13,
            weatherBackZ: 5,
            usesCanonicalMotion: false
        )
    }

    func precipitationImpact(in scene: SKScene) -> ThemePrecipitationImpact? {
        ThemePrecipitationImpact(
            point: CGPoint(
                x: CGFloat.random(in: size.width * 0.04 ... size.width * 0.96),
                y: size.height * 0.34 + CGFloat.random(in: -6 ... 10)
            ),
            splashScale: CGFloat.random(in: 0.8 ... 1.3),
            flatten: 0.42
        )
    }

    private func rebuildBackdrop() {
        guard let background, size.width > 1, size.height > 1 else { return }
        background.removeAllChildren()
        let scene = theme.scene
        if let name = scene.backgroundImage {
            let sprite = SKSpriteNode(texture: SKTexture(imageNamed: name))
            sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
            sprite.size = size
            background.addChild(sprite)
            return
        }

        let sky = SKSpriteNode(texture: Self.gradientTexture(
            top: SKColor(scene.skyTop),
            bottom: SKColor(scene.skyBottom)
        ))
        sky.anchorPoint = .zero
        sky.size = size
        background.addChild(sky)

        let ground = SKShapeNode(path: groundPath(scene.terrain))
        ground.fillColor = SKColor(scene.ground)
        ground.strokeColor = .clear
        ground.zPosition = 1
        background.addChild(ground)
        addGroundDetail(scene)
    }

    private func groundPath(_ terrain: PiboScene.Terrain) -> CGPath {
        let width = size.width
        let top = size.height * 0.34
        let path = CGMutablePath()
        switch terrain {
        case .meadow:
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: top - 14))
            path.addQuadCurve(to: CGPoint(x: width, y: top - 20), control: CGPoint(x: width * 0.5, y: top + 16))
            path.addLine(to: CGPoint(x: width, y: 0))
        case .beach:
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: top - 18))
            path.addQuadCurve(to: CGPoint(x: width, y: top - 18), control: CGPoint(x: width * 0.5, y: top - 34))
            path.addLine(to: CGPoint(x: width, y: 0))
        case .platform:
            path.move(to: CGPoint(x: width * 0.14, y: top - size.height * 0.02))
            path.addLine(to: CGPoint(x: width * 0.86, y: top + size.height * 0.02))
            path.addLine(to: CGPoint(x: width * 0.93, y: top - size.height * 0.025))
            path.addLine(to: CGPoint(x: width * 0.21, y: top - size.height * 0.065))
        }
        path.closeSubpath()
        return path
    }

    private func addGroundDetail(_ scene: PiboScene) {
        guard let background else { return }
        let width = size.width
        let top = size.height * 0.34
        switch scene.terrain {
        case .meadow:
            for petal in Self.petals {
                let radius = 3 + petal.s * 4
                let node = SKShapeNode(ellipseOf: CGSize(width: radius * 2, height: radius * 1.4))
                node.fillColor = SKColor(scene.groundAccent).withAlphaComponent(0.85)
                node.strokeColor = .clear
                node.position = CGPoint(x: petal.x * width, y: (top - 10) * (1 - petal.y))
                node.zPosition = 2
                background.addChild(node)
            }
        case .beach:
            let sea = SKShapeNode(rect: CGRect(x: 0, y: top - 18, width: width, height: size.height * 0.14))
            sea.fillColor = SKColor(scene.groundAccent)
            sea.strokeColor = .clear
            sea.zPosition = 0.5
            background.addChild(sea)
        case .platform:
            let edge = SKShapeNode(rect: CGRect(
                x: width * 0.21,
                y: top - size.height * 0.095,
                width: width * 0.72,
                height: size.height * 0.04
            ))
            edge.fillColor = SKColor(scene.groundAccent)
            edge.strokeColor = .clear
            edge.zPosition = 0.9
            background.addChild(edge)
        }
    }

    private static let petals: [(x: CGFloat, y: CGFloat, s: CGFloat)] = [
        (0.08, 0.42, 0.6), (0.17, 0.70, 0.3), (0.27, 0.30, 0.9), (0.34, 0.62, 0.5),
        (0.45, 0.48, 0.2), (0.52, 0.78, 0.7), (0.61, 0.36, 0.4), (0.69, 0.66, 0.8),
        (0.77, 0.44, 0.3), (0.84, 0.72, 0.6), (0.91, 0.34, 0.5), (0.13, 0.88, 0.4),
    ]

    private static func gradientTexture(top: SKColor, bottom: SKColor) -> SKTexture {
        let textureSize = CGSize(width: 2, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: textureSize, format: format).image { context in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 1, y: 0),
                end: CGPoint(x: 1, y: textureSize.height),
                options: []
            )
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }
}

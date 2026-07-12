import SpriteKit
import UIKit

/// Theme-agnostic precipitation renderer. Themes provide impact targets; the
/// controller owns particles, pooling, cadence, and low-power degradation.
final class PiboWeatherEffectController {
    private let backLayer: SKNode
    private let frontLayer: SKNode
    private var environment: PiboStageEnvironment = .daylight
    private var lowPowerModeEnabled = false
    private var wind = StageWind(direction: CGVector(dx: -0.9, dy: -0.08), strength: 0.3, gustiness: 0.2)
    private var size: CGSize = .zero
    private var themeImpact: () -> ThemePrecipitationImpact? = { nil }
    private var characterImpactPoint: () -> CGPoint? = { nil }
    private var splashPool: [SKSpriteNode] = []
    private var nextSplashPoolIndex = 0

    init(backLayer: SKNode, frontLayer: SKNode) {
        self.backLayer = backLayer
        self.frontLayer = frontLayer
    }

    func apply(
        environment: PiboStageEnvironment,
        lowPowerMode: Bool,
        size: CGSize,
        wind: StageWind,
        themeImpact: @escaping () -> ThemePrecipitationImpact?,
        characterImpactPoint: @escaping () -> CGPoint?
    ) {
        self.environment = environment
        lowPowerModeEnabled = lowPowerMode
        self.size = size
        self.wind = wind
        self.themeImpact = themeImpact
        self.characterImpactPoint = characterImpactPoint
        rebuild()
    }

    func stop() {
        backLayer.removeAllChildren()
        backLayer.removeAllActions()
        frontLayer.removeAllChildren()
        frontLayer.removeAllActions()
        splashPool.removeAll(keepingCapacity: true)
        nextSplashPoolIndex = 0
    }

    private func rebuild() {
        stop()
        guard environment.rainIntensity > 0, size.width > 1, size.height > 1 else { return }
        prepareSplashPool()
        buildRainCurtain()
        startGroundSplashes()
        startCharacterDrips()
    }

    private func buildRainCurtain() {
        let storm = environment.rainIntensity >= 0.8
        let emitter = SKEmitterNode()
        emitter.particleTexture = Self.rainTexture
        emitter.position = CGPoint(x: size.width / 2, y: size.height + 24)
        emitter.particlePositionRange = CGVector(dx: size.width * 1.15, dy: 0)
        let powerMultiplier: CGFloat = lowPowerModeEnabled ? 0.45 : 1
        emitter.particleBirthRate = (90 + 150 * environment.rainIntensity) * powerMultiplier
        emitter.particleLifetime = size.height / 480 + 0.6
        emitter.particleLifetimeRange = 0.3
        emitter.emissionAngle = -.pi / 2
        emitter.emissionAngleRange = 0.05
        emitter.particleSpeed = storm ? 720 : 560
        emitter.particleSpeedRange = 140
        emitter.yAcceleration = -420
        emitter.xAcceleration = wind.direction.dx * (storm ? 140 : 55)
        emitter.particleAlpha = 0.55
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = -0.12
        emitter.particleScale = storm ? 0.55 : 0.42
        emitter.particleScaleRange = 0.2
        emitter.particleColor = Self.rainTint
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .alpha
        emitter.advanceSimulationTime(1.6)
        backLayer.addChild(emitter)
    }

    private func startGroundSplashes() {
        let interval = (environment.rainIntensity >= 0.8 ? 0.05 : 0.11)
            * (lowPowerModeEnabled ? 2.2 : 1)
        frontLayer.run(.repeatForever(.sequence([
            .wait(forDuration: interval, withRange: interval * 0.8),
            .run { [weak self] in self?.spawnThemeImpact() },
        ])), withKey: "groundSplash")
    }

    private func startCharacterDrips() {
        let interval = (environment.rainIntensity >= 0.8 ? 0.35 : 0.6)
            * (lowPowerModeEnabled ? 1.8 : 1)
        frontLayer.run(.repeatForever(.sequence([
            .wait(forDuration: interval, withRange: interval * 0.7),
            .run { [weak self] in self?.spawnCharacterDrip() },
        ])), withKey: "characterDrip")
    }

    private func spawnThemeImpact() {
        guard let impact = themeImpact() else { return }
        impact.reaction?()
        makeSplash(at: impact.point, scale: impact.splashScale, flatten: impact.flatten)
    }

    private func spawnCharacterDrip() {
        guard let landingPoint = characterImpactPoint() else { return }
        let drop = SKSpriteNode(texture: Self.rainTexture)
        drop.size = CGSize(width: 3, height: 11)
        drop.color = Self.rainTint
        drop.colorBlendFactor = 1
        drop.position = CGPoint(x: landingPoint.x, y: landingPoint.y + 46)
        frontLayer.addChild(drop)
        let fall = SKAction.moveTo(y: landingPoint.y, duration: 0.14)
        fall.timingMode = .easeIn
        drop.run(.sequence([
            fall,
            .run { [weak self] in
                self?.makeSplash(at: landingPoint, scale: 0.7, flatten: 0.62)
            },
            .removeFromParent(),
        ]))
    }

    private func makeSplash(at point: CGPoint, scale: CGFloat, flatten: CGFloat) {
        guard let node = acquireSplashNode() else { return }
        node.removeAllActions()
        node.position = point
        node.setScale(scale)
        node.isHidden = false
        let action = flatten > 0.52 ? Self.characterSplashAction : Self.groundSplashAction
        node.run(action.copy() as! SKAction)
    }

    private func prepareSplashPool() {
        guard splashPool.isEmpty else { return }
        for _ in 0..<Self.splashPoolSize {
            let node = SKSpriteNode(texture: Self.groundSplashFrames.first)
            node.size = Self.splashTextureSize
            node.color = Self.rainTint
            node.colorBlendFactor = 1
            node.zPosition = 0
            node.isHidden = true
            frontLayer.addChild(node)
            splashPool.append(node)
        }
    }

    private func acquireSplashNode() -> SKSpriteNode? {
        guard !splashPool.isEmpty else { return nil }
        for offset in 0..<splashPool.count {
            let index = (nextSplashPoolIndex + offset) % splashPool.count
            let node = splashPool[index]
            if node.isHidden || !node.hasActions() {
                nextSplashPoolIndex = (index + 1) % splashPool.count
                node.removeAllActions()
                return node
            }
        }
        let node = splashPool[nextSplashPoolIndex]
        nextSplashPoolIndex = (nextSplashPoolIndex + 1) % splashPool.count
        node.removeAllActions()
        return node
    }

    private static let rainTint = SKColor(red: 0.62, green: 0.78, blue: 0.92, alpha: 1)
    private static let splashPoolSize = 24
    private static let splashTextureSize = CGSize(width: 48, height: 44)
    private static let groundSplashFrames = splashFrames(flatten: 0.42)
    private static let characterSplashFrames = splashFrames(flatten: 0.62)
    private static let groundSplashAction = SKAction.sequence([
        .animate(
            with: groundSplashFrames,
            timePerFrame: 0.34 / Double(groundSplashFrames.count - 1),
            resize: false,
            restore: false
        ),
        .hide(),
    ])
    private static let characterSplashAction = SKAction.sequence([
        .animate(
            with: characterSplashFrames,
            timePerFrame: 0.34 / Double(characterSplashFrames.count - 1),
            resize: false,
            restore: false
        ),
        .hide(),
    ])

    private static func splashFrames(flatten: CGFloat) -> [SKTexture] {
        let frameCount = 21
        let duration: CGFloat = 0.34
        let base = CGPoint(x: splashTextureSize.width / 2, y: splashTextureSize.height * 0.68)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        return (0..<frameCount).map { frame in
            let time = CGFloat(frame) / CGFloat(frameCount - 1) * duration
            let image = UIGraphicsImageRenderer(size: splashTextureSize, format: format).image { context in
                let cg = context.cgContext
                let ringProgress = min(1, time / duration)
                let ringScale = 1 + 1.6 * ringProgress
                let ringSize = CGSize(width: 11 * ringScale, height: 11 * flatten * ringScale)
                cg.setStrokeColor(rainTint.withAlphaComponent(0.75 * (1 - ringProgress)).cgColor)
                cg.setLineWidth(1.4)
                cg.strokeEllipse(in: CGRect(
                    x: base.x - ringSize.width / 2,
                    y: base.y - ringSize.height / 2,
                    width: ringSize.width,
                    height: ringSize.height
                ))

                let beadProgress: CGFloat
                let beadY: CGFloat
                if time <= 0.16 {
                    beadProgress = time / 0.16
                    beadY = base.y - 11 * (1 - pow(1 - beadProgress, 2))
                } else {
                    beadProgress = min(1, (time - 0.16) / 0.16)
                    beadY = base.y - 11 * (1 - beadProgress * beadProgress)
                }
                let beadAlpha = max(0, 1 - time / 0.32)
                cg.setFillColor(rainTint.withAlphaComponent(beadAlpha).cgColor)
                cg.fillEllipse(in: CGRect(x: base.x - 1.7, y: beadY - 1.7, width: 3.4, height: 3.4))

                let sideProgress = min(1, time / 0.18)
                let sideAlpha = max(0, 1 - time / 0.22)
                cg.setFillColor(rainTint.withAlphaComponent(sideAlpha).cgColor)
                for sign: CGFloat in [-1, 1] {
                    let center = CGPoint(
                        x: base.x + sign * 12 * sideProgress,
                        y: base.y - 9 * sideProgress
                    )
                    cg.fillEllipse(in: CGRect(
                        x: center.x - 1.3,
                        y: center.y - 1.3,
                        width: 2.6,
                        height: 2.6
                    ))
                }
            }
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            return texture
        }
    }

    private static let rainTexture: SKTexture = {
        let size = CGSize(width: 4, height: 18)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            cg.addPath(CGPath(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerWidth: 2,
                cornerHeight: 2,
                transform: nil
            ))
            cg.clip()
            let colors = [SKColor.white.withAlphaComponent(0).cgColor, SKColor.white.cgColor] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 2, y: 0),
                end: CGPoint(x: 2, y: 18),
                options: []
            )
        }
        return SKTexture(image: image)
    }()
}

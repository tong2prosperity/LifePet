import SpriteKit

final class ForestFoliageNode: SKSpriteNode {
    private let stiffness: CGFloat
    private let maximumAngle: CGFloat
    private let phaseOffset: CGFloat
    private var angle: CGFloat = 0
    private var angularVelocity: CGFloat = 0

    init(texture: SKTexture, definition: ForestSceneManifest.Foliage) {
        stiffness = definition.stiffness
        maximumAngle = definition.maximumAngle
        phaseOffset = definition.phase
        super.init(texture: texture, color: .clear, size: definition.frame.size)
        anchorPoint = CGPoint(x: definition.anchor.x, y: 1 - definition.anchor.y)
        zPosition = definition.zPosition
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(time: TimeInterval, deltaTime: TimeInterval, wind: ForestWind, reduceMotion: Bool) {
        let dt = CGFloat(min(max(deltaTime, 0), 1.0 / 30.0))
        let amplitude = maximumAngle * wind.strength * (reduceMotion ? 0.25 : 1)
        let base = sin(CGFloat(time) * (0.72 + phaseOffset * 0.04) + phaseOffset) * amplitude
        let gust = sin(CGFloat(time) * 0.19 + phaseOffset * 2.7)
            * sin(CGFloat(time) * 1.43 + phaseOffset)
            * amplitude * wind.gustiness
        let target = base + gust
        let damping = 2 * sqrt(stiffness) * 0.82
        angularVelocity += ((target - angle) * stiffness - angularVelocity * damping) * dt
        angle += angularVelocity * dt
        angle = min(max(angle, -maximumAngle * 1.8), maximumAngle * 1.8)
        zRotation = angle
    }

    func receiveRainImpact(strength: CGFloat, side: CGFloat) {
        angularVelocity += min(max(side, -1), 1) * (0.28 + 0.34 * strength)
    }
}

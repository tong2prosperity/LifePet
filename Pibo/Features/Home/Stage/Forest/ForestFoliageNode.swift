import CoreGraphics
import SpriteKit
import UIKit

final class ForestFoliageNode: SKSpriteNode {
    let interactionRole: ForestSceneManifest.FoliageInteraction.Role
    let maximumInteractionAngle: CGFloat
    let neighborInfluence: CGFloat

    private let ambientStiffness: CGFloat
    private let maximumAmbientAngle: CGFloat
    private let phaseOffset: CGFloat
    private let returnStiffness: CGFloat
    private let returnDamping: CGFloat
    private let alphaMask: ForestFoliageAlphaMask?

    private var ambientAngle: CGFloat = 0
    private var ambientAngularVelocity: CGFloat = 0
    private var interactionAngle: CGFloat = 0
    private var interactionAngularVelocity: CGFloat = 0
    private var directTargetAngle: CGFloat = 0
    private var neighborTargetAngle: CGFloat = 0
    private(set) var isDirectlyManipulated = false

    var displayedInteractionAngle: CGFloat { interactionAngle }
    var acceptsDirectManipulation: Bool { interactionRole == .direct }

    init(texture: SKTexture, definition: ForestSceneManifest.Foliage) {
        ambientStiffness = definition.stiffness
        maximumAmbientAngle = definition.maximumAngle
        phaseOffset = definition.phase
        interactionRole = definition.interaction.role
        maximumInteractionAngle = definition.interaction.maximumAngle
        neighborInfluence = definition.interaction.neighborInfluence
        returnStiffness = definition.interaction.returnStiffness
        returnDamping = definition.interaction.returnDamping
        alphaMask = definition.interaction.role == .direct
            ? ForestFoliageAlphaMask(imageNamed: definition.image)
            : nil
        super.init(texture: texture, color: .clear, size: definition.frame.size)
        name = definition.image
        anchorPoint = CGPoint(x: definition.anchor.x, y: 1 - definition.anchor.y)
        zPosition = definition.zPosition
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(time: TimeInterval, deltaTime: TimeInterval, wind: StageWind, reduceMotion: Bool) {
        let dt = CGFloat(min(max(deltaTime, 0), 1.0 / 30.0))
        let amplitude = maximumAmbientAngle * wind.strength * (reduceMotion ? 0.25 : 1)
        let base = sin(CGFloat(time) * (0.72 + phaseOffset * 0.04) + phaseOffset) * amplitude
        let gust = sin(CGFloat(time) * 0.19 + phaseOffset * 2.7)
            * sin(CGFloat(time) * 1.43 + phaseOffset)
            * amplitude * wind.gustiness
        let ambientTarget = base + gust
        let ambientDamping = 2 * sqrt(ambientStiffness) * 0.82
        ambientAngularVelocity += (
            (ambientTarget - ambientAngle) * ambientStiffness
                - ambientAngularVelocity * ambientDamping
        ) * dt
        ambientAngle += ambientAngularVelocity * dt
        ambientAngle = min(
            max(ambientAngle, -maximumAmbientAngle * 1.8),
            maximumAmbientAngle * 1.8
        )

        updateInteraction(deltaTime: dt, reduceMotion: reduceMotion)
        zRotation = ambientAngle + interactionAngle
    }

    func receiveRainImpact(strength: CGFloat, side: CGFloat) {
        ambientAngularVelocity += min(max(side, -1), 1) * (0.28 + 0.34 * strength)
    }

    func containsOpaquePoint(_ scenePoint: CGPoint, in scene: SKNode) -> Bool {
        guard acceptsDirectManipulation, !isHidden, alpha > 0.01,
              size.width > 0, size.height > 0 else { return false }
        let local = scene.convert(scenePoint, to: self)
        let minX = -anchorPoint.x * size.width
        let minY = -anchorPoint.y * size.height
        let u = (local.x - minX) / size.width
        let v = (local.y - minY) / size.height
        guard (0 ... 1).contains(u), (0 ... 1).contains(v) else { return false }
        // If the authored image ever fails to load, fail closed. Treating the
        // whole sprite rectangle as interactive would make transparent pixels
        // steal taps from Pibo and the scene behind the leaf.
        return alphaMask?.contains(u: u, v: v) ?? false
    }

    func beginDirectManipulation() {
        guard acceptsDirectManipulation else { return }
        isDirectlyManipulated = true
        directTargetAngle = interactionAngle
        interactionAngularVelocity = 0
    }

    func setDirectTargetAngle(_ angle: CGFloat) {
        guard isDirectlyManipulated else { return }
        directTargetAngle = min(max(angle, -maximumInteractionAngle), maximumInteractionAngle)
    }

    func endDirectManipulation(releaseVelocity: CGFloat, tapDirection: CGFloat?) {
        guard isDirectlyManipulated else { return }
        isDirectlyManipulated = false
        directTargetAngle = 0
        if let tapDirection {
            interactionAngularVelocity = min(max(tapDirection, -1), 1) * 0.7
        } else {
            let velocity = min(max(releaseVelocity, -3.2), 3.2)
            if velocity * interactionAngle > 0 {
                // Leave room for a small inertial overshoot without slamming
                // into the hard safety limit on a fast outward flick.
                let limit = max(maximumInteractionAngle * 1.12, 0.18)
                let remaining = max(limit * limit - interactionAngle * interactionAngle, 0)
                let maximumOutwardVelocity = sqrt(returnStiffness * remaining)
                interactionAngularVelocity = min(abs(velocity), maximumOutwardVelocity)
                    * (velocity < 0 ? -1 : 1)
            } else {
                interactionAngularVelocity = velocity
            }
        }
    }

    func setNeighborTargetAngle(_ angle: CGFloat) {
        neighborTargetAngle = angle
    }

    private func updateInteraction(deltaTime dt: CGFloat, reduceMotion: Bool) {
        guard dt > 0 else { return }
        if isDirectlyManipulated {
            let previous = interactionAngle
            let follow = 1 - exp(-30 * dt)
            interactionAngle += (directTargetAngle - interactionAngle) * follow
            interactionAngularVelocity = (interactionAngle - previous) / dt
            return
        }

        let previous = interactionAngle
        let target = neighborTargetAngle
        let stiffness = returnStiffness * (reduceMotion ? 1.25 : 1)
        let damping = returnDamping * (reduceMotion ? 1.4 : 1)
        interactionAngularVelocity += (
            (target - interactionAngle) * stiffness
                - interactionAngularVelocity * damping
        ) * dt
        let proposedAngle = interactionAngle + interactionAngularVelocity * dt

        let limit = max(maximumInteractionAngle * 1.12, 0.18)
        interactionAngle = min(max(proposedAngle, -limit), limit)
        if interactionAngle != proposedAngle,
           interactionAngularVelocity * proposedAngle > 0 {
            interactionAngularVelocity = 0
        }
        if reduceMotion, abs(target) < 0.001, previous * interactionAngle < 0 {
            interactionAngle = 0
            interactionAngularVelocity = 0
        } else if abs(target - interactionAngle) < 0.0005,
                  abs(interactionAngularVelocity) < 0.005 {
            interactionAngle = target
            interactionAngularVelocity = 0
        }
    }
}

/// A native-resolution Alpha map used only when a touch begins. Every hit maps
/// to one source PNG pixel; no dilation or semantic padding is applied.
struct ForestFoliageAlphaMask {
    private static let alphaThreshold: UInt8 = 1

    private let width: Int
    private let height: Int
    private let alpha: [UInt8]

    init?(imageNamed imageName: String) {
        guard let image = UIImage(named: imageName)?.cgImage else { return nil }
        let imageWidth = image.width
        let imageHeight = image.height
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        let bytesPerPixel = 4
        let bytesPerRow = imageWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: imageHeight * bytesPerRow)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let alpha = pixels.withUnsafeMutableBytes({ buffer -> [UInt8]? in
            guard let data = buffer.baseAddress,
                  let context = CGContext(
                    data: data,
                    width: imageWidth,
                    height: imageHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: bitmapInfo
                  ) else { return nil }

            context.interpolationQuality = .none
            // Bitmap row zero already represents the CGImage's top row. Do
            // not apply UIKit's drawing flip here: `contains` converts
            // SpriteKit's bottom-up local V coordinate to that top-down row.
            context.draw(image, in: CGRect(
                x: 0,
                y: 0,
                width: imageWidth,
                height: imageHeight
            ))
            context.flush()

            var alpha = [UInt8](repeating: 0, count: imageWidth * imageHeight)
            for y in 0 ..< imageHeight {
                for x in 0 ..< imageWidth {
                    alpha[y * imageWidth + x] = buffer[
                        y * bytesPerRow + x * bytesPerPixel + 3
                    ]
                }
            }
            return alpha
        }) else { return nil }
        width = imageWidth
        height = imageHeight
        self.alpha = alpha
    }

    func contains(u: CGFloat, v: CGFloat) -> Bool {
        guard (0 ... 1).contains(u), (0 ... 1).contains(v) else { return false }
        let x = Int((u * CGFloat(width - 1)).rounded())
        // SpriteKit local Y points up; bitmap rows run from the image's top.
        let y = Int(((1 - v) * CGFloat(height - 1)).rounded())
        return alpha[y * width + x] >= Self.alphaThreshold
    }
}

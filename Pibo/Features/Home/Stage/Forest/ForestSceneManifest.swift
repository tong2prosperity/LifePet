import CoreGraphics
import Foundation

enum ForestLightingGroup: CaseIterable, Hashable {
    case far
    case midground
    case foreground
    case pibo
    case water
    case emissive
}

/// Figma `3817:2132` uses a 393×852 portrait canvas. All values below retain
/// the original top-left design coordinates; `ForestLayoutMapper` converts
/// them to SpriteKit's bottom-left coordinate system with one uniform scale.
enum ForestSceneManifest {
    static let designSize = CGSize(width: 393, height: 852)
    static let piboFootPoint = CGPoint(x: 196.5, y: 610)
    private static let boringTraverseEasing = PiboUnitBezier([0.42, 0, 0.58, 1])

    /// Exact 460×460 player placement from `pibo_context`'s live integration.
    /// The authored 300×300 artboard is inset by 80 player pixels on every
    /// edge. Keeping the outer player is essential: business `bounceCut` scales
    /// that box around 50% / 58%, not the cropped character artboard.
    struct PiboPlayerPlacement: Equatable {
        let frame: CGRect
        let zPosition: CGFloat

        var artboardFrame: CGRect {
            let inset = frame.width * 80 / 460
            return frame.insetBy(dx: inset, dy: inset)
        }

        /// Top-left design coordinates, matching CSS `transform-origin`.
        var bounceOrigin: CGPoint {
            CGPoint(
                x: frame.minX + frame.width * 0.5,
                y: frame.minY + frame.height * 0.58
            )
        }
    }

    struct PiboArtboardPlacement: Equatable {
        let frame: CGRect
        let zPosition: CGFloat
    }

    static func piboPlayerPlacement(
        stateID: String,
        boringElapsed: TimeInterval = 0
    ) -> PiboPlayerPlacement {
        switch stateID {
        case PiboAnimationResourceID.sleepingHammockA,
             PiboAnimationResourceID.sleepingHammockB,
             PiboAnimationResourceID.wakingHammock:
            return PiboPlayerPlacement(
                frame: CGRect(x: -31, y: 90.8, width: 322, height: 322),
                zPosition: 20
            )
        case "coolhide":
            return PiboPlayerPlacement(
                frame: CGRect(x: 138, y: 240, width: 299, height: 299),
                zPosition: 5.5
            )
        case "dive":
            return PiboPlayerPlacement(
                frame: CGRect(x: -10.5, y: 508, width: 414, height: 414),
                zPosition: 11.5
            )
        case "boring":
            let phase = boringElapsed.truncatingRemainder(dividingBy: 28)
            let x: CGFloat
            if phase < 12 {
                let progress = CGFloat(boringTraverseEasing(phase / 12))
                x = -372 + progress * 361.5
            } else if phase < 16 {
                x = -10.5
            } else {
                let progress = CGFloat(boringTraverseEasing((phase - 16) / 12))
                x = -10.5 + progress * 331.5
            }
            return PiboPlayerPlacement(
                frame: CGRect(x: x, y: 292, width: 414, height: 414),
                zPosition: 10.5
            )
        case "weak":
            return PiboPlayerPlacement(
                frame: CGRect(x: -10.5, y: 370, width: 414, height: 414),
                zPosition: 20
            )
        default:
            return PiboPlayerPlacement(
                frame: CGRect(x: -10.5, y: 284, width: 414, height: 414),
                zPosition: 20
            )
        }
    }

    static func piboArtboardPlacement(
        stateID: String,
        boringElapsed: TimeInterval = 0
    ) -> PiboArtboardPlacement {
        let player = piboPlayerPlacement(stateID: stateID, boringElapsed: boringElapsed)
        return PiboArtboardPlacement(frame: player.artboardFrame, zPosition: player.zPosition)
    }

    struct FoliageInteraction: Hashable {
        enum Role: Hashable {
            case direct
            case passive
        }

        let role: Role
        let maximumAngle: CGFloat
        /// Maximum fraction of a nearby directly manipulated leaf's angle.
        let neighborInfluence: CGFloat
        let returnStiffness: CGFloat
        let returnDamping: CGFloat

        static func direct(
            maximumAngle: CGFloat,
            neighborInfluence: CGFloat
        ) -> Self {
            Self(
                role: .direct,
                maximumAngle: maximumAngle,
                neighborInfluence: neighborInfluence,
                returnStiffness: 36,
                returnDamping: 9
            )
        }

        static func passive(neighborInfluence: CGFloat) -> Self {
            Self(
                role: .passive,
                maximumAngle: 0,
                neighborInfluence: neighborInfluence,
                returnStiffness: 42,
                returnDamping: 10.5
            )
        }
    }

    struct Layer: Hashable {
        let image: String
        let frame: CGRect
        let zPosition: CGFloat
        let lightingGroup: ForestLightingGroup
    }

    struct Foliage: Hashable {
        let image: String
        /// Independent source frame in Figma canvas `3817:2130`.
        let sourceNodeID: String
        let frame: CGRect
        /// Anchor in top-left normalized Figma coordinates.
        let anchor: CGPoint
        let zPosition: CGFloat
        let stiffness: CGFloat
        let maximumAngle: CGFloat
        let phase: CGFloat
        let lightingGroup: ForestLightingGroup
        let interaction: FoliageInteraction

        init(
            image: String,
            sourceNodeID: String,
            frame: CGRect,
            anchor: CGPoint,
            zPosition: CGFloat,
            stiffness: CGFloat,
            maximumAngle: CGFloat,
            phase: CGFloat,
            lightingGroup: ForestLightingGroup,
            interaction: FoliageInteraction
        ) {
            self.image = image
            self.sourceNodeID = sourceNodeID
            self.frame = frame
            self.anchor = anchor
            self.zPosition = zPosition
            self.stiffness = stiffness
            self.maximumAngle = maximumAngle
            self.phase = phase
            self.lightingGroup = lightingGroup
            self.interaction = interaction
        }
    }

    static let backgroundLayers: [Layer] = [
        Layer(image: "forest_bg_tree", frame: CGRect(x: -40.0985, y: -25.7977, width: 449.6905, height: 642.7610), zPosition: 0, lightingGroup: .far),
        Layer(image: "forest_stone_10", frame: CGRect(x: 181.5289, y: 470, width: 86, height: 34.4974), zPosition: 2, lightingGroup: .midground),
        Layer(image: "forest_stone_9", frame: CGRect(x: 94.1058, y: 485, width: 129.1052, height: 35.3897), zPosition: 4, lightingGroup: .midground),
        Layer(image: "forest_secondary_tree", frame: CGRect(x: -85, y: -25, width: 269.5, height: 592.1303), zPosition: 5, lightingGroup: .far),
        Layer(image: "forest_grass_circle", frame: CGRect(x: 239, y: 378, width: 215.1110, height: 190.3749), zPosition: 6, lightingGroup: .midground),
        Layer(image: "forest_stone_8", frame: CGRect(x: -93, y: 448, width: 252.2633, height: 149.5190), zPosition: 7, lightingGroup: .midground),
        Layer(image: "forest_stone_3", frame: CGRect(x: 238, y: 505, width: 168, height: 94), zPosition: 9, lightingGroup: .midground),
        Layer(image: "forest_stone_4", frame: CGRect(x: 295, y: 430, width: 239.1742, height: 165.5062), zPosition: 10, lightingGroup: .midground),
        // Export the complete Figma source group `3906:3293`. Its child
        // `3906:3294` is only the flat base and omits all authored materials.
        Layer(image: "forest_main_tree", frame: CGRect(x: -25, y: 484, width: 461.3105, height: 218.4633), zPosition: 11, lightingGroup: .midground),
        Layer(image: "forest_stone_7", frame: CGRect(x: -73, y: 627, width: 186.7648, height: 125), zPosition: 12, lightingGroup: .foreground),
        Layer(image: "forest_stone_6", frame: CGRect(x: -1, y: 706, width: 165, height: 47), zPosition: 13, lightingGroup: .foreground),
        Layer(image: "forest_stone_5", frame: CGRect(x: -81, y: 686, width: 217, height: 116), zPosition: 14, lightingGroup: .foreground),
        Layer(image: "forest_stone_2", frame: CGRect(x: 314, y: 664, width: 166, height: 147), zPosition: 15, lightingGroup: .foreground),
        Layer(image: "forest_stone_1", frame: CGRect(x: 227, y: 780, width: 202.5465, height: 77.7470), zPosition: 16, lightingGroup: .foreground),
    ]

    static let river = Layer(
        image: "forest_water_static",
        frame: CGRect(x: -34, y: 487, width: 448.2329, height: 382.7229),
        zPosition: 3,
        lightingGroup: .water
    )

    /// Every item is a complete independent foreground-plant frame from
    /// Figma. Hit testing and anchored rotation must use this same texture.
    static let foliage: [Foliage] = [
        Foliage(image: "forest_main_leaf_2", sourceNodeID: "6444:35815", frame: CGRect(x: -43, y: 592.0001, width: 163.0004, height: 202.0049), anchor: CGPoint(x: 0.48, y: 0.98), zPosition: 31, stiffness: 10.5, maximumAngle: 0.065, phase: 0.2, lightingGroup: .foreground, interaction: .direct(maximumAngle: .pi / 6, neighborInfluence: 0.12)),
        // Figma 3906:3081 is one complete blade-and-stem asset. Its whole
        // texture rotates around the authored attachment point below.
        Foliage(
            image: "forest_main_leaf_1",
            sourceNodeID: "3906:3081",
            frame: CGRect(x: 211.6180, y: 494, width: 254.3036, height: 329.7027),
            anchor: CGPoint(x: 0.74, y: 0.98),
            zPosition: 32,
            stiffness: 9.0,
            maximumAngle: 0.075,
            phase: 1.4,
            lightingGroup: .foreground,
            interaction: .direct(maximumAngle: .pi / 6, neighborInfluence: 0.12)
        ),
        Foliage(image: "forest_front_leaf_2", sourceNodeID: "3906:3151", frame: CGRect(x: -71, y: 740, width: 248, height: 128.53), anchor: CGPoint(x: 0.10, y: 0.92), zPosition: 35, stiffness: 12, maximumAngle: 0.05, phase: 2.2, lightingGroup: .foreground, interaction: .direct(maximumAngle: .pi * 2 / 15, neighborInfluence: 0.16)),
        Foliage(image: "forest_front_leaf_1", sourceNodeID: "3906:3141", frame: CGRect(x: 11, y: 774, width: 279, height: 119.9522), anchor: CGPoint(x: 0.12, y: 0.92), zPosition: 36, stiffness: 11, maximumAngle: 0.05, phase: 3.0, lightingGroup: .foreground, interaction: .direct(maximumAngle: .pi * 2 / 15, neighborInfluence: 0.16)),
        Foliage(image: "forest_front_grass_1", sourceNodeID: "3906:3156", frame: CGRect(x: 219.2007, y: 760, width: 70.6650, height: 91.0819), anchor: CGPoint(x: 0.50, y: 1), zPosition: 37, stiffness: 15, maximumAngle: 0.075, phase: 0.8, lightingGroup: .foreground, interaction: .direct(maximumAngle: .pi / 7, neighborInfluence: 0.22)),
        Foliage(image: "forest_front_grass_2", sourceNodeID: "3906:3177", frame: CGRect(x: 261, y: 731.4669, width: 126.9644, height: 170.5405), anchor: CGPoint(x: 0.50, y: 1), zPosition: 38, stiffness: 13, maximumAngle: 0.085, phase: 1.9, lightingGroup: .foreground, interaction: .direct(maximumAngle: .pi / 6, neighborInfluence: 0.19)),
        Foliage(image: "forest_front_grass_3", sourceNodeID: "3906:3213", frame: CGRect(x: 333, y: 747, width: 69.5622, height: 120.7878), anchor: CGPoint(x: 0.50, y: 1), zPosition: 39, stiffness: 14, maximumAngle: 0.085, phase: 2.8, lightingGroup: .foreground, interaction: .direct(maximumAngle: .pi / 7, neighborInfluence: 0.16)),
    ]

    static let morningLight = Layer(
        image: "forest_light_morning",
        frame: CGRect(x: -55, y: -16, width: 411.5, height: 604.5),
        zPosition: 65,
        lightingGroup: .emissive
    )
}

struct ForestLayoutMapper {
    let sceneSize: CGSize

    var scale: CGFloat {
        max(sceneSize.width / ForestSceneManifest.designSize.width,
            sceneSize.height / ForestSceneManifest.designSize.height)
    }

    var origin: CGPoint {
        CGPoint(
            x: (sceneSize.width - ForestSceneManifest.designSize.width * scale) / 2,
            y: (sceneSize.height - ForestSceneManifest.designSize.height * scale) / 2
        )
    }

    func point(_ designPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: origin.x + designPoint.x * scale,
            y: origin.y + (ForestSceneManifest.designSize.height - designPoint.y) * scale
        )
    }

    func size(_ designSize: CGSize) -> CGSize {
        CGSize(width: designSize.width * scale, height: designSize.height * scale)
    }

    /// Converts a top-left design rect into SpriteKit's bottom-left scene space.
    func rect(_ designRect: CGRect) -> CGRect {
        CGRect(
            origin: point(CGPoint(x: designRect.minX, y: designRect.maxY)),
            size: size(designRect.size)
        )
    }

    func designPoint(_ scenePoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (scenePoint.x - origin.x) / scale,
            y: ForestSceneManifest.designSize.height - (scenePoint.y - origin.y) / scale
        )
    }
}

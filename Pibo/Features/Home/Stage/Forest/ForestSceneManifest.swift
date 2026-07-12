import CoreGraphics

/// Figma `3817:2132` uses a 393×852 portrait canvas. All values below retain
/// the original top-left design coordinates; `ForestLayoutMapper` converts
/// them to SpriteKit's bottom-left coordinate system with one uniform scale.
enum ForestSceneManifest {
    static let designSize = CGSize(width: 393, height: 852)
    static let piboFootPoint = CGPoint(x: 196.5, y: 610)

    struct Layer: Hashable {
        let image: String
        let frame: CGRect
        let zPosition: CGFloat
    }

    struct Foliage: Hashable {
        let image: String
        let frame: CGRect
        /// Anchor in top-left normalized Figma coordinates.
        let anchor: CGPoint
        let zPosition: CGFloat
        let stiffness: CGFloat
        let maximumAngle: CGFloat
        let phase: CGFloat
    }

    static let backgroundLayers: [Layer] = [
        Layer(image: "forest_bg_tree", frame: CGRect(x: -40.0985, y: -25.7977, width: 449.6905, height: 642.7610), zPosition: 0),
        Layer(image: "forest_stone_10", frame: CGRect(x: 181.5289, y: 470, width: 86, height: 34.4974), zPosition: 2),
        Layer(image: "forest_stone_9", frame: CGRect(x: 94.1058, y: 485, width: 129.1052, height: 35.3897), zPosition: 4),
        Layer(image: "forest_secondary_tree", frame: CGRect(x: -70, y: -25, width: 269.5, height: 592.1303), zPosition: 5),
        Layer(image: "forest_grass_circle", frame: CGRect(x: 240, y: 378, width: 215.1110, height: 190.3749), zPosition: 6),
        Layer(image: "forest_stone_8", frame: CGRect(x: -93, y: 448, width: 252.2633, height: 149.5190), zPosition: 7),
        Layer(image: "forest_flower", frame: CGRect(x: 265, y: 326.1251, width: 133.8292, height: 210.0371), zPosition: 8),
        Layer(image: "forest_stone_3", frame: CGRect(x: 238, y: 505, width: 168, height: 94), zPosition: 9),
        Layer(image: "forest_stone_4", frame: CGRect(x: 295, y: 430, width: 239.1742, height: 165.5062), zPosition: 10),
        Layer(image: "forest_main_tree", frame: CGRect(x: -25, y: 484, width: 461.3105, height: 218.4633), zPosition: 11),
        Layer(image: "forest_stone_7", frame: CGRect(x: -50, y: 627, width: 186.7648, height: 125), zPosition: 12),
        Layer(image: "forest_stone_6", frame: CGRect(x: 58, y: 717, width: 165, height: 47), zPosition: 13),
        Layer(image: "forest_stone_5", frame: CGRect(x: -58, y: 686, width: 217, height: 116), zPosition: 14),
        Layer(image: "forest_stone_2", frame: CGRect(x: 314, y: 664, width: 166, height: 147), zPosition: 15),
        Layer(image: "forest_stone_1", frame: CGRect(x: 227, y: 780, width: 202.5465, height: 77.7470), zPosition: 16),
    ]

    static let river = Layer(
        image: "forest_river",
        frame: CGRect(x: -34, y: 487, width: 448.2329, height: 382.7229),
        zPosition: 3
    )

    static let foliage: [Foliage] = [
        Foliage(image: "forest_main_leaf_2", frame: CGRect(x: -33, y: 585, width: 210.1935, height: 259.6893), anchor: CGPoint(x: 0.48, y: 0.98), zPosition: 31, stiffness: 10.5, maximumAngle: 0.065, phase: 0.2),
        Foliage(image: "forest_main_leaf_1", frame: CGRect(x: 199.5819, y: 481, width: 283.4227, height: 367.4554), anchor: CGPoint(x: 0.74, y: 0.98), zPosition: 32, stiffness: 9.0, maximumAngle: 0.075, phase: 1.4),
        Foliage(image: "forest_front_leaf_2", frame: CGRect(x: -71, y: 740, width: 248, height: 128.53), anchor: CGPoint(x: 0.10, y: 0.92), zPosition: 35, stiffness: 12, maximumAngle: 0.05, phase: 2.2),
        Foliage(image: "forest_front_leaf_1", frame: CGRect(x: 11, y: 774, width: 279, height: 119.9522), anchor: CGPoint(x: 0.12, y: 0.92), zPosition: 36, stiffness: 11, maximumAngle: 0.05, phase: 3.0),
        Foliage(image: "forest_front_grass_1", frame: CGRect(x: 219.2007, y: 760, width: 70.6650, height: 91.0819), anchor: CGPoint(x: 0.50, y: 1), zPosition: 37, stiffness: 15, maximumAngle: 0.075, phase: 0.8),
        Foliage(image: "forest_front_grass_2", frame: CGRect(x: 261, y: 731.4669, width: 126.9644, height: 170.5405), anchor: CGPoint(x: 0.50, y: 1), zPosition: 38, stiffness: 13, maximumAngle: 0.085, phase: 1.9),
        Foliage(image: "forest_front_grass_3", frame: CGRect(x: 333, y: 747, width: 69.5622, height: 120.7878), anchor: CGPoint(x: 0.50, y: 1), zPosition: 39, stiffness: 14, maximumAngle: 0.085, phase: 2.8),
    ]

    static let morningLight = Layer(
        image: "forest_light_morning",
        frame: CGRect(x: -55, y: -16, width: 411.5, height: 604.5),
        zPosition: 65
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
}

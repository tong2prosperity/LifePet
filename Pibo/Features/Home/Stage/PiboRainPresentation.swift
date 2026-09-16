import CoreGraphics

/// Deterministic rain seeds and timings shared with HarmonyOS
/// `RainPresentation.ets`. Presentation only: rain intensity and wind come
/// from Core's environment output.
enum PiboRainPresentation {
    struct Seed: Equatable {
        let id: Int
        /// Percent of the stage, top-left origin.
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: CGFloat
    }

    static let sparse: [Seed] = [
        .init(id: 1, x: 4, y: 3, size: 12, opacity: 0.42), .init(id: 2, x: 12, y: 26, size: 18, opacity: 0.58),
        .init(id: 3, x: 19, y: 8, size: 14, opacity: 0.48), .init(id: 4, x: 27, y: 42, size: 20, opacity: 0.62),
        .init(id: 5, x: 35, y: 18, size: 11, opacity: 0.38), .init(id: 6, x: 43, y: 2, size: 17, opacity: 0.56),
        .init(id: 7, x: 51, y: 35, size: 14, opacity: 0.46), .init(id: 8, x: 59, y: 13, size: 21, opacity: 0.64),
        .init(id: 9, x: 67, y: 48, size: 13, opacity: 0.44), .init(id: 10, x: 75, y: 24, size: 18, opacity: 0.60),
        .init(id: 11, x: 83, y: 5, size: 15, opacity: 0.50), .init(id: 12, x: 92, y: 39, size: 20, opacity: 0.66),
        .init(id: 13, x: 8, y: 61, size: 16, opacity: 0.52), .init(id: 14, x: 22, y: 73, size: 12, opacity: 0.40),
        .init(id: 15, x: 39, y: 57, size: 19, opacity: 0.61), .init(id: 16, x: 56, y: 79, size: 14, opacity: 0.47),
        .init(id: 17, x: 70, y: 66, size: 18, opacity: 0.59), .init(id: 18, x: 88, y: 82, size: 13, opacity: 0.43),
    ]

    static let dense: [Seed] = sparse + [
        .init(id: 19, x: 1, y: 51, size: 17, opacity: 0.46), .init(id: 20, x: 7, y: 91, size: 12, opacity: 0.36),
        .init(id: 21, x: 15, y: 14, size: 19, opacity: 0.54), .init(id: 22, x: 24, y: 64, size: 15, opacity: 0.43),
        .init(id: 23, x: 31, y: 88, size: 21, opacity: 0.57), .init(id: 24, x: 38, y: 31, size: 13, opacity: 0.39),
        .init(id: 25, x: 46, y: 69, size: 18, opacity: 0.52), .init(id: 26, x: 53, y: 94, size: 14, opacity: 0.41),
        .init(id: 27, x: 61, y: 44, size: 20, opacity: 0.58), .init(id: 28, x: 68, y: 7, size: 12, opacity: 0.37),
        .init(id: 29, x: 77, y: 55, size: 17, opacity: 0.49), .init(id: 30, x: 85, y: 29, size: 14, opacity: 0.42),
        .init(id: 31, x: 95, y: 72, size: 22, opacity: 0.60), .init(id: 32, x: 11, y: 39, size: 13, opacity: 0.40),
        .init(id: 33, x: 29, y: 5, size: 18, opacity: 0.51), .init(id: 34, x: 49, y: 84, size: 16, opacity: 0.45),
        .init(id: 35, x: 73, y: 96, size: 19, opacity: 0.55), .init(id: 36, x: 90, y: 17, size: 15, opacity: 0.44),
    ]

    /// Depth partitions reuse one budget: 24 far + 12 near, or 12 + 6 reduced.
    static func particles(near: Bool, reduced: Bool) -> [Seed] {
        (reduced ? sparse : dense).filter { near ? $0.id % 3 == 0 : $0.id % 3 != 0 }
    }

    /// Seconds for one full-stage traverse.
    static func duration(near: Bool, storm: Bool, reduced: Bool) -> Double {
        (near ? 1.45 : 2.3) * (storm ? 0.8 : 1) * (reduced ? 1.8 : 1)
    }

    /// Authored creek anchors on the 393×852 forest board (top-left design).
    static let rippleAnchors: [CGPoint] = [
        CGPoint(x: 184, y: 680), CGPoint(x: 250, y: 726),
        CGPoint(x: 161, y: 785), CGPoint(x: 221, y: 814),
    ]
}

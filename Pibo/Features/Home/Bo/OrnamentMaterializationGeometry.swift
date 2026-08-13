import SwiftUI

/// Object-specific structural regions used by the unlock construction reveal.
struct OrnamentBuildRegion: Identifiable {
    let id: String
    let frame: CGRect
    let entryOffset: CGSize

    static func plan(for id: PiboOrnament.ID) -> [OrnamentBuildRegion] {
        switch id {
        case .hammock:
            // Suspension first, then the cradle, then its lower details.
            topDown(prefix: "hammock")
        case .chime:
            // The hanging point is the physical prerequisite for every bell.
            topDown(prefix: "chime")
        case .statusObserver:
            // A freestanding instrument is assembled base → body → lens.
            bottomUp(prefix: "observer")
        case .lantern:
            // The plant grows from its rooted base into stems and flower lamps.
            bottomUp(prefix: "lantern")
        }
    }

    private static func topDown(prefix: String) -> [OrnamentBuildRegion] {
        [
            OrnamentBuildRegion(
                id: "\(prefix).anchor",
                frame: CGRect(x: 0, y: 0, width: 1, height: 0.34),
                entryOffset: CGSize(width: 0, height: -7)
            ),
            OrnamentBuildRegion(
                id: "\(prefix).body",
                frame: CGRect(x: 0, y: 0.34, width: 1, height: 0.34),
                entryOffset: CGSize(width: 0, height: -5)
            ),
            OrnamentBuildRegion(
                id: "\(prefix).detail",
                frame: CGRect(x: 0, y: 0.68, width: 1, height: 0.32),
                entryOffset: CGSize(width: 0, height: -3)
            ),
        ]
    }

    private static func bottomUp(prefix: String) -> [OrnamentBuildRegion] {
        [
            OrnamentBuildRegion(
                id: "\(prefix).base",
                frame: CGRect(x: 0, y: 0.68, width: 1, height: 0.32),
                entryOffset: CGSize(width: 0, height: 7)
            ),
            OrnamentBuildRegion(
                id: "\(prefix).body",
                frame: CGRect(x: 0, y: 0.34, width: 1, height: 0.34),
                entryOffset: CGSize(width: 0, height: 5)
            ),
            OrnamentBuildRegion(
                id: "\(prefix).detail",
                frame: CGRect(x: 0, y: 0, width: 1, height: 0.34),
                entryOffset: CGSize(width: 0, height: 3)
            ),
        ]
    }
}

/// Cubic path used by the invested `bo` as it enters the selected artwork.
struct InvestmentFlightPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: Self.start(in: rect.size))
        path.addCurve(
            to: Self.end(in: rect.size),
            control1: Self.control1(in: rect.size),
            control2: Self.control2(in: rect.size)
        )
        return path
    }

    static func point(at rawProgress: CGFloat, in size: CGSize) -> CGPoint {
        let progress = min(max(rawProgress, 0), 1)
        let inverse = 1 - progress
        let start = start(in: size)
        let first = control1(in: size)
        let second = control2(in: size)
        let end = end(in: size)
        return CGPoint(
            x: inverse * inverse * inverse * start.x
                + 3 * inverse * inverse * progress * first.x
                + 3 * inverse * progress * progress * second.x
                + progress * progress * progress * end.x,
            y: inverse * inverse * inverse * start.y
                + 3 * inverse * inverse * progress * first.y
                + 3 * inverse * progress * progress * second.y
                + progress * progress * progress * end.y
        )
    }

    private static func start(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width + 14, y: -6)
    }

    private static func control1(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.92, y: size.height * 0.34)
    }

    private static func control2(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.38, y: size.height * 0.08)
    }

    private static func end(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.5, y: size.height * 0.52)
    }
}

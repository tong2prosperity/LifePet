import PiboCore

enum PiboCorePetDetectiveAdapter {
    struct Point: Equatable, Hashable {
        let x: Int
        let y: Int
    }

    static func canMove(
        size: Int,
        rocks: Set<Point>,
        from: Point,
        to: Point
    ) -> Bool {
        PiboCorePetDetective.canMove(
            size: size,
            rocks: rocks.map(\.corePoint),
            from: from.corePoint,
            to: to.corePoint
        )
    }

    static func shortestPath(
        size: Int,
        rocks: Set<Point>,
        start: Point,
        target: Point
    ) -> Int? {
        PiboCorePetDetective.shortestPath(
            size: size,
            rocks: rocks.map(\.corePoint),
            start: start.corePoint,
            target: target.corePoint
        )
    }

    static func score(shortestPath: Int, moves: Int) -> Int {
        PiboCorePetDetective.score(shortestPath: shortestPath, moves: moves)
    }
}

private extension PiboCorePetDetectiveAdapter.Point {
    var corePoint: PiboCorePetDetectivePoint {
        PiboCorePetDetectivePoint(x: x, y: y)
    }
}

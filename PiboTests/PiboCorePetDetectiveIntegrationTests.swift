import Testing
@testable import Pibo

@Test func rustPetDetectiveEngineDrivesGameRules() {
    let start = PiboCorePetDetectiveAdapter.Point(x: 0, y: 0)
    let target = PiboCorePetDetectiveAdapter.Point(x: 4, y: 4)
    #expect(PiboCorePetDetectiveAdapter.shortestPath(
        size: 5,
        rocks: [],
        start: start,
        target: target
    ) == 8)

    let rocks: Set<PiboCorePetDetectiveAdapter.Point> = [.init(x: 1, y: 0)]
    #expect(!PiboCorePetDetectiveAdapter.canMove(
        size: 5,
        rocks: rocks,
        from: start,
        to: .init(x: 1, y: 0)
    ))
    #expect(PiboCorePetDetectiveAdapter.canMove(
        size: 5,
        rocks: rocks,
        from: start,
        to: .init(x: 0, y: 1)
    ))
    #expect(PiboCorePetDetectiveAdapter.score(shortestPath: 8, moves: 8) == 88)
    #expect(PiboCorePetDetectiveAdapter.score(shortestPath: 8, moves: 10) == 64)
}

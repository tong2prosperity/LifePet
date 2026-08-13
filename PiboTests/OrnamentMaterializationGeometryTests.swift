import CoreGraphics
import Testing
@testable import Pibo

@MainActor
struct OrnamentMaterializationGeometryTests {
    @Test func hangingOrnamentsBuildFromTheirAnchorDownward() {
        for (id, prefix) in [
            (PiboOrnament.ID.hammock, "hammock"),
            (.chime, "chime"),
        ] {
            let regions = OrnamentBuildRegion.plan(for: id)

            #expect(regions.map(\.id) == [
                "\(prefix).anchor",
                "\(prefix).body",
                "\(prefix).detail",
            ])
            #expect(regions.map(\.frame) == [
                CGRect(x: 0, y: 0, width: 1, height: 0.34),
                CGRect(x: 0, y: 0.34, width: 1, height: 0.34),
                CGRect(x: 0, y: 0.68, width: 1, height: 0.32),
            ])
            #expect(regions.map(\.entryOffset) == [
                CGSize(width: 0, height: -7),
                CGSize(width: 0, height: -5),
                CGSize(width: 0, height: -3),
            ])
        }
    }

    @Test func freestandingOrnamentsBuildFromTheirBaseUpward() {
        for (id, prefix) in [
            (PiboOrnament.ID.statusObserver, "observer"),
            (.lantern, "lantern"),
        ] {
            let regions = OrnamentBuildRegion.plan(for: id)

            #expect(regions.map(\.id) == [
                "\(prefix).base",
                "\(prefix).body",
                "\(prefix).detail",
            ])
            #expect(regions.map(\.frame) == [
                CGRect(x: 0, y: 0.68, width: 1, height: 0.32),
                CGRect(x: 0, y: 0.34, width: 1, height: 0.34),
                CGRect(x: 0, y: 0, width: 1, height: 0.34),
            ])
            #expect(regions.map(\.entryOffset) == [
                CGSize(width: 0, height: 7),
                CGSize(width: 0, height: 5),
                CGSize(width: 0, height: 3),
            ])
        }
    }

    @Test func flightPathClampsProgressAndKeepsItsAuthoredCurve() {
        let size = CGSize(width: 200, height: 100)
        let start = CGPoint(x: 214, y: -6)
        let midpoint = CGPoint(x: 136.75, y: 21.5)
        let end = CGPoint(x: 100, y: 52)

        #expect(InvestmentFlightPath.point(at: -1, in: size) == start)
        #expect(InvestmentFlightPath.point(at: 0, in: size) == start)
        #expect(InvestmentFlightPath.point(at: 0.5, in: size) == midpoint)
        #expect(InvestmentFlightPath.point(at: 1, in: size) == end)
        #expect(InvestmentFlightPath.point(at: 2, in: size) == end)
    }
}

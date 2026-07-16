import CoreLocation
import Testing
@testable import Pibo

@Test func rustDoodleGeometryDrivesTheAppDomain() {
    let square = [
        CLLocationCoordinate2D(latitude: 0, longitude: 0),
        CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
        CLLocationCoordinate2D(latitude: 0.001, longitude: 0.001),
        CLLocationCoordinate2D(latitude: 0.001, longitude: 0),
    ]
    #expect(abs(PiboCoreDoodleAdapter.enclosedArea(square) - 12_392) < 400)
    #expect(PiboCoreDoodleAdapter.pathLength(square) > 300)
    #expect(PiboCoreDoodleAdapter.isDrawn(coordinateCount: 3, distanceMeters: 30))
    #expect(!PiboCoreDoodleAdapter.isDrawn(coordinateCount: 2, distanceMeters: 100))
}


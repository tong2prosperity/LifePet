import CoreLocation
import PiboCore

enum PiboCoreDoodleAdapter {
    static func segmentDistance(
        from first: CLLocationCoordinate2D,
        to second: CLLocationCoordinate2D
    ) -> Double {
        PiboCoreDoodle.segmentDistance(from: first.coreCoordinate, to: second.coreCoordinate)
    }

    static func pathLength(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        PiboCoreDoodle.pathLength(coordinates.map(\.coreCoordinate))
    }

    static func enclosedArea(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        PiboCoreDoodle.enclosedArea(coordinates.map(\.coreCoordinate))
    }

    static func isDrawn(coordinateCount: Int, distanceMeters: Double) -> Bool {
        PiboCoreDoodle.isDrawn(
            coordinateCount: coordinateCount,
            distanceMeters: distanceMeters
        )
    }
}

private extension CLLocationCoordinate2D {
    var coreCoordinate: PiboCoreDoodleCoordinate {
        PiboCoreDoodleCoordinate(latitude: latitude, longitude: longitude)
    }
}


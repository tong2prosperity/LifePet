import CoreLocation
import PiboCore
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

@Test func rustDoodleTaskScoreAndRewardDriveTheAppDomain() {
    let shape = PiboCoreDoodleAdapter.shape(dayKey: 20_000, acceptedTaskCount: 0)
    #expect(PiboCoreWalkDoodleShape.allCases.contains(shape))

    let center = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
    let radius = 0.00055
    let circle = (0...48).map { index in
        let angle = Double(index) / 48 * 2 * Double.pi
        return CLLocationCoordinate2D(
            latitude: center.latitude + sin(angle) * radius,
            longitude: center.longitude + cos(angle) * radius
        )
    }
    let evaluation = PiboCoreDoodleAdapter.evaluate(
        shape: .circle,
        coordinates: circle,
        previousBestScore: 0,
        dailyRewardedEnergy: 0
    )
    #expect(evaluation.score.isValid)
    #expect(evaluation.score.isCompleted)
    #expect(evaluation.score.score > 0)
    #expect(evaluation.reward.newBestScore == evaluation.score.score)
    #expect(evaluation.reward.grantedEnergy > 0)
}

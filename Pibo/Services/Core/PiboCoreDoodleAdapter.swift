import CoreLocation
import PiboCore

enum PiboCoreDoodleAdapter {
    struct Evaluation: Equatable, Sendable {
        let score: PiboCoreWalkDoodleScore
        let reward: PiboCoreWalkDoodleReward
    }

    static var scoringVersion: UInt32 { PiboCoreDoodle.scoringVersion }
    static var rewardVersion: UInt32 { PiboCoreDoodle.rewardVersion }
    static var minimumDistanceMeters: Double { PiboCoreDoodle.minimumDistanceMeters }
    static var maximumDailyBonusEnergy: Double { PiboCoreDoodle.maximumDailyBonusEnergy }

    static func shape(dayKey: Int64, acceptedTaskCount: Int) -> PiboCoreWalkDoodleShape {
        PiboCoreDoodle.shape(dayKey: dayKey, acceptedTaskCount: acceptedTaskCount)
    }

    static func evaluate(
        shape: PiboCoreWalkDoodleShape,
        coordinates: [CLLocationCoordinate2D],
        previousBestScore: Int,
        dailyRewardedEnergy: Double
    ) -> Evaluation {
        let score = PiboCoreDoodle.score(
            shape: shape,
            coordinates: coordinates.map(\.coreCoordinate)
        )
        return Evaluation(
            score: score,
            reward: PiboCoreDoodle.reward(
                for: score,
                previousBestScore: previousBestScore,
                dailyRewardedEnergy: dailyRewardedEnergy
            )
        )
    }

    static func copyIndex(
        kind: PiboCoreWalkDoodleCopyKind,
        coordinateCount: Int,
        distanceMeters: Double,
        durationSeconds: Double,
        attempt: Int,
        lineCount: Int
    ) -> Int? {
        PiboCoreDoodle.copyIndex(
            kind: kind,
            coordinateCount: coordinateCount,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            attempt: attempt,
            lineCount: lineCount
        )
    }

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

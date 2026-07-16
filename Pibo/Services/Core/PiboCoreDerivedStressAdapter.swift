import Foundation
import PiboCore

enum PiboCoreDerivedStressAdapter {
    static let maxAnchorAge: TimeInterval = PiboCoreDerivedStress.maxAnchorAgeSeconds
    static let maxHRAge: TimeInterval = PiboCoreDerivedStress.maxHRAgeSeconds

    static func compute(
        rmssd: Double?,
        baseline: StressBaseline?,
        restingHR: Double,
        currentHR: Double,
        currentHRAt: Date?,
        rmssdAt: Date?,
        isMoving: Bool,
        now: Date
    ) -> DerivedStress? {
        guard let result = PiboCoreDerivedStress.compute(PiboCoreDerivedStressInput(
            rmssd: rmssd,
            baseline: baseline?.derivedCoreBaseline,
            restingHR: restingHR,
            currentHR: currentHR,
            currentHRAgeSeconds: currentHRAt.map { now.timeIntervalSince($0) },
            rmssdAgeSeconds: rmssdAt.map { now.timeIntervalSince($0) },
            isMoving: isMoving
        )) else { return nil }
        return DerivedStress(
            score: result.score,
            level: appLevel(result.level),
            hrvAgeMinutes: result.hrvAgeMinutes,
            isEstimated: result.isEstimated
        )
    }

    private static func appLevel(_ level: PiboCoreStressLevel) -> StressLevel {
        switch level {
        case .excellent: .excellent
        case .normal: .normal
        case .notice: .notice
        case .overload: .overload
        }
    }
}

private extension StressBaseline {
    var derivedCoreBaseline: PiboCoreStressBaseline {
        PiboCoreStressBaseline(meanLn: meanLn, sdLn: sdLn, dayCount: dayCount)
    }
}

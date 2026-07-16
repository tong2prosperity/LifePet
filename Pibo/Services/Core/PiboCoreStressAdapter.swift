import PiboCore

/// Keeps app-facing stress models stable while the scoring rules live in the
/// shared Rust core used by both iOS and HarmonyOS.
enum PiboCoreStressAdapter {
    static let coldStartDays = PiboCoreStress.coldStartDays
    static let fullPersonalDays = PiboCoreStress.fullPersonalDays

    static func baselineZ(rmssd: Double, baseline: StressBaseline) -> Double {
        PiboCoreStress.baselineZ(rmssd: rmssd, baseline: baseline.coreBaseline)
    }

    static func baseline(dailyMedians: [Double]) -> StressBaseline? {
        guard let statistics = PiboCoreStress.baseline(dailyMedians: dailyMedians) else {
            return nil
        }
        return StressBaseline(
            meanLn: statistics.baseline.meanLn,
            sdLn: statistics.baseline.sdLn,
            dayCount: statistics.baseline.dayCount,
            geoMean: statistics.geoMean
        )
    }

    static func personalScore(rmssd: Double, baseline: StressBaseline) -> Double {
        PiboCoreStress.personalScore(rmssd: rmssd, baseline: baseline.coreBaseline)
    }

    static func absoluteScore(rmssd: Double) -> Double {
        PiboCoreStress.absoluteScore(rmssd: rmssd)
    }

    static func anchor(rmssd: Double?, baseline: StressBaseline?) -> Double? {
        PiboCoreStress.anchor(rmssd: rmssd, baseline: baseline?.coreBaseline)
    }

    static func tier(for score: Double) -> StressLevel {
        appLevel(PiboCoreStress.tier(for: score))
    }

    static func level(
        rmssd: Double,
        baseline: StressBaseline?,
        restingHR: Double
    ) -> StressLevel {
        appLevel(PiboCoreStress.level(
            rmssd: rmssd,
            baseline: baseline?.coreBaseline,
            restingHR: restingHR
        ))
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
    var coreBaseline: PiboCoreStressBaseline {
        PiboCoreStressBaseline(meanLn: meanLn, sdLn: sdLn, dayCount: dayCount)
    }
}

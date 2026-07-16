import Foundation
import HealthKit
import PiboCore

enum PiboCoreSleepAdapter {
    enum ResolvedSampleKind {
        case ignored
        case awake
        case legacyAsleep
        case core
        case deep
        case rem
        case unspecified
    }

    static func sampleIsDetailed(_ value: HKCategoryValueSleepAnalysis?) -> Bool {
        PiboCoreSleep.sampleIsDetailed(coreSampleKind(value))
    }

    static func resolveSample(
        _ value: HKCategoryValueSleepAnalysis?,
        hasDetailedSamples: Bool
    ) -> ResolvedSampleKind {
        switch PiboCoreSleep.resolveSample(
            coreSampleKind(value),
            hasDetailedSamples: hasDetailedSamples
        ) {
        case .ignored: .ignored
        case .awake: .awake
        case .legacyAsleep: .legacyAsleep
        case .core: .core
        case .deep: .deep
        case .rem: .rem
        case .unspecified: .unspecified
        }
    }

    static func samplesShareSession(gapSeconds: TimeInterval) -> Bool {
        PiboCoreSleep.samplesShareSession(gapSeconds: gapSeconds)
    }

    static func segmentsShouldMerge(sameStage: Bool, gapSeconds: TimeInterval) -> Bool {
        PiboCoreSleep.segmentsShouldMerge(sameStage: sameStage, gapSeconds: gapSeconds)
    }

    private static func coreSampleKind(
        _ value: HKCategoryValueSleepAnalysis?
    ) -> PiboCoreSleepSampleKind {
        switch value {
        case .some(.awake): .awake
        case .some(.asleep): .legacyAsleep
        case .some(.asleepCore): .core
        case .some(.asleepDeep): .deep
        case .some(.asleepREM): .rem
        case .some(.asleepUnspecified): .unspecified
        default: .other
        }
    }
}

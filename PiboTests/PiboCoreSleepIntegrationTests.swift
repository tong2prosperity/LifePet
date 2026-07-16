import HealthKit
import Testing
@testable import Pibo

@Test func rustSleepTimingPolicyDrivesHealthIngestion() {
    #expect(PiboCoreSleepAdapter.samplesShareSession(gapSeconds: 4 * 3600 - 0.001))
    #expect(!PiboCoreSleepAdapter.samplesShareSession(gapSeconds: 4 * 3600))
    #expect(PiboCoreSleepAdapter.segmentsShouldMerge(sameStage: true, gapSeconds: 60))
    #expect(!PiboCoreSleepAdapter.segmentsShouldMerge(sameStage: true, gapSeconds: 60.001))
    #expect(!PiboCoreSleepAdapter.segmentsShouldMerge(sameStage: false, gapSeconds: 0))
}

@Test func rustSleepSamplePriorityDrivesHealthKitMapping() {
    #expect(PiboCoreSleepAdapter.sampleIsDetailed(.asleepCore))
    #expect(PiboCoreSleepAdapter.sampleIsDetailed(.asleepUnspecified))
    #expect(!PiboCoreSleepAdapter.sampleIsDetailed(.asleep))
    #expect(PiboCoreSleepAdapter.resolveSample(
        .asleep,
        hasDetailedSamples: true
    ) == .ignored)
    #expect(PiboCoreSleepAdapter.resolveSample(
        .asleep,
        hasDetailedSamples: false
    ) == .legacyAsleep)
    #expect(PiboCoreSleepAdapter.resolveSample(
        .asleepUnspecified,
        hasDetailedSamples: true
    ) == .unspecified)
}

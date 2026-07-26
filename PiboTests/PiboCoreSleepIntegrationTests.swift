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
    #expect(PiboCoreSleepAdapter.sampleIsDetailed(.asleepDeep))
    #expect(PiboCoreSleepAdapter.sampleIsDetailed(.asleepREM))
    #expect(!PiboCoreSleepAdapter.sampleIsDetailed(.awake))
}

/// `asleep` and `asleepUnspecified` are the same HealthKit value — iOS 16 only
/// renamed it — so the adapter cannot tell a modern stage-less sample from a
/// pre-iOS-16 block that envelopes the real stages. It resolves that ambiguity
/// conservatively, and both halves of that choice are load-bearing:
/// `hasDetailedStages` gates the card's stage breakdown (a phone-only sleep
/// schedule must not render as 100% 浅睡), and dropping the span on a source that
/// *does* carry stages keeps `MorningSleepSessionBuilder.normalize` from letting
/// the enveloping block swallow them.
@Test func healthKitAmbiguousAsleepValueResolvesConservatively() {
    #expect(HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue == 1)
    #expect(!PiboCoreSleepAdapter.sampleIsDetailed(.asleepUnspecified))
    #expect(PiboCoreSleepAdapter.resolveSample(
        .asleepUnspecified,
        hasDetailedSamples: true
    ) == .ignored)
    #expect(PiboCoreSleepAdapter.resolveSample(
        .asleepUnspecified,
        hasDetailedSamples: false
    ) == .legacyAsleep)
}

/// Characterization guard for the mapping above. Fed an enveloping whole-night
/// span *as if it were a stage*, the normalizer clips every interior stage away
/// — which is exactly why ingestion resolves an ambiguous asleep block to
/// `.ignored` whenever its own source also carries stages. If normalization ever
/// learns to handle envelopes, this expectation flips and the conservative
/// mapping can be revisited.
@Test func anEnvelopingSpanWouldClipTheInteriorStagesOfItsOwnSource() {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    func at(_ hours: Double) -> Date { base.addingTimeInterval(hours * 3_600) }
    func value(_ start: Double, _ end: Double, _ stage: SleepStage) -> MorningSleepSampleValue {
        .init(start: at(start), end: at(end), stage: stage, sourceID: "watch",
              sourceHasDetailedStages: true, isInBed: false)
    }
    let samples: [MorningSleepSampleValue] = [
        value(0, 6, .core),   // the envelope, had it survived resolution
        value(0, 3, .core),
        value(3, 4, .deep),
        value(4, 6, .rem),
    ]

    let session = MorningSleepSessionBuilder.latestSession(from: samples)
    #expect(session?.deep == 0)
    #expect(session?.rem == 0)
    #expect(abs((session?.total ?? 0) - 6 * 3_600) < 1)
}

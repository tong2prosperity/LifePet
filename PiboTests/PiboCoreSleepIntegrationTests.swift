import Testing
@testable import Pibo

@Test func rustSleepTimingPolicyDrivesHealthIngestion() {
    #expect(PiboCoreSleepAdapter.samplesShareSession(gapSeconds: 4 * 3600 - 0.001))
    #expect(!PiboCoreSleepAdapter.samplesShareSession(gapSeconds: 4 * 3600))
    #expect(PiboCoreSleepAdapter.segmentsShouldMerge(sameStage: true, gapSeconds: 60))
    #expect(!PiboCoreSleepAdapter.segmentsShouldMerge(sameStage: true, gapSeconds: 60.001))
    #expect(!PiboCoreSleepAdapter.segmentsShouldMerge(sameStage: false, gapSeconds: 0))
}

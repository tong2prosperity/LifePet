import Testing
@testable import Pibo

@Test func rustRhythmTapPolicyDrivesTimingAndJudgement() {
    let config = PiboCoreRhythmTapAdapter.config
    #expect(config.beatInterval == 0.6)
    #expect(config.countIn == 2.4)
    #expect(config.session == 45)
    #expect(config.debounce == 0.12)

    let exact = PiboCoreRhythmTapAdapter.judge(
        elapsed: 1.2,
        lastJudgedBeat: .min,
        combo: 2
    )
    #expect(exact.beat == 2)
    #expect(exact.newCombo == 3)
    #expect(exact.scoreGain == 13)
    #expect(exact.judgement == .exact)

    let duplicate = PiboCoreRhythmTapAdapter.judge(
        elapsed: 1.04,
        lastJudgedBeat: 2,
        combo: 4
    )
    #expect(duplicate.judgement == .duplicate)
    #expect(duplicate.newCombo == 4)

    let expired = PiboCoreRhythmTapAdapter.resolveExpired(
        elapsed: 0.77,
        lastResolvedBeat: 0,
        lastJudgedBeat: 0
    )
    #expect(expired.latestExpiredBeat == 1)
    #expect(expired.advanced)
    #expect(expired.missed)
}

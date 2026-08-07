import Testing
@testable import Pibo

@Test func rustPatV2UsesFortyPercentAndBothSpeechCaps() {
    #expect(PiboCorePatAdapter.decideV2(
        spokenIn24Hours: 0,
        spokenIn10Minutes: 0,
        speechRoll: 0.399_999,
        restingState: false
    ).speaks)
    #expect(!PiboCorePatAdapter.decideV2(
        spokenIn24Hours: 0,
        spokenIn10Minutes: 0,
        speechRoll: 0.4,
        restingState: false
    ).speaks)
    #expect(!PiboCorePatAdapter.decideV2(
        spokenIn24Hours: 9,
        spokenIn10Minutes: 0,
        speechRoll: 0,
        restingState: false
    ).speaks)
    #expect(!PiboCorePatAdapter.decideV2(
        spokenIn24Hours: 0,
        spokenIn10Minutes: 3,
        speechRoll: 0,
        restingState: false
    ).speaks)
}

@Test func sleepAndWakingPatsNeverCountTowardAngry() {
    #expect(!PiboCorePatAdapter.decideV2(
        spokenIn24Hours: 0,
        spokenIn10Minutes: 0,
        speechRoll: 0,
        restingState: true
    ).countsTowardAngry)
    #expect(PiboCorePatAdapter.decideV2(
        spokenIn24Hours: 0,
        spokenIn10Minutes: 0,
        speechRoll: 0,
        restingState: false
    ).countsTowardAngry)
}

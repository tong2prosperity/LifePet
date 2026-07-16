import Testing
@testable import Pibo

@Test func rustPatPolicyDrivesTheAppDomain() {
    #expect(PiboCorePatAdapter.decide(
        spokenIn24Hours: 9,
        spokenIn10Minutes: 0,
        speechRoll: 0,
        storyRoll: 0,
        hasUnrevealedStory: true
    ) == .ignored)
    #expect(PiboCorePatAdapter.decide(
        spokenIn24Hours: 8,
        spokenIn10Minutes: 2,
        speechRoll: 0.29,
        storyRoll: 0.24,
        hasUnrevealedStory: true
    ) == .storySpeech)
    #expect(PiboCorePatAdapter.decide(
        spokenIn24Hours: 0,
        spokenIn10Minutes: 0,
        speechRoll: 0.29,
        storyRoll: 0.24,
        hasUnrevealedStory: false
    ) == .stateSpeech)
}


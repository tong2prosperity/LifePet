import Testing
@testable import Pibo

@Test func rustPotStackPolicyDrivesDropResolution() {
    let perfect = PiboCorePotStackAdapter.drop(
        topX: 0.5,
        topWidth: 0.72,
        movingX: 0.51,
        perfectStreak: 2
    )
    #expect(perfect.success)
    #expect(perfect.perfect)
    #expect(perfect.newStreak == 3)
    #expect(perfect.scoreGain == 4)

    let trimmed = PiboCorePotStackAdapter.drop(
        topX: 0.5,
        topWidth: 0.72,
        movingX: 0.6,
        perfectStreak: 4
    )
    #expect(trimmed.success)
    #expect(!trimmed.perfect)
    #expect(trimmed.newStreak == 0)
    #expect(trimmed.cutPercent == 13)
}

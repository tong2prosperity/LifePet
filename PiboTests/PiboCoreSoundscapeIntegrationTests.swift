import Testing
@testable import Pibo

@Test func rustSoundscapeRulesDriveTheAppDomain() {
    #expect(abs(PiboCoreSoundscapeAdapter.dayWeight(at: 7) - 0.5) < 0.0001)
    let rain = PiboCoreSoundscapeAdapter.resolve(
        localHour: 12,
        weather: .rain,
        biome: .forest
    )
    #expect(abs((rain.loopVolumes[.forestWind] ?? 0) - 0.075) < 0.0001)
    #expect(abs((rain.loopVolumes[.lightRain] ?? 0) - 0.36) < 0.0001)
    #expect(!rain.thunderEnabled)
    let storm = PiboCoreSoundscapeAdapter.resolve(
        localHour: 12,
        weather: .thunderstorm,
        biome: .forest
    )
    #expect(abs((storm.loopVolumes[.heavyRain] ?? 0) - 0.55) < 0.0001)
    #expect(storm.thunderEnabled)
}


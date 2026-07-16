import CoreFoundation
import Testing
@testable import Pibo

@Test func rustEnvironmentRulesDriveTheAppDomain() {
    #expect(PiboStageEnvironmentResolver.normalizedHour(-1) == 23)
    #expect(PiboDayPhase.resolve(hour: 5) == .morning)
    #expect(PiboDayPhase.resolve(hour: 9) == .day)
    #expect(PiboDayPhase.resolve(hour: 16.5) == .dusk)
    #expect(PiboDayPhase.resolve(hour: 20.5) == .night)
    #expect(PiboStageEnvironment(localHour: 12, weather: .rain).rainIntensity == 0.6)
    #expect(PiboStageEnvironment(localHour: 12, weather: .thunderstorm).rainIntensity == 1)
    #expect(PiboStageEnvironment(localHour: 12, weather: .snow).rainIntensity == 0)
}

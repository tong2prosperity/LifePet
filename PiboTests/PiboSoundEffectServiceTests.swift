import Foundation
import Testing
@testable import Pibo

@MainActor
struct PiboSoundEffectServiceTests {
    /// Same twelve stems as HarmonyOS `PiboSoundEffect`; the bundle ships
    /// every runtime file byte-identical to pibo-media `audio.home-sfx`.
    @Test func everyCueIsBundled() {
        #expect(PiboSoundEffect.allCases.count == 12)
        for effect in PiboSoundEffect.allCases {
            #expect(
                PiboSoundEffectService.resourceURL(for: effect) != nil,
                "Missing bundled sound effect: \(effect.assetName).m4a"
            )
        }
    }

    @Test func patCueFollowsReactionState() {
        #expect(PiboSoundEffect.pat(for: .stable) == .patStable)
        #expect(PiboSoundEffect.pat(for: .dataUnknown) == .patStable)
        #expect(PiboSoundEffect.pat(for: .energetic) == .patEnergetic)
        #expect(PiboSoundEffect.pat(for: .tired) == .patTired)
        #expect(PiboSoundEffect.pat(for: .sleeping) == .patSleepy)
        #expect(PiboSoundEffect.pat(for: .waking) == .patSleepy)
    }

    /// The sleep-side pat is the quietest cue so it never reads as waking Pibo.
    @Test func mixMatchesHarmonyTable() {
        let volumes = Dictionary(uniqueKeysWithValues: PiboSoundEffect.allCases.map { ($0, $0.volume) })
        #expect(volumes.values.allSatisfy { $0 > 0 && $0 <= 0.3 })
        #expect(volumes.values.allSatisfy { $0 >= PiboSoundEffect.patSleepy.volume })
        #expect(PiboSoundEffect.patSleepy.volume == 0.14)
        #expect(PiboSoundEffect.stateTransition.volume == 0.18)
        #expect(PiboSoundEffect.boGrowthSparkle.volume == 0.2)
        #expect(PiboSoundEffect.boSproutTouch.volume == 0.28)
    }

    @Test func settingDefaultsOnAndPersistsSeparatelyFromAmbience() throws {
        let suite = "PiboSoundEffectServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = PiboSoundEffectService(defaults: defaults)
        #expect(service.isEnabled)
        defaults.set(false, forKey: PiboPersistenceKeys.Defaults.soundEffectsEnabled)
        #expect(!service.isEnabled)
        #expect(PiboPersistenceKeys.Defaults.soundEffectsEnabled != PiboPersistenceKeys.Defaults.ambientSoundEnabled)
    }
}

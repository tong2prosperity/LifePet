import Foundation
import Testing
@testable import Pibo

@MainActor
struct HomeStageSurfaceInputTests {
    @Test func inputPreservesEveryStageValue() throws {
        let suite = "HomeStageSurfaceInputTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PetStateStore(demoMode: true)
        let animation = HomeAnimationPresentationController(stateID: "weak")
        let environment = PiboStageEnvironment(localHour: 18, weather: .rain)
        let unlocks = OrnamentUnlockStore(
            defaults: defaults,
            ownershipKey: "test.ownership",
            eligibilityKey: "test.eligibility",
            pendingPurchaseKey: "test.pending-purchase",
            debugUnlockOverride: true
        )
        let lights = OrnamentLightStore(defaults: defaults)
        let ledger = BoLedgerStore(
            defaults: defaults,
            persistenceKey: "test.bo-ledger"
        )
        let input = HomeStageSurface.Input(
            store: store,
            boLedger: ledger,
            animationPresentation: animation,
            environment: environment,
            ornamentUnlocks: unlocks,
            ornamentLights: lights,
            tuning: .standard,
            isPaused: true,
            isObscured: false
        )

        #expect(input.theme == store.currentTheme)
        #expect(input.activityState == store.activityState)
        #expect(input.animationStateID == animation.stateID)
        #expect(input.growth == .sprouted)
        #expect(input.boGrowthStage == ledger.growthStage)
        #expect(input.sproutGrowthProgress == ledger.growthProgress)
        #expect(input.environment == environment)
        #expect(input.presentedOrnaments == Set(PiboOrnament.ID.allCases))
        #expect(input.unlockedOrnaments == unlocks.unlocked)
        #expect(input.litOrnamentLights == lights.lit)
        #expect(input.tuning == .standard)
        #expect(input.isPaused)
        #expect(!input.isObscured)
    }
}

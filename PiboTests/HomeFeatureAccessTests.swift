import Foundation
import SwiftUI
import Testing
@testable import Pibo

@MainActor
struct HomeFeatureAccessTests {
    @Test func releaseAndEntitlementGatesPreserveFeatureAvailability() throws {
        let fixture = try Fixture(unlocked: true)
        defer { fixture.cleanUp() }

        let enabled = fixture.access(
            cameraReleased: true,
            walkDoodleReleased: true,
            miniGamesReleased: true
        )
        #expect(enabled.cameraEnabled)
        #expect(enabled.walkDoodleEnabled)
        #expect(enabled.miniGamesEnabled)

        let unreleased = fixture.access(
            cameraReleased: false,
            walkDoodleReleased: false,
            miniGamesReleased: false
        )
        #expect(!unreleased.cameraEnabled)
        #expect(!unreleased.walkDoodleEnabled)
        #expect(!unreleased.miniGamesEnabled)
    }

    @Test func missingEntitlementsKeepReleasedFeaturesUnavailable() throws {
        let fixture = try Fixture(unlocked: false)
        defer { fixture.cleanUp() }

        let access = fixture.access(
            cameraReleased: true,
            walkDoodleReleased: true,
            miniGamesReleased: true
        )

        #expect(!access.cameraEnabled)
        #expect(!access.walkDoodleEnabled)
        #expect(access.miniGamesEnabled)
    }

    @Test func bindingsUseTheResolvedAvailabilityWithoutChangingSetterRules() throws {
        let fixture = try Fixture(unlocked: true)
        defer { fixture.cleanUp() }

        let disabled = fixture.access(
            cameraReleased: false,
            walkDoodleReleased: false,
            miniGamesReleased: false
        )
        disabled.cameraPresented.wrappedValue = true
        disabled.walkDoodlePresented.wrappedValue = true
        disabled.gamesPresented.wrappedValue = true

        #expect(!fixture.presentation.showCamera)
        #expect(!fixture.presentation.showWalkDoodle)
        #expect(fixture.presentation.showGames)
        #expect(!disabled.gamesPresented.wrappedValue)
    }
}

@MainActor
private final class Fixture {
    let suiteName: String
    let defaults: UserDefaults
    let presentation = HomePresentationState()
    let unlocks: OrnamentUnlockStore

    init(unlocked: Bool) throws {
        let resolvedSuiteName = "HomeFeatureAccessTests.\(UUID().uuidString)"
        let resolvedDefaults = try #require(
            UserDefaults(suiteName: resolvedSuiteName)
        )
        suiteName = resolvedSuiteName
        defaults = resolvedDefaults
        unlocks = OrnamentUnlockStore(
            defaults: resolvedDefaults,
            ownershipKey: "test.owned",
            eligibilityKey: "test.eligible",
            pendingPurchaseKey: "test.pending",
            debugUnlockOverride: unlocked
        )
    }

    func access(
        cameraReleased: Bool,
        walkDoodleReleased: Bool,
        miniGamesReleased: Bool
    ) -> HomeFeatureAccess {
        HomeFeatureAccess(
            presentation: presentation,
            ornamentUnlocks: unlocks,
            cameraReleased: cameraReleased,
            walkDoodleReleased: walkDoodleReleased,
            miniGamesReleased: miniGamesReleased
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

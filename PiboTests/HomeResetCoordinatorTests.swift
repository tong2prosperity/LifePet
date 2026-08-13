import Foundation
import Testing
@testable import Pibo

@MainActor
struct HomeResetCoordinatorTests {
    @Test func resetPreservesTheExistingSideEffectOrder() {
        var events: [String] = []

        HomeResetCoordinator.run(handlers: .init(
            trackReset: { events.append("track") },
            resetSpeechHistory: { events.append("speech") },
            resetPetState: { events.append("pet-state") },
            resetBoLedger: { events.append("bo-ledger") },
            resetOnboarding: { events.append("onboarding") },
            resetOrnamentUnlocks: { events.append("ornament-unlocks") },
            resetOrnamentLights: { events.append("ornament-lights") },
            clearFirstRipeAnnouncement: { events.append("first-ripe") }
        ))

        #expect(events == [
            "track",
            "speech",
            "pet-state",
            "bo-ledger",
            "onboarding",
            "ornament-unlocks",
            "ornament-lights",
            "first-ripe",
        ])
    }

    @Test func resetClearsTheFirstRipeAnnouncementPersistenceKey() throws {
        let suiteName = "HomeResetCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = PiboPersistenceKeys.Defaults.boFirstRipeNotified
        defaults.set(true, forKey: key)

        HomeResetCoordinator.clearFirstRipeAnnouncement(in: defaults)

        #expect(defaults.object(forKey: key) == nil)
    }
}

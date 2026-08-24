import Foundation
import PiboCore
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct BoProgressFeedbackTests {
    @Test func ledgerUpdatesUseCoreAndCoalesceToTheHighestMilestone() throws {
        let suite = "BoProgressFeedbackTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BoProgressFeedbackStore(defaults: defaults)

        #expect(store.recordLedgerUpdate(
            previousEnergyPool: 10,
            newEnergyPool: 60,
            mintedCount: 0
        ) == .threeQuarters)
        #expect(store.pending?.milestone == .threeQuarters)
        #expect(store.pending?.previousEnergyPool == 10)
        #expect(store.pending?.newEnergyPool == 60)

        #expect(store.recordLedgerUpdate(
            previousEnergyPool: 0,
            newEnergyPool: 20,
            mintedCount: 0
        ) == .quarter)
        #expect(store.pending?.milestone == .threeQuarters)

        let restored = BoProgressFeedbackStore(defaults: defaults)
        #expect(restored.pending?.milestone == .threeQuarters)
    }

    @Test func mintSupersedesAnUnplayedFractionalReminder() throws {
        let suite = "BoProgressFeedbackMintTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BoProgressFeedbackStore(defaults: defaults)
        store.enqueue(
            .nearMint,
            previousEnergyPool: 60,
            newEnergyPool: 90,
            mintedCount: 0
        )

        #expect(store.recordLedgerUpdate(
            previousEnergyPool: 70,
            newEnergyPool: 5,
            mintedCount: 1
        ) == .minted)
        #expect(store.pending?.milestone == .minted)
        #expect(store.pending?.previousEnergyPool == 60)
        #expect(store.pending?.newEnergyPool == 5)
        #expect(store.pending?.mintedCount == 1)
    }

    @Test func growthBelowANamedBoundaryStillQueuesCausalFeedback() throws {
        let suite = "BoProgressFeedbackSmallGrowthTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BoProgressFeedbackStore(defaults: defaults)

        #expect(store.recordLedgerUpdate(
            previousEnergyPool: 5,
            newEnergyPool: 9,
            mintedCount: 0
        ) == .none)
        #expect(store.pending?.milestone == BoProgressMilestone.none)
        #expect(store.pending?.isPresentable == true)
    }
}

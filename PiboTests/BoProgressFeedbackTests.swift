import Foundation
import PiboCore
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct BoProgressFeedbackTests {
    @Test func badgeRequestCoalescesFeedAndMilestoneIntoOnePass() throws {
        let feedID = UUID()
        let milestoneID = UUID()
        let request = try #require(BoCounterFeedbackRequest(
            feedID: feedID,
            milestoneID: milestoneID
        ))

        #expect(request.id == milestoneID)
        #expect(request.sourceIDs == Set([feedID, milestoneID]))
        #expect(BoCounterFeedbackRequest(feedID: nil, milestoneID: nil) == nil)
    }

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
        store.enqueue(.nearMint)

        #expect(store.recordLedgerUpdate(
            previousEnergyPool: 70,
            newEnergyPool: 5,
            mintedCount: 1
        ) == .minted)
        #expect(store.pending == nil)
    }
}

import Foundation
import Testing
@testable import Pibo

@MainActor
struct PiboContextualActionIntegrationTests {
    @Test func everyCoreStateMapsToItsSingleContextualAction() {
        #expect(PiboCoreAnimationAdapter.contextualAction(for: .dataUnknown) == .checkConnection)
        #expect(PiboCoreAnimationAdapter.contextualAction(for: .sleeping) == .letSleep)
        #expect(PiboCoreAnimationAdapter.contextualAction(for: .waking) == .morningGreeting)
        #expect(PiboCoreAnimationAdapter.contextualAction(for: .stable) == .checkIn)
        #expect(PiboCoreAnimationAdapter.contextualAction(for: .energetic) == .play)
        #expect(PiboCoreAnimationAdapter.contextualAction(for: .tired) == .rest)
    }

    @Test func onlyStableCheckInCountsTowardAngry() {
        for state in PiboActivityState.allCases {
            #expect(
                PiboCoreAnimationAdapter.contextualActionCountsTowardAngry(for: state)
                    == (state == .stable)
            )
        }
    }

    @Test func interruptedHealthDataRetainsCredibleStateOnlyWithPriorRead() {
        let prior = HealthDataService.DataAvailability.temporarilyInterrupted(lastReadableAt: .now)
        let cold = HealthDataService.DataAvailability.temporarilyInterrupted(lastReadableAt: nil)
        #expect(prior.hasReliableData)
        #expect(!cold.hasReliableData)
        #expect(prior.requiresAttention)
    }
}

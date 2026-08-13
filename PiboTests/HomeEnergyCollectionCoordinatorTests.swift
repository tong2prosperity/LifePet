import Testing
@testable import Pibo

@Suite
@MainActor
struct HomeEnergyCollectionCoordinatorTests {
    @Test func dismissPopPreservesEverySideEffectInOrder() {
        var events: [String] = []

        HomeEnergyCollectionCoordinator.dismissPop(handlers: .init(
            tap: { events.append("tap") },
            trackCollected: { events.append("track") },
            consumePendingWorkout: { events.append("consume-workout") },
            finishPop: { events.append("finish-pop") }
        ))

        #expect(events == ["tap", "track", "consume-workout", "finish-pop"])
    }
}

import CoreLocation
import Foundation
import PiboCore
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct WalkDoodleProgressStoreTests {
    @Test func taskIsStableForTheDayAndAdvancesAfterFirstAcceptance() throws {
        let suite = "WalkDoodleProgressStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WalkDoodleProgressStore(defaults: defaults)
        let date = Date.now
        let task = store.task(at: date)

        #expect(store.task(at: date) == task)
        let evaluation = circleEvaluation()
        let committed = store.commit(
            shape: .circle,
            evaluation: evaluation,
            at: date
        )
        #expect(committed.firstAcceptance)
        #expect(committed.day.accepted)
        #expect(committed.day.attemptCount == 1)
        #expect(store.acceptedTaskCount == 1)
        #expect(!committed.eventID.isEmpty)
        #expect(store.rewardOutbox.count == 1)

        let restored = WalkDoodleProgressStore(defaults: defaults)
        #expect(restored.task(at: date) == committed.day)
        #expect(restored.rewardOutbox == store.rewardOutbox)
    }

    @Test func rewardOutboxIsExplicitlyAcknowledged() throws {
        let suite = "WalkDoodleProgressOutboxTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WalkDoodleProgressStore(defaults: defaults)
        let commit = store.commit(
            shape: .circle,
            evaluation: circleEvaluation()
        )
        #expect(store.rewardOutbox.map(\.eventID).contains(commit.eventID))
        store.acknowledgeReward(eventID: commit.eventID)
        #expect(store.rewardOutbox.isEmpty)
    }

    private func circleEvaluation() -> PiboCoreDoodleAdapter.Evaluation {
        let latitude = 31.2304
        let longitude = 121.4737
        let radius = 0.00055
        let coordinates = (0...48).map { index in
            let angle = Double(index) / 48 * 2 * Double.pi
            return CLLocationCoordinate2D(
                latitude: latitude + sin(angle) * radius,
                longitude: longitude + cos(angle) * radius
            )
        }
        return PiboCoreDoodleAdapter.evaluate(
            shape: .circle,
            coordinates: coordinates,
            previousBestScore: 0,
            dailyRewardedEnergy: 0
        )
    }
}

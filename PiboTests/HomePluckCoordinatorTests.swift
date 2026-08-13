import XCTest
@testable import Pibo

@MainActor
final class HomePluckCoordinatorTests: XCTestCase {
    func testFailedLedgerMutationStopsEveryPresentationEffect() {
        let recorder = Recorder(pluckSucceeds: false, cooperationEnabled: true)

        let collected = HomePluckCoordinator.run(handlers: recorder.handlers)

        XCTAssertFalse(collected)
        XCTAssertEqual(recorder.events, ["event-id", "pluck:local-pluck-test"])
    }

    func testSuccessfulPluckPreservesEffectOrderWithoutCooperation() {
        let recorder = Recorder(pluckSucceeds: true, cooperationEnabled: false)

        let collected = HomePluckCoordinator.run(handlers: recorder.handlers)

        XCTAssertTrue(collected)
        XCTAssertEqual(
            recorder.events,
            [
                "event-id", "pluck:local-pluck-test", "balance",
                "track:7:local-pluck-test", "play", "message", "cooperation",
            ]
        )
    }

    func testCooperationReadsLifetimeValuesAfterPresentationAndObservesThemInOrder() {
        let recorder = Recorder(pluckSucceeds: true, cooperationEnabled: true)

        let collected = HomePluckCoordinator.run(handlers: recorder.handlers)

        XCTAssertTrue(collected)
        XCTAssertEqual(
            recorder.events,
            [
                "event-id", "pluck:local-pluck-test", "balance",
                "track:7:local-pluck-test", "play", "message", "cooperation",
                "minted", "collected", "observe:11:4",
            ]
        )
    }
}

@MainActor
private final class Recorder {
    var events: [String] = []

    private let pluckSucceeds: Bool
    private let isCooperationEnabled: Bool

    init(pluckSucceeds: Bool, cooperationEnabled: Bool) {
        self.pluckSucceeds = pluckSucceeds
        self.isCooperationEnabled = cooperationEnabled
    }

    var handlers: HomePluckCoordinator.Handlers {
        .init(
            makeEventID: { [self] in
                events.append("event-id")
                return "local-pluck-test"
            },
            pluck: { [self] eventID in
                events.append("pluck:\(eventID)")
                return pluckSucceeds
            },
            currentBalance: { [self] in
                events.append("balance")
                return 7
            },
            trackPluck: { [self] balance, eventID in
                events.append("track:\(balance):\(eventID)")
            },
            playPluck: { [self] in events.append("play") },
            showCollectedMessage: { [self] in events.append("message") },
            cooperationEnabled: { [self] in
                events.append("cooperation")
                return isCooperationEnabled
            },
            lifetimeMinted: { [self] in
                events.append("minted")
                return 11
            },
            lifetimeCollected: { [self] in
                events.append("collected")
                return 4
            },
            observeBoProgress: { [self] minted, collected in
                events.append("observe:\(minted):\(collected)")
            }
        )
    }
}

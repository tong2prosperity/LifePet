import XCTest
@testable import Pibo

@MainActor
final class HomeFirstRipeBoAnnouncementCoordinatorTests: XCTestCase {
    func testMissingRipeBoShortCircuitsPersistenceAndEffects() {
        let events = EventLog()

        HomeFirstRipeBoAnnouncementCoordinator.announceIfNeeded(
            policy: policy(),
            hasRipeBo: events.read(false, named: "ripe"),
            speechIsAbsent: events.read(true, named: "speech"),
            idleSpeechContextAvailable: events.read(true, named: "context"),
            handlers: handlers(events: events, wasAnnounced: false)
        )

        XCTAssertEqual(events.values, ["ripe"])
    }

    func testExistingAnnouncementShortCircuitsPresentationEffects() {
        let events = EventLog()

        HomeFirstRipeBoAnnouncementCoordinator.announceIfNeeded(
            policy: policy(),
            hasRipeBo: events.read(true, named: "ripe"),
            speechIsAbsent: events.read(true, named: "speech"),
            idleSpeechContextAvailable: events.read(true, named: "context"),
            handlers: handlers(events: events, wasAnnounced: true)
        )

        XCTAssertEqual(events.values, ["ripe", "announced"])
    }

    func testEligibleAnnouncementPersistsBeforeShowingAndNotifying() {
        let events = EventLog()

        HomeFirstRipeBoAnnouncementCoordinator.announceIfNeeded(
            policy: policy(),
            hasRipeBo: events.read(true, named: "ripe"),
            speechIsAbsent: events.read(true, named: "speech"),
            idleSpeechContextAvailable: events.read(true, named: "context"),
            handlers: handlers(events: events, wasAnnounced: false)
        )

        XCTAssertEqual(events.values, [
            "ripe",
            "announced",
            "speech",
            "context",
            "mark-announced",
            "show",
            "notify",
        ])
    }

    private func policy() -> HomePresentationPolicy {
        HomePresentationPolicy(
            sceneIsActive: true,
            cameraPresented: false,
            gamesPresented: false,
            historyPresented: false,
            walkDoodlePresented: false,
            settingsPresented: false,
            storyRecoveryPresented: false,
            sheetPresented: false,
            sheetDismissalInProgress: false,
            sproutFlowIsIdle: true
        )
    }

    private func handlers(
        events: EventLog,
        wasAnnounced: Bool
    ) -> HomeFirstRipeBoAnnouncementCoordinator.Handlers {
        HomeFirstRipeBoAnnouncementCoordinator.Handlers(
            wasAnnounced: {
                events.append("announced")
                return wasAnnounced
            },
            markAnnounced: { events.append("mark-announced") },
            showAnnouncement: { events.append("show") },
            notify: { events.append("notify") }
        )
    }
}

@MainActor
private final class EventLog {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func read<Value>(_ value: Value, named name: String) -> Value {
        append(name)
        return value
    }
}

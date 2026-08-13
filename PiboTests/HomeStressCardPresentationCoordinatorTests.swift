import Testing
@testable import Pibo

@Suite
@MainActor
struct HomeStressCardPresentationCoordinatorTests {
    @Test func missingRequestShortCircuitsEveryMutation() {
        let events = EventLog()

        HomeStressCardPresentationCoordinator.presentIfPossible(
            policy: policy(),
            pendingCardOpen: events.read(false, named: "pending"),
            handlers: handlers(events)
        )

        #expect(events.values == ["pending"])
    }

    @Test func occupiedHomeRetainsThePendingRequest() {
        let events = EventLog()

        HomeStressCardPresentationCoordinator.presentIfPossible(
            policy: policy(coverPresented: true),
            pendingCardOpen: events.read(true, named: "pending"),
            handlers: handlers(events)
        )

        #expect(events.values == ["pending"])
    }

    @Test func eligibleRequestClearsThenFocusesThenPresents() {
        let events = EventLog()

        HomeStressCardPresentationCoordinator.presentIfPossible(
            policy: policy(),
            pendingCardOpen: events.read(true, named: "pending"),
            handlers: handlers(events)
        )

        #expect(events.values == ["pending", "clear", "focus", "present"])
    }

    private func policy(coverPresented: Bool = false) -> HomePresentationPolicy {
        HomePresentationPolicy(
            sceneIsActive: true,
            cameraPresented: coverPresented,
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
        _ events: EventLog
    ) -> HomeStressCardPresentationCoordinator.Handlers {
        HomeStressCardPresentationCoordinator.Handlers(
            clearPendingRequest: { events.append("clear") },
            focusStressCard: { events.append("focus") },
            presentHistory: { events.append("present") }
        )
    }
}

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

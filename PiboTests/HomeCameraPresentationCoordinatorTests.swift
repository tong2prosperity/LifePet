import Testing
@testable import Pibo

@Suite
@MainActor
struct HomeCameraPresentationCoordinatorTests {
    @Test func generalEntryTracksNoneThenClearsMealThenPresents() {
        let events = EventLog()

        HomeCameraPresentationCoordinator.open(
            meal: nil,
            handlers: handlers(events)
        )

        #expect(events.values == ["track:none", "meal:none", "present"])
    }

    @Test func mealEntryForwardsMealAndPreservesMutationOrder() {
        let events = EventLog()

        HomeCameraPresentationCoordinator.openIfEnabled(
            meal: .lunch,
            isEnabled: true,
            handlers: handlers(events)
        )

        #expect(events.values == ["track:lunch", "meal:lunch", "present"])
    }

    @Test func disabledMealEntryHasNoSideEffects() {
        let events = EventLog()

        HomeCameraPresentationCoordinator.openIfEnabled(
            meal: .dinner,
            isEnabled: false,
            handlers: handlers(events)
        )

        #expect(events.values == [])
    }

    private func handlers(
        _ events: EventLog
    ) -> HomeCameraPresentationCoordinator.Handlers {
        HomeCameraPresentationCoordinator.Handlers(
            trackOpen: { events.append("track:\($0?.rawValue ?? "none")") },
            setInitialMeal: { events.append("meal:\($0?.rawValue ?? "none")") },
            presentCamera: { events.append("present") }
        )
    }
}

private final class EventLog {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

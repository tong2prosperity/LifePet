import Testing
@testable import Pibo

@Suite
@MainActor
struct HomeHairPullCoordinatorTests {
    @Test func unripeHairPullTapsThenTurnsAway() {
        let events = EventLog()

        HomeHairPullCoordinator.handle(handlers: handlers(
            events,
            hasRipeBo: false,
            pluckSucceeds: true
        ))

        #expect(events.values == ["tap", "ripe", "turn-away"])
    }

    @Test func ripeHairPullTapsThenAttemptsPluck() {
        let events = EventLog()

        HomeHairPullCoordinator.handle(handlers: handlers(
            events,
            hasRipeBo: true,
            pluckSucceeds: true
        ))

        #expect(events.values == ["tap", "ripe", "pluck"])
    }

    @Test func failedRipePluckDoesNotFallBackToTurnAway() {
        let events = EventLog()

        HomeHairPullCoordinator.handle(handlers: handlers(
            events,
            hasRipeBo: true,
            pluckSucceeds: false
        ))

        #expect(events.values == ["tap", "ripe", "pluck"])
    }

    private func handlers(
        _ events: EventLog,
        hasRipeBo: Bool,
        pluckSucceeds: Bool
    ) -> HomeHairPullCoordinator.Handlers {
        HomeHairPullCoordinator.Handlers(
            tap: { events.append("tap") },
            hasRipeBo: {
                events.append("ripe")
                return hasRipeBo
            },
            pluck: {
                events.append("pluck")
                return pluckSucceeds
            },
            playTurnAway: { events.append("turn-away") }
        )
    }
}

private final class EventLog {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

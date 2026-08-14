import Foundation
import Testing
@testable import Pibo

@MainActor
struct HomeTaskCoordinatorTests {
    @Test func minuteElapsedRefreshesAnimationBeforeLights() {
        let events = EventLog()
        let date = Date(timeIntervalSince1970: 123)

        HomeTaskCoordinator.minuteElapsed(
            at: date,
            handlers: events.handlers
        )

        #expect(events.values == ["animation", "lights:123.0"])
    }

    @Test func systemDateChangeRefreshesClockBeforeAnimation() {
        let events = EventLog()

        HomeTaskCoordinator.systemDateChanged(handlers: events.handlers)

        #expect(events.values == ["clock", "animation"])
    }

    @Test func angryExpiryRefreshesAnimationAtExpiry() {
        let events = EventLog()
        let date = Date(timeIntervalSince1970: 456)

        HomeTaskCoordinator.angryStateExpired(
            at: date,
            handlers: events.handlers
        )

        #expect(events.values == ["animation-at:456.0"])
    }
}

@MainActor
private final class EventLog {
    private(set) var values: [String] = []

    var handlers: HomeTaskCoordinator.Handlers {
        .init(
            refreshClock: { self.values.append("clock") },
            refreshAnimation: { self.values.append("animation") },
            refreshAnimationAt: {
                self.values.append("animation-at:\($0.timeIntervalSince1970)")
            },
            refreshOrnamentLights: {
                self.values.append("lights:\($0.timeIntervalSince1970)")
            }
        )
    }
}

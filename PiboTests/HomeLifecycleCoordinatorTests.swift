import Testing
@testable import Pibo

@MainActor
struct HomeLifecycleCoordinatorTests {
    @Test func appearancePreservesEffectOrder() {
        let events = EventLog()

        HomeLifecycleCoordinator.appeared(
            hasRipeBo: true,
            handlers: events.handlers
        )

        #expect(events.values == [
            "weather",
            "greeting",
            "day-label",
            "entered-speech",
            "animation",
            "debug-automation",
            "achievement",
            "soundscape",
            "morning-sleep",
            "stress-card",
            "ripe-bo",
        ])
    }

    @Test func appearanceWithoutRipeBoSkipsAnnouncement() {
        let events = EventLog()

        HomeLifecycleCoordinator.appeared(
            hasRipeBo: false,
            handlers: events.handlers
        )

        #expect(events.values.last == "stress-card")
        #expect(!events.values.contains("ripe-bo"))
    }
}

@MainActor
private final class EventLog {
    private(set) var values: [String] = []

    var handlers: HomeLifecycleCoordinator.Handlers {
        .init(
            activateWeather: { self.values.append("weather") },
            cacheGreeting: { self.values.append("greeting") },
            cacheDayLabel: { self.values.append("day-label") },
            speakForEnteredWeather: { self.values.append("entered-speech") },
            refreshAnimation: { self.values.append("animation") },
            runDebugAutomation: { self.values.append("debug-automation") },
            presentAchievement: { self.values.append("achievement") },
            startSoundscape: { self.values.append("soundscape") },
            presentMorningSleep: { self.values.append("morning-sleep") },
            presentStressCard: { self.values.append("stress-card") },
            announceFirstRipeBo: { self.values.append("ripe-bo") }
        )
    }
}

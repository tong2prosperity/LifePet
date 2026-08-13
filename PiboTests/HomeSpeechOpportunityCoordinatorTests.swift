import PiboCore
import XCTest
@testable import Pibo

@MainActor
final class HomeSpeechOpportunityCoordinatorTests: XCTestCase {
    func testWeatherMappingPreservesSupportedSpeechCuesAndOmitsFog() {
        let expected: [PiboWeather: PiboSpeechWeather?] = [
            .clear: .clear,
            .cloudy: .cloudy,
            .fog: nil,
            .rain: .rain,
            .thunderstorm: .thunderstorm,
            .snow: .snow,
        ]

        XCTAssertEqual(Set(expected.keys), Set(PiboWeather.allCases))
        for (weather, speechWeather) in expected {
            XCTAssertEqual(
                HomeSpeechOpportunityCoordinator.speechWeather(for: weather),
                speechWeather
            )
        }
    }

    func testPausedWeatherOpportunityShortCircuitsEveryLaterRead() {
        let events = EventLog()

        HomeSpeechOpportunityCoordinator.presentWeatherIfPossible(
            trigger: .entered,
            handlers: weatherHandlers(events: events, stageIsPaused: true)
        )

        XCTAssertEqual(events.values, ["stage"])
    }

    func testUnavailableWeatherShortCircuitsResolutionAndPresentation() {
        let events = EventLog()

        HomeSpeechOpportunityCoordinator.presentWeatherIfPossible(
            trigger: .environmentChanged,
            handlers: weatherHandlers(
                events: events,
                stageIsPaused: false,
                weather: nil
            )
        )

        XCTAssertEqual(events.values, ["stage", "context", "weather"])
    }

    func testEligibleWeatherOpportunityResolvesAndShowsInOrder() {
        let events = EventLog()

        HomeSpeechOpportunityCoordinator.presentWeatherIfPossible(
            trigger: .environmentChanged,
            handlers: weatherHandlers(events: events, stageIsPaused: false)
        )

        XCTAssertEqual(events.values, [
            "stage",
            "context",
            "weather",
            "resolve-rain-environmentChanged",
            "show-weather",
        ])
    }

    func testExistingSpeechShortCircuitsEveryLaterIdleRead() {
        let events = EventLog()

        HomeSpeechOpportunityCoordinator.presentIdleIfPossible(
            handlers: idleHandlers(events: events, speechIsAbsent: false)
        )

        XCTAssertEqual(events.values, ["speech"])
    }

    func testMissingIdleContextShortCircuitsResolutionAndPresentation() {
        let events = EventLog()

        HomeSpeechOpportunityCoordinator.presentIdleIfPossible(
            handlers: idleHandlers(
                events: events,
                speechIsAbsent: true,
                context: nil
            )
        )

        XCTAssertEqual(events.values, ["speech", "sprout", "stage", "context"])
    }

    func testEligibleIdleOpportunityResolvesAndShowsInOrder() {
        let events = EventLog()

        HomeSpeechOpportunityCoordinator.presentIdleIfPossible(
            handlers: idleHandlers(events: events, speechIsAbsent: true)
        )

        XCTAssertEqual(events.values, [
            "speech",
            "sprout",
            "stage",
            "context",
            "resolve-idle",
            "show-idle",
        ])
    }

    private func weatherHandlers(
        events: EventLog,
        stageIsPaused: Bool,
        weather: PiboSpeechWeather? = .rain
    ) -> HomeSpeechOpportunityCoordinator.WeatherHandlers {
        HomeSpeechOpportunityCoordinator.WeatherHandlers(
            stageIsPaused: { events.read(stageIsPaused, named: "stage") },
            idleSpeechContextAvailable: { events.read(true, named: "context") },
            weather: { events.read(weather, named: "weather") },
            resolve: { weather, trigger in
                events.append("resolve-\(weather.rawValue)-\(trigger.rawValue)")
                return self.speech(id: "weather")
            },
            show: { events.append("show-\($0.id)") }
        )
    }

    private func idleHandlers(
        events: EventLog,
        speechIsAbsent: Bool,
        context: PiboCoreHomeSpeechContext? = .idle
    ) -> HomeSpeechOpportunityCoordinator.IdleHandlers {
        HomeSpeechOpportunityCoordinator.IdleHandlers(
            speechIsAbsent: { events.read(speechIsAbsent, named: "speech") },
            sproutIsIdle: { events.read(true, named: "sprout") },
            stageIsPaused: { events.read(false, named: "stage") },
            context: { events.read(context, named: "context") },
            resolve: { context in
                events.append("resolve-\(context)")
                return self.speech(id: "idle")
            },
            show: { events.append("show-\($0.id)") }
        )
    }

    private func speech(id: String) -> PiboSpeech {
        PiboSpeech(
            id: id,
            text: id,
            presentation: .normal,
            cueKey: id
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

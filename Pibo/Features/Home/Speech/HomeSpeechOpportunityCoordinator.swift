import Foundation
import PiboCore

/// Owns Home's ambient speech opportunities. Copy selection and speech budgets
/// remain in `PiboSpeechService`; presentation remains in
/// `HomeSpeechPresentationController`.
@MainActor
enum HomeSpeechOpportunityCoordinator {
    struct WeatherHandlers {
        let stageIsPaused: () -> Bool
        let idleSpeechContextAvailable: () -> Bool
        let weather: () -> PiboSpeechWeather?
        let resolve: (_ weather: PiboSpeechWeather, _ trigger: PiboSpeechTrigger) -> PiboSpeech?
        let show: (PiboSpeech) -> Void
    }

    struct IdleHandlers {
        let speechIsAbsent: () -> Bool
        let sproutIsIdle: () -> Bool
        let stageIsPaused: () -> Bool
        let context: () -> PiboCoreHomeSpeechContext?
        let resolve: (PiboCoreHomeSpeechContext) -> PiboSpeech?
        let show: (PiboSpeech) -> Void
    }

    static func presentWeatherIfPossible(
        trigger: PiboSpeechTrigger,
        stageIsPaused: @autoclosure @escaping () -> Bool,
        idleSpeechContext: @autoclosure @escaping () -> PiboCoreHomeSpeechContext?,
        weather: @autoclosure @escaping () -> PiboWeather,
        speech: PiboSpeechService,
        show: @escaping (PiboSpeech) -> Void
    ) {
        presentWeatherIfPossible(
            trigger: trigger,
            handlers: WeatherHandlers(
                stageIsPaused: { stageIsPaused() },
                idleSpeechContextAvailable: { idleSpeechContext() != nil },
                weather: { speechWeather(for: weather()) },
                resolve: { weather, trigger in
                    speech.resolve(
                        cues: [.weather(weather)],
                        context: .home(trigger: trigger)
                    )
                },
                show: show
            )
        )
    }

    static func presentWeatherIfPossible(
        trigger: PiboSpeechTrigger,
        handlers: WeatherHandlers
    ) {
        guard !handlers.stageIsPaused(),
              handlers.idleSpeechContextAvailable(),
              let weather = handlers.weather(),
              let line = handlers.resolve(weather, trigger)
        else { return }

        handlers.show(line)
    }

    static func speechWeather(for weather: PiboWeather) -> PiboSpeechWeather? {
        PiboSpeechWeather(rawValue: weather.rawValue)
    }

    static func runIdleLoop(
        speechIsAbsent: @escaping () -> Bool,
        sproutIsIdle: @escaping () -> Bool,
        stageIsPaused: @escaping () -> Bool,
        context: @escaping () -> PiboCoreHomeSpeechContext?,
        storyStage: @escaping () -> PiboCoreStorySpeechStage,
        facts: @escaping () -> PiboHomeSpeechFacts,
        values: @escaping () -> [String: String],
        speech: PiboSpeechService,
        show: @escaping (PiboSpeech) -> Void
    ) async {
        await runIdleLoop(handlers: IdleHandlers(
            speechIsAbsent: speechIsAbsent,
            sproutIsIdle: sproutIsIdle,
            stageIsPaused: stageIsPaused,
            context: context,
            resolve: { context in
                speech.resolveIdle(
                    context: context,
                    storyStage: storyStage(),
                    facts: facts(),
                    values: values()
                )
            },
            show: show
        ))
    }

    static func runIdleLoop(handlers: IdleHandlers) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 15...30)))
            presentIdleIfPossible(handlers: handlers)
        }
    }

    static func presentIdleIfPossible(handlers: IdleHandlers) {
        guard handlers.speechIsAbsent(),
              handlers.sproutIsIdle(),
              !handlers.stageIsPaused(),
              let context = handlers.context(),
              let line = handlers.resolve(context)
        else { return }

        handlers.show(line)
    }
}

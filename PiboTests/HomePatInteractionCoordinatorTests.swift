import PiboCore
import Testing
@testable import Pibo

@MainActor
struct HomePatInteractionCoordinatorTests {
    @Test func speechCooldownSuppressesOnlySpeechEffects() {
        var events: [String] = []
        let input = PiboPatConversationInput(
            state: .stable,
            episodeKey: "stable",
            storyStage: "unresponded"
        )
        let handlers = HomePatInteractionCoordinator.Handlers(
            react: { action, state in
                #expect(action == .checkIn)
                #expect(state == .stable)
                events.append("reaction")
            },
            resolveSpeech: {
                events.append("resolve")
                return .speechSuppressed
            },
            presentHealthStatus: { events.append("side-effect") },
            show: { _ in events.append("speech") },
            trackSpeech: { _ in events.append("analytics") }
        )

        HomePatInteractionCoordinator.run(input: input, handlers: handlers)
        HomePatInteractionCoordinator.run(input: input, handlers: handlers)

        #expect(events == ["reaction", "resolve", "reaction", "resolve"])
    }

    @Test func acceptedSpeechRunsAfterTheImmediateReaction() {
        var events: [String] = []
        let input = PiboPatConversationInput(
            state: .dataUnknown,
            episodeKey: "authorization",
            storyStage: "unresponded"
        )
        let resolution = PiboPatResolution(
            speechAccepted: true,
            text: "我还看不到记录。",
            speaker: .pibo,
            action: .checkConnection,
            shouldExecuteSideEffect: true,
            interactionCompleted: true,
            context: .dataUnknownAuthorization
        )

        HomePatInteractionCoordinator.run(
            input: input,
            handlers: HomePatInteractionCoordinator.Handlers(
                react: { action, state in
                    #expect(action == .checkConnection)
                    #expect(state == .dataUnknown)
                    events.append("reaction")
                },
                resolveSpeech: {
                    events.append("resolve")
                    return resolution
                },
                presentHealthStatus: { events.append("side-effect") },
                show: { line in
                    #expect(line.text == "我还看不到记录。")
                    #expect(line.lingerDuration == 3)
                    events.append("speech")
                },
                trackSpeech: { tracked in
                    #expect(tracked == resolution)
                    events.append("analytics")
                }
            )
        )

        #expect(events == ["reaction", "resolve", "speech", "side-effect", "analytics"])
    }
}

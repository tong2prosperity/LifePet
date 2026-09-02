import Foundation
import PiboCore

/// Gives every accepted physical pat immediate feedback, then independently
/// asks the shared conversation contract whether a speech line may appear.
@MainActor
enum HomePatInteractionCoordinator {
    struct Handlers {
        let react: (PiboCoreAnimationAdapter.ContextualAction, PiboActivityState) -> Void
        let resolveSpeech: () -> PiboPatResolution
        let presentHealthStatus: () -> Void
        let show: (PiboSpeechLine) -> Void
        let trackSpeech: (PiboPatResolution) -> Void
    }

    static func run(
        input: PiboPatConversationInput,
        speech: PiboSpeechService,
        contextualActions: HomeContextualActionCoordinator,
        stageCommands: PiboStageCommandController,
        presentHealthStatus: @escaping () -> Void,
        show: @escaping (PiboSpeechLine) -> Void
    ) {
        run(
            input: input,
            handlers: Handlers(
                react: { action, state in
                    LPHaptics.tap()
                    contextualActions.restart(
                        action: action,
                        state: state,
                        stageCommands: stageCommands
                    )
                },
                resolveSpeech: { speech.resolvePatConversation(input) },
                presentHealthStatus: presentHealthStatus,
                show: show,
                trackSpeech: { resolution in
                    Analytics.track(
                        .pat,
                        screen: "home",
                        [
                            "reaction": .string(resolution.action?.rawValue ?? "speech"),
                            "context": .string(String(resolution.context.rawValue)),
                            "has_next": .bool(resolution.hasNext),
                        ]
                    )
                }
            )
        )
    }

    static func run(input: PiboPatConversationInput, handlers: Handlers) {
        handlers.react(PiboCoreAnimationAdapter.contextualAction(for: input.state), input.state)
        let resolution = handlers.resolveSpeech()
        guard resolution.speechAccepted, let text = resolution.text else { return }

        var line = PiboSpeechLine(
            text: text,
            source: resolution.speaker == .system ? .system : .pibo
        )
        line.hasNext = resolution.hasNext
        line.lingerDuration = PiboCorePatAdapter.speechCooldownDurationSeconds
        handlers.show(line)

        if resolution.shouldExecuteSideEffect,
           resolution.action == .checkConnection {
            handlers.presentHealthStatus()
        }
        handlers.trackSpeech(resolution)
    }
}

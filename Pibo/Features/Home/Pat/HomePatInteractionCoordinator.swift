import Foundation
import PiboCore

/// Resolves one accepted tap through the shared Core conversation contract.
/// CD rejection is intentionally inert: no haptic, animation, speech, or queue.
@MainActor
enum HomePatInteractionCoordinator {
    static func run(
        input: PiboPatConversationInput,
        speech: PiboSpeechService,
        contextualActions: HomeContextualActionCoordinator,
        stageCommands: PiboStageCommandController,
        presentHealthStatus: @escaping () -> Void,
        show: @escaping (PiboSpeechLine) -> Void
    ) {
        let resolution = speech.resolvePatConversation(input)
        guard resolution.accepted, let text = resolution.text else { return }

        LPHaptics.tap()
        var line = PiboSpeechLine(
            text: text,
            source: resolution.speaker == .system ? .system : .pibo
        )
        line.hasNext = resolution.hasNext
        line.lingerDuration = PiboCorePatAdapter.interactionDurationSeconds
        show(line)

        if resolution.shouldExecuteAction,
           let action = resolution.action?.contextualAction {
            _ = contextualActions.begin(
                action: action,
                state: input.state,
                stageCommands: stageCommands
            )
            if action == .checkConnection { presentHealthStatus() }
        }
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
}

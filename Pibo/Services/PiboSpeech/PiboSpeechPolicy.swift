import Foundation

/// Global silence rules. Copy matching remains in the catalog; this type only
/// decides whether the current surface has already used its speech budget.
struct PiboSpeechPolicy {
    func canSpeak(
        in context: PiboSpeechContext,
        history: PiboSpeechHistory
    ) -> Bool {
        switch (context.surface, context.trigger) {
        case (.home, .entered):
            return history.count(for: scope(for: context)) < 1
        case (.home, .environmentChanged):
            return history.count(for: scope(for: context)) < 1
        case (.home, .idle):
            return history.count(for: scope(for: context)) < 2
        default:
            // User-opened cards and completed actions are naturally scarce and
            // should not be blocked by ambient speech elsewhere in the app.
            return true
        }
    }

    func scope(for context: PiboSpeechContext) -> String {
        "\(context.surface.rawValue).\(context.trigger.rawValue)"
    }
}

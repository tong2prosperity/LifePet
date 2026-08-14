import Foundation

/// Owns the one-shot side effects that follow the first ripe `bo` eligibility
/// decision. Eligibility itself remains in `HomePresentationPolicy`.
@MainActor
enum HomeFirstRipeBoAnnouncementCoordinator {
    struct Handlers {
        let wasAnnounced: () -> Bool
        let markAnnounced: () -> Void
        let showAnnouncement: () -> Void
        let notify: () -> Void
    }

    static func announceIfNeeded(
        policy: HomePresentationPolicy,
        hasRipeBo: @autoclosure () -> Bool,
        speechIsAbsent: @autoclosure () -> Bool,
        idleSpeechContextAvailable: @autoclosure () -> Bool,
        show: @escaping (PiboSpeechLine) -> Void
    ) {
        let key = PiboPersistenceKeys.Defaults.boFirstRipeNotified
        announceIfNeeded(
            policy: policy,
            hasRipeBo: hasRipeBo(),
            speechIsAbsent: speechIsAbsent(),
            idleSpeechContextAvailable: idleSpeechContextAvailable(),
            handlers: Handlers(
                wasAnnounced: { UserDefaults.standard.bool(forKey: key) },
                markAnnounced: { UserDefaults.standard.set(true, forKey: key) },
                showAnnouncement: {
                    show(PiboSpeechLine(
                        text: AppLocalization.narrative("home.bo.firstRipe")
                    ))
                },
                notify: {
                    Task { await WorkoutCompletionNotifier.shared.notifyFirstBoRipened() }
                }
            )
        )
    }

    static func announceIfNeeded(
        policy: HomePresentationPolicy,
        hasRipeBo: @autoclosure () -> Bool,
        speechIsAbsent: @autoclosure () -> Bool,
        idleSpeechContextAvailable: @autoclosure () -> Bool,
        handlers: Handlers
    ) {
        guard policy.shouldAnnounceFirstRipeBo(
            hasRipeBo: hasRipeBo(),
            wasAnnounced: handlers.wasAnnounced(),
            speechIsAbsent: speechIsAbsent(),
            idleSpeechContextAvailable: idleSpeechContextAvailable()
        ) else { return }

        handlers.markAnnounced()
        handlers.showAnnouncement()
        handlers.notify()
    }
}

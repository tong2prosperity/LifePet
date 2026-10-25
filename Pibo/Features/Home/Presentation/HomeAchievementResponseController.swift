import Foundation
import Observation
import UIKit

/// Decision 055: an event in the existing forest, never a modal or a reward.
/// Timing is platform playback, matching Harmony's 7.2 s response / 3 s seen point.
@MainActor
@Observable
final class HomeAchievementResponseController {
    struct Environment {
        var pending: () -> PiboAnimationAchievementPayload? = { nil }
        var appActive: () -> Bool = { false }
        var blocked: () -> Bool = { false }
        var actorPresent: () -> Bool = { true }
        var animationStateID: () -> String = { "" }
        var currentLine: () -> PiboSpeechLine? = { nil }
        var steps: () -> Int = { 0 }
        var show: (PiboSpeechLine) -> Void = { _ in }
        var dismiss: () -> Void = {}
        var complete: (PiboAnimationAchievementPayload) -> Void = { _ in }
    }

    private(set) var active: PiboAnimationAchievementPayload?
    @ObservationIgnored var environment = Environment()
    @ObservationIgnored private var line: PiboSpeechLine?
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var completionTask: Task<Void, Never>?

    func reconcile(now: Date = .now) {
        if let active {
            if !environment.appActive() { leaveHome(now: now); return }
            if environment.pending()?.id != active.id || environment.blocked()
                || !PiboCoreAnimationAdapter.achievementPresentationAllowed(in: environment.animationStateID())
                || environment.currentLine() != line
                || now.timeIntervalSince(startedAt ?? now) >= 7.2 {
                finish()
            }
            return
        }
        guard environment.appActive(), !environment.blocked(), environment.actorPresent(),
              environment.currentLine() == nil,
              PiboCoreAnimationAdapter.achievementPresentationAllowed(in: environment.animationStateID()),
              let pending = environment.pending(), Calendar.current.isDate(pending.occurredAt, inSameDayAs: now)
        else { return }
        active = pending
        startedAt = now
        var speech = PiboSpeechLine(text: Self.text(for: pending.kind), lingerDuration: 7.2)
        if let label = pending.workoutLabel, let minutes = pending.workoutDurationMinutes, pending.kind == .pigu {
            speech.fact = AppLocalization.format("%@ · %d 分钟", label, minutes)
        } else if pending.kind == .muscle {
            speech.fact = AppLocalization.format("今天 %@ 步", environment.steps().formatted())
        }
        line = speech
        environment.show(speech)
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement,
                                 argument: [speech.text, speech.fact].compactMap { $0 }.joined(separator: " "))
        }
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(7200))
            guard !Task.isCancelled, self?.active?.id == pending.id else { return }
            self?.finish()
        }
    }

    func finish() {
        guard let payload = active else { return }
        clear()
        // Completion compares the ID again: a newer workout must remain pending.
        environment.complete(payload)
    }

    func leaveHome(now: Date = .now) {
        guard let payload = active else { return }
        let seen = now.timeIntervalSince(startedAt ?? now) >= 3
        clear()
        if seen { environment.complete(payload) }
    }

    private func clear() {
        completionTask?.cancel()
        completionTask = nil
        if environment.currentLine() == line { environment.dismiss() }
        active = nil
        line = nil
        startedAt = nil
    }

    private static func text(for kind: PiboAnimationAchievementKind) -> String {
        switch PiboCoreAnimationAdapter.achievementContentID(kind: kind, modal: true) {
        case "animation.pigu.modal": AppLocalization.text("你动起来以后，我这里也有了变化。")
        case "animation.muscle.modal": AppLocalization.text("走了这么远，我也想试试这个姿势。")
        default: ""
        }
    }
}

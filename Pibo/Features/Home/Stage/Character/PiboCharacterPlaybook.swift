import Foundation

/// A short scripted performance: play these states in order, hold each, then
/// return to whatever ambient state the health data says Pibo should be in.
///
/// This is the mechanism behind "finished a workout → 秀肌肉 → 娇羞 → 回常驻态".
/// It is deliberately separate from the ambient state machine: ambient states
/// describe a *condition* and can sit for hours, a playbook is a *performance*
/// and always ends. `muscle` and `pigu` are the two states the designer gave an
/// intro flourish to, precisely because they are meant for moments like this.
///
/// The rules for *when* to run one belong in `pibo-core` alongside the existing
/// six-state machine — this type only executes what it is handed.
@MainActor
final class PiboCharacterPlaybook {
    struct Beat {
        let stateID: String
        /// How long to stay once the transition has settled.
        let hold: TimeInterval

        init(_ stateID: String, hold: TimeInterval = 1.6) {
            self.stateID = stateID
            self.hold = hold
        }
    }

    private(set) var isPlaying = false

    private let transition: PiboStateTransition
    private var queue: [Beat] = []
    private var holdRemaining: TimeInterval = 0
    private var waitingOnSettle = false
    /// Where to return once the performance ends. Captured at the start so an
    /// ambient change arriving mid-performance is honoured rather than lost.
    private var ambientStateID: String

    init(transition: PiboStateTransition, ambientStateID: String) {
        self.transition = transition
        self.ambientStateID = ambientStateID
        // Chain rather than replace: the idle animator also listens for settle so
        // a combo restarts from its own zero.
        let existing = transition.onSettled
        transition.onSettled = { [weak self] in
            existing?()
            self?.handleSettled()
        }
    }

    /// Updates the ambient state. During a performance this only records where to
    /// return to; the performance is never cut short by a data update, because a
    /// summary that vanishes mid-flourish reads as a glitch.
    func setAmbient(_ stateID: String) {
        ambientStateID = stateID
        guard !isPlaying else { return }
        transition.transition(to: stateID)
    }

    func play(_ beats: [Beat]) {
        guard !beats.isEmpty else { return }
        queue = beats
        isPlaying = true
        advance()
    }

    /// Ends the performance immediately and heads back to ambient.
    func cancel() {
        queue.removeAll()
        holdRemaining = 0
        waitingOnSettle = false
        guard isPlaying else { return }
        isPlaying = false
        transition.transition(to: ambientStateID)
    }

    func update(deltaTime: TimeInterval) {
        guard isPlaying, !waitingOnSettle, holdRemaining > 0 else { return }
        holdRemaining -= max(0, deltaTime)
        if holdRemaining <= 0 { advance() }
    }

    // MARK: - Private

    private func handleSettled() {
        guard isPlaying, waitingOnSettle else { return }
        waitingOnSettle = false
        // The hold starts once the shape has landed, so the pose is actually
        // readable for its full duration rather than being eaten by the morph.
        if holdRemaining <= 0 { advance() }
    }

    private func advance() {
        guard let beat = queue.first else {
            isPlaying = false
            transition.transition(to: ambientStateID)
            return
        }
        queue.removeFirst()
        holdRemaining = beat.hold
        waitingOnSettle = true
        transition.transition(to: beat.stateID)
    }
}

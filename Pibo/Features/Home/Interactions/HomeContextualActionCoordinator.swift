import Foundation
import Observation

/// Owns the short-lived behavior layered over Core's health state. It never
/// changes that state, and a newly resolved health state cancels the behavior.
@MainActor
@Observable
final class HomeContextualActionCoordinator {
    private(set) var runningAction: PiboCoreAnimationAdapter.ContextualAction?
    private var sourceState: PiboActivityState?
    @ObservationIgnored private var completionTask: Task<Void, Never>?

    func begin(
        action: PiboCoreAnimationAdapter.ContextualAction,
        state: PiboActivityState,
        stageCommands: PiboStageCommandController
    ) -> Bool {
        guard runningAction == nil else { return false }
        runningAction = action
        sourceState = state
        stageCommands.playContextualAction(action)
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: action.duration)
            guard !Task.isCancelled else { return }
            self?.runningAction = nil
            self?.sourceState = nil
        }
        return true
    }

    func cancelIfStateChanged(
        to state: PiboActivityState,
        stageCommands: PiboStageCommandController
    ) {
        guard let sourceState, sourceState != state else { return }
        completionTask?.cancel()
        completionTask = nil
        runningAction = nil
        self.sourceState = nil
        stageCommands.cancelContextualAction()
    }
}

import Foundation
import Observation

/// Owns the animation state presented by Home after Core resolution and the
/// optional Debug-only override. Thresholds and deterministic selection remain
/// in `PiboCoreAnimationAdapter` through the existing input/state resolvers.
@MainActor
@Observable
final class HomeAnimationPresentationController {
    private(set) var stateID: String
    private(set) var state: PiboActivityState = .dataUnknown
    private(set) var decision: PiboCoreStateAdapter.Decision?

    #if DEBUG
    var forcedStateID: String?
    private(set) var coreStateID: String
    #endif

    init(stateID: String? = nil) {
        let resolvedStateID = stateID ?? PiboAnimationStateMap.fallback
        self.stateID = resolvedStateID
        #if DEBUG
        forcedStateID = HomeDebugLaunchOptions.current.forcedAnimationStateID
        coreStateID = resolvedStateID
        #endif
    }

    func refresh(
        store: PetStateStore,
        history: HealthHistoryStore,
        now: Date = .now
    ) {
        store.animationExperience.refreshExpiries(now: now)
        let calendar = Calendar.current
        let historyWindow = HomeAnimationInputResolver.sleepHistoryWindow(
            at: now,
            calendar: calendar
        )
        let records = history.records(
            from: historyWindow.start,
            to: historyWindow.end
        )
        let input = HomeAnimationInputResolver.resolve(
            at: now,
            calendar: calendar,
            records: records,
            hasActivityData: store.hasStepsData,
            steps: store.rawSteps,
            lastWorkoutEndedAt: store.lastWorkoutEndedAt
        )
        let resolution = HomeAnimationStateResolver.resolve(input)
        state = resolution.state
        decision = resolution.decision
        store.publishPiboState(resolution.state)

        #if DEBUG
        coreStateID = resolution.stateID
        stateID = Self.presentedStateID(
            coreStateID: resolution.stateID,
            forcedStateID: forcedStateID
        )
        #else
        stateID = resolution.stateID
        #endif
    }

    static func presentedStateID(
        coreStateID: String,
        forcedStateID: String?
    ) -> String {
        guard let forcedStateID,
              PiboAnimationStateMap.available.contains(forcedStateID)
        else { return coreStateID }
        return forcedStateID
    }

    static func debugBounceTarget(
        previousStateID: String,
        presentedStateID: String,
        usesBounceCut: Bool
    ) -> String? {
        guard usesBounceCut, presentedStateID != previousStateID else { return nil }
        return presentedStateID
    }

    #if DEBUG
    /// Selects a developer override and returns the new target only when the
    /// existing tuning panel should issue its authored bounce cut.
    func selectDebugState(
        _ selectedStateID: String?,
        usesBounceCut: Bool,
        store: PetStateStore,
        history: HealthHistoryStore,
        now: Date = .now
    ) -> String? {
        let previous = stateID
        forcedStateID = selectedStateID
        refresh(store: store, history: history, now: now)
        return Self.debugBounceTarget(
            previousStateID: previous,
            presentedStateID: stateID,
            usesBounceCut: usesBounceCut
        )
    }

    /// Deterministic capture automation needs one stable destination frame
    /// before it asks the renderer to perform the exact bounce-cut timeline.
    func prepareDebugBounce(to stateID: String) {
        self.stateID = stateID
    }
    #endif
}

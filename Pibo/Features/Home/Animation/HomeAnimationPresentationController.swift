import Foundation
import Observation
import PiboCore

/// Owns the animation state presented by Home after Core resolution and the
/// optional Debug-only override. Thresholds and deterministic selection remain
/// in `PiboCoreAnimationAdapter` through the existing input/state resolvers.
@MainActor
@Observable
final class HomeAnimationPresentationController {
    private(set) var stateID: String
    private(set) var state: PiboActivityState = .dataUnknown
    private(set) var decision: PiboCoreStateAdapter.Decision?
    private var lifecycleSnapshot: PiboCoreStateSnapshot
    private var hasHammock = false

    /// The semantic state used by pat interactions. Production always follows
    /// Core; Debug may mirror the animation picker so copy and reactions can be
    /// reviewed without manufacturing HealthKit history.
    var patState: PiboActivityState {
        #if DEBUG
        Self.resolvedPatState(coreState: state, debugForcedStateID: forcedStateID)
        #else
        state
        #endif
    }

    var patEpisodeKey: String {
        let event = lifecycleSnapshot.eventAt ?? 0
        let wake = lifecycleSnapshot.wakeStartedAt ?? 0
        #if DEBUG
        let validOverride = forcedStateID.flatMap {
            PiboAnimationStateMap.available.contains($0) ? $0 : nil
        }
        return "\(patState.rawValue):\(event):\(wake):\(validOverride ?? "core")"
        #else
        return "\(state.rawValue):\(event):\(wake)"
        #endif
    }

    var wakeStartedAt: Date? {
        lifecycleSnapshot.wakeStartedAt.map(Date.init(timeIntervalSince1970:))
    }

    var stateOccurredAt: Date? {
        lifecycleSnapshot.eventAt.map(Date.init(timeIntervalSince1970:))
    }

    #if DEBUG
    var forcedStateID: String?
    private(set) var coreStateID: String
    #endif

    init(stateID: String? = nil) {
        let resolvedStateID = stateID ?? PiboAnimationStateMap.fallback
        self.stateID = resolvedStateID
        lifecycleSnapshot = PiboStateLifecyclePersistence.load()
        #if DEBUG
        forcedStateID = HomeDebugLaunchOptions.current.forcedAnimationStateID
        coreStateID = resolvedStateID
        #endif
    }

    func refresh(
        store: PetStateStore,
        history: HealthHistoryStore,
        hasHammock: Bool? = nil,
        hasReliableHealthData: Bool? = nil,
        now: Date = .now
    ) {
        if let hasHammock { self.hasHammock = hasHammock }
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
        let resolved = HomeAnimationInputResolver.resolve(
            snapshot: lifecycleSnapshot,
            at: now,
            calendar: calendar,
            records: records,
            hasActivityData: hasReliableHealthData ?? store.hasRealHealthData,
            lastWorkoutEndedAt: store.lastWorkoutEndedAt,
            activityMilestoneReachedAt: store.lastActivityMilestoneReachedAt
        )
        lifecycleSnapshot = resolved.snapshot
        PiboStateLifecyclePersistence.save(lifecycleSnapshot)
        let resolution = HomeAnimationStateResolver.resolve(resolved.input)
        state = resolution.state
        decision = resolution.decision
        store.publishPiboState(resolution.state)
        let presentedStateID = PiboAnimationStateMap.presentedAmbientStateID(
            semanticStateID: resolution.stateID,
            state: resolution.state,
            hasHammock: self.hasHammock,
            needsWakingRecovery: resolution.decision.pendingState == .tired
                && resolution.decision.pendingCause == .insufficientSleep
        )

        #if DEBUG
        coreStateID = presentedStateID
        stateID = Self.presentedStateID(
            coreStateID: presentedStateID,
            forcedStateID: forcedStateID
        )
        #else
        stateID = presentedStateID
        #endif
    }

    func resetLifecycle() {
        lifecycleSnapshot = PiboCoreStatePolicy.initialSnapshot()
        PiboStateLifecyclePersistence.reset()
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

    /// Maps a visual override to the nearest one of Core's six semantic states
    /// for copy QA only. Release builds compile out the override branch and
    /// unconditionally return the real Core state.
    static func resolvedPatState(
        coreState: PiboActivityState,
        debugForcedStateID: String?
    ) -> PiboActivityState {
        #if DEBUG
        guard let debugForcedStateID,
              PiboAnimationStateMap.available.contains(debugForcedStateID)
        else { return coreState }
        if debugForcedStateID == PiboAnimationResourceID.activityMilestoneCelebrate
            || debugForcedStateID == PiboAnimationResourceID.workoutCelebrate {
            return .energetic
        }
        return PiboCoreAnimationAdapter.semanticState(for: debugForcedStateID)
        #else
        return coreState
        #endif
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

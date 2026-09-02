#if DEBUG
import Testing
@testable import Pibo

@MainActor
struct HomeDebugControlsStateTests {
    @Test func selectionPassesCurrentIntentIntoResolutionBeforeTransitioning() {
        let state = HomeDebugControlsState(usesBounceCut: true)
        var events: [String] = []

        state.selectAnimationState(
            "dive",
            resolve: { stateID, usesBounceCut in
                events.append("resolve:\(stateID ?? "nil"):\(usesBounceCut)")
                return "resolved-dive"
            },
            transition: { events.append("transition:\($0)") }
        )

        #expect(events == ["resolve:dive:true", "transition:resolved-dive"])
    }

    @Test func rejectedSelectionDoesNotIssueAStageTransition() {
        let state = HomeDebugControlsState()
        var transitionedStateID: String?

        state.selectAnimationState(
            nil,
            resolve: { _, _ in nil },
            transition: { transitionedStateID = $0 }
        )

        #expect(transitionedStateID == nil)
    }
}
#endif

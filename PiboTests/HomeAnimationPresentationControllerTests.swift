import Testing
@testable import Pibo

@MainActor
struct HomeAnimationPresentationControllerTests {
    @Test func validDebugOverrideReplacesOnlyThePresentedState() {
        #expect(HomeAnimationPresentationController.presentedStateID(
            coreStateID: "pibo-state-stable-forest-idle",
            forcedStateID: "dive"
        ) == "dive")
    }

    @Test func absentOrUnknownDebugOverridePreservesCoreState() {
        #expect(HomeAnimationPresentationController.presentedStateID(
            coreStateID: "boring",
            forcedStateID: nil
        ) == "boring")
        #expect(HomeAnimationPresentationController.presentedStateID(
            coreStateID: "boring",
            forcedStateID: "unknown"
        ) == "boring")
    }

    @Test func debugBounceRequiresBothIntentAndAChangedPresentedState() {
        #expect(HomeAnimationPresentationController.debugBounceTarget(
            previousStateID: "pibo-state-stable-forest-idle",
            presentedStateID: "dive",
            usesBounceCut: true
        ) == "dive")
        #expect(HomeAnimationPresentationController.debugBounceTarget(
            previousStateID: "pibo-state-stable-forest-idle",
            presentedStateID: "dive",
            usesBounceCut: false
        ) == nil)
        #expect(HomeAnimationPresentationController.debugBounceTarget(
            previousStateID: "dive",
            presentedStateID: "dive",
            usesBounceCut: true
        ) == nil)
    }

    #if DEBUG
    @Test func capturePreparationChangesOnlyThePresentedState() {
        let controller = HomeAnimationPresentationController(stateID: "pibo-state-stable-forest-idle")
        let originalCoreState = controller.coreStateID
        let originalForcedState = controller.forcedStateID

        controller.prepareDebugBounce(to: "dive")

        #expect(controller.stateID == "dive")
        #expect(controller.coreStateID == originalCoreState)
        #expect(controller.forcedStateID == originalForcedState)
    }
    #endif
}

import Testing
@testable import Pibo

@MainActor
struct PiboStageRenderControllerTests {
    @Test func commonItemOverlayUsesReducedCadenceWithoutPausingTheScene() {
        let controller = PiboStageRenderController()

        #expect(controller.preferredFramesPerSecond(
            isPaused: false,
            isObscured: true,
            displayMaximum: 120
        ) == 30)
        #expect(controller.preferredFramesPerSecond(
            isPaused: true,
            isObscured: true,
            displayMaximum: 120
        ) == 1)
    }
}

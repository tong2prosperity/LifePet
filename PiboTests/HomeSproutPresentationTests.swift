import Testing
@testable import Pibo

struct HomeSproutPresentationTests {
    @Test func closeupPhasesProvideTheirExistingCaptionsAndObscureChrome() {
        #expect(
            SproutFlowPhase.collecting.closeupCaptionText
                == "收到一条新的运动记录"
        )
        #expect(
            SproutFlowPhase.sprouted.closeupCaptionText
                == "Pibo 记下了这次变化"
        )
        #expect(SproutFlowPhase.collecting.obscuresHomeChrome)
        #expect(SproutFlowPhase.sprouted.obscuresHomeChrome)
    }

    @Test func idleAndPopHaveNoCaptionAndKeepChromeVisible() {
        #expect(SproutFlowPhase.idle.closeupCaptionText == nil)
        #expect(SproutFlowPhase.pop.closeupCaptionText == nil)
        #expect(!SproutFlowPhase.idle.obscuresHomeChrome)
        #expect(!SproutFlowPhase.pop.obscuresHomeChrome)
    }
}

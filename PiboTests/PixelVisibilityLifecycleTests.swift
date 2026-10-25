import Foundation
import PiboCore
import CoreGraphics
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct PixelVisibilityLifecycleTests {
    @Test func pixelHidingDefersSpeechUntilTheActorReturns() throws {
        final class QuietBrain: PixelDayBrain {
            func next(previous: PiboDayActivity) -> PixelDayPlan? { nil }
            func slow() -> Bool { false }
        }
        let key = "PixelVisibilityLifecycleTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let now = Date().timeIntervalSince1970
        let memory = PiboCompanionStore(defaults: defaults, clock: { now })
        let companion = HomeCompanionController(store: memory, clock: { now })
        let renderer = PixelStageRenderer()
        let brain = QuietBrain()
        renderer.brain = brain
        let look = PixelStageRenderer.Look()
        _ = renderer.render(size: CGSize(width: 402, height: 874), scale: 3, now: now * 1000, look: look)
        companion.environment = .init(appActive: { true }, state: { .stable },
                                      actorPresent: { renderer.actorPresent }, hasAnswerWish: { true })
        defer { companion.leaveHome() }
        renderer.director.greet(.hide, find: -1, hideSpot: .tallGrass,
                                hideMs: Double(PiboCoreDayRules.hideSeconds()) * 1000)
        _ = renderer.render(size: CGSize(width: 402, height: 874), scale: 3, now: now * 1000 + 50, look: look)
        #expect(renderer.director.hiding)
        #expect(!renderer.actorPresent)
        companion.tick()
        #expect(!companion.wishPromptReady)
        #expect(!companion.claimStoryLine())
        renderer.director.found()
        for frame in 2...240 {
            _ = renderer.render(size: CGSize(width: 402, height: 874), scale: 3,
                                now: now * 1000 + Double(frame * 50), look: look)
        }
        #expect(renderer.actorPresent)
        #expect(companion.claimStoryLine(), "speech can resume after the pixel find sequence returns Pibo")
    }

    @Test func ordinaryFramesStayVisibleWhileSpeechStartsAndStops() throws {
        let renderer = PixelStageRenderer()
        var look = PixelStageRenderer.Look()
        look.hour = 14
        look.animationStateID = "stable"
        let start = Date().timeIntervalSince1970 * 1000
        for tick in 0..<80 {
            look.holdPibo = (tick / 20) % 2 == 1
            let image = renderer.render(size: CGSize(width: 402, height: 874), scale: 3,
                                        now: start + Double(tick) * 50, look: look)
            #expect(image != nil)
            #expect(renderer.actorPresent, "speech presentation must not remove the body at frame \(tick)")
        }
    }
}

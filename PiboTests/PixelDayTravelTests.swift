import Testing
import Foundation
@testable import Pibo
import PiboCore

@Suite struct PixelDayTravelTests {
    private final class DummyBrain: PixelDayBrain {
        func next(previous: PiboDayActivity) -> PixelDayPlan? { nil }
        func slow() -> Bool { false }
    }

    @Test func provisionalShortLayoutCannotStrandPiboBelowTheFinalForest() {
        final class SleepingBrain: PixelDayBrain {
            func next(previous: PiboDayActivity) -> PixelDayPlan? {
                let plan = PixelDayPlan()
                plan.activity = .idle
                plan.place = .mossNest
                return plan
            }
            func slow() -> Bool { true }
        }
        let brain = SleepingBrain()
        let director = PixelDayDirector()
        director.setBrain(brain)
        director.configure(pixelForestLayout(145, 124), .clearing)
        director.settle()
        let finalLayout = pixelForestLayout(134, 291)
        director.configure(finalLayout, .clearing)
        let actor = director.step(1000, hold: false)
        #expect(actor.y <= Double(pixelWalkBounds(finalLayout, .clearing).maxY))
        #expect(actor.y < Double(finalLayout.height))
    }

    @Test func travelWalksPastBoundsToEdgeAndTriggersSceneSwitch() {
        let director = PixelDayDirector()
        let brain = DummyBrain()
        director.setBrain(brain)
        let layout = pixelForestLayout(136, 172)
        director.configure(layout, .clearing)

        var switched = false
        director.events.onSceneSwitch = {
            switched = true
        }

        director.travel()

        // Step over time, periodically calling configure(layout, .clearing) as the render loop does.
        var now: Double = 1000
        for _ in 0..<200 {
            now += 50
            director.configure(layout, .clearing)
            let frame = director.step(now, hold: false)
            if switched {
                break
            }
            #expect(frame.activity == .explore || frame.activity == .idle)
        }

        #expect(switched, "Pibo must walk off-screen to the edge (-26) and fire onSceneSwitch without being clamped at minX")
    }

    @Test func arriveTeleportsToEdgeAndWalksIntoScene() {
        let director = PixelDayDirector()
        let brain = DummyBrain()
        director.setBrain(brain)
        let layout = pixelForestLayout(136, 172)
        director.configure(layout, .creek)

        director.arrive()

        // First step resolves teleport to edge (-26)
        var now: Double = 2000
        let firstFrame = director.step(now, hold: false)
        #expect(firstFrame.x <= 0, "First frame after arrive must be off-screen at the edge")

        // Stepping moves Pibo inwards toward 0.4 * width (approx 80 px at 13 px/s takes ~6.2s)
        for _ in 0..<160 {
            now += 50
            director.configure(layout, .creek)
            _ = director.step(now, hold: false)
        }

        let settledFrame = director.step(now, hold: false)
        let targetX = Double(layout.width) * 0.4
        #expect(abs(settledFrame.x - targetX) < 1.0, "Pibo must walk in from edge to near 0.4 * width")
    }
}

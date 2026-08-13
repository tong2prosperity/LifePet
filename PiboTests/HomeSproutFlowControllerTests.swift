import Foundation
import Testing
@testable import Pibo

@MainActor
struct HomeSproutFlowControllerTests {
    @Test func closeupPreservesPlaybackAndPhaseOrder() throws {
        let controller = HomeSproutFlowController()
        var events: [String] = []
        var onPhase: ((SproutCloseupPhase) -> Void)?

        controller.start(
            request: request(animation: .stageCloseup),
            reduceMotion: false,
            handlers: .init(
                playCloseup: { start, target, callback in
                    events.append("closeup:\(start):\(target)")
                    onPhase = callback
                },
                playGrowth: { _, _ in events.append("growth") },
                markSprouted: { events.append("sprouted") },
                currentPendingWorkoutID: { nil }
            )
        )

        #expect(controller.phase == .collecting)
        #expect(events == ["closeup:0.2:0.4"])

        let callback = try #require(onPhase)
        callback(.shaking)
        #expect(controller.phase == .collecting)
        #expect(events == ["closeup:0.2:0.4"])

        callback(.sprouted)
        #expect(controller.phase == .sprouted)
        #expect(events == ["closeup:0.2:0.4", "sprouted"])

        callback(.finished)
        #expect(controller.phase == .pop)
    }

    @Test func inPlaceGrowthUsesAuthoredDelayAndMatchingWorkoutGate() throws {
        let workoutID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        var pendingWorkoutID: UUID? = workoutID
        var scheduledDelay: TimeInterval?
        var completion: (@MainActor () -> Void)?
        var growth: (Double, Double)?
        let controller = HomeSproutFlowController {
            scheduledDelay = $0
            completion = $1
        }

        controller.start(
            request: request(workoutID: workoutID, animation: .inPlaceGrowth),
            reduceMotion: false,
            handlers: .init(
                playCloseup: { _, _, _ in },
                playGrowth: { growth = ($0, $1) },
                markSprouted: {},
                currentPendingWorkoutID: { pendingWorkoutID }
            )
        )

        #expect(growth?.0 == 0.2)
        #expect(growth?.1 == 0.4)
        #expect(scheduledDelay == 1.35)
        let runCompletion = try #require(completion)
        pendingWorkoutID = UUID()
        runCompletion()
        #expect(controller.phase == .collecting)

        pendingWorkoutID = workoutID
        runCompletion()
        #expect(controller.phase == .pop)

        controller.finishPop()
        #expect(controller.phase == .idle)
    }

    @Test func reducedMotionKeepsTheExistingShortDelay() {
        var scheduledDelay: TimeInterval?
        let controller = HomeSproutFlowController { delay, _ in
            scheduledDelay = delay
        }

        controller.start(
            request: request(animation: .inPlaceGrowth),
            reduceMotion: true,
            handlers: .init(
                playCloseup: { _, _, _ in },
                playGrowth: { _, _ in },
                markSprouted: {},
                currentPendingWorkoutID: { nil }
            )
        )

        #expect(scheduledDelay == 0.15)
    }

    private func request(
        workoutID: UUID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        animation: HomeSproutFlowStartResolver.Animation
    ) -> HomeSproutFlowStartResolver.Request {
        HomeSproutFlowStartResolver.Request(
            workoutID: workoutID,
            growthStart: 0.2,
            growthTarget: 0.4,
            animation: animation
        )
    }
}

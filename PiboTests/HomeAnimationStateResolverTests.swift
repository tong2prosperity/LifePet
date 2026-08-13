import XCTest
@testable import Pibo

@MainActor
final class HomeAnimationStateResolverTests: XCTestCase {
    func testResolverPreservesAnUncoveredAmbientDecision() {
        XCTAssertEqual(
            HomeAnimationStateResolver.resolve(input()).stateID,
            "default"
        )
    }

    func testStressMemoryUsesAmbientDecisionBeforeAchievementHold() {
        let resolution = HomeAnimationStateResolver.resolve(input(
            stressBaselineDays: 7,
            stressZ: -1,
            heldAchievement: .muscle
        ))

        XCTAssertEqual(resolution.stateID, "muscle")
        XCTAssertEqual(resolution.nextStressStateID, "dive")
    }

    func testProtectedAngryStateRemainsAboveAchievementHold() {
        let resolution = HomeAnimationStateResolver.resolve(input(
            angryActive: true,
            heldAchievement: .muscle
        ))

        XCTAssertEqual(resolution.stateID, "angry")
        XCTAssertEqual(resolution.nextStressStateID, "default")
    }

    private func input(
        angryActive: Bool = false,
        stressBaselineDays: Int = 0,
        stressZ: Double = 0,
        heldAchievement: PiboAnimationAchievementKind? = nil
    ) -> HomeAnimationStateResolver.Input {
        HomeAnimationStateResolver.Input(
            localHour: 15,
            hasSleepData: true,
            sleepHours: 7,
            sleepReferenceHours: 7,
            hasActivityData: true,
            steps: 4_000,
            hasWorkoutToday: false,
            postPluckSleep: false,
            sleepDayKey: 20_260_814,
            angryActive: angryActive,
            hasEligibleRMSSD: stressBaselineDays > 0,
            stressBaselineDays: stressBaselineDays,
            stressZ: stressZ,
            rmssdAgeSeconds: 0,
            previousStressStateID: "default",
            heldAchievement: heldAchievement
        )
    }
}

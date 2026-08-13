import Foundation
import PiboCore
import XCTest
@testable import Pibo

@MainActor
final class HomePresentationPolicyPendingTests: XCTestCase {
    func testAchievementReturnsThePendingPayloadOnlyWhenHomeIsEligible() {
        let payload = achievement()

        XCTAssertEqual(
            policy().pendingAchievement(
                animationStateID: "default",
                pendingAchievement: payload
            ),
            payload
        )
        XCTAssertNil(policy().pendingAchievement(
            animationStateID: "sleep-1",
            pendingAchievement: payload
        ))
    }

    func testAchievementPreservesGuardReadOrderAndPendingLaziness() {
        let probe = ReadProbe()
        let policy = HomePresentationPolicy(
            sceneIsActive: probe.read(false, named: "scene"),
            cameraPresented: probe.read(false, named: "camera"),
            gamesPresented: probe.read(false, named: "games"),
            historyPresented: probe.read(false, named: "history"),
            walkDoodlePresented: probe.read(false, named: "doodle"),
            settingsPresented: probe.read(false, named: "settings"),
            storyRecoveryPresented: probe.read(false, named: "recovery"),
            sheetPresented: probe.read(false, named: "sheet"),
            sheetDismissalInProgress: false,
            sproutFlowIsIdle: true
        )

        let payload = policy.pendingAchievement(
            animationStateID: probe.read("default", named: "state"),
            pendingAchievement: probe.read(achievement(), named: "pending")
        )

        XCTAssertNil(payload)
        XCTAssertEqual(probe.names, ["scene"])
    }

    func testMorningSleepReturnsTheConsumablePresentationLast() {
        let probe = ReadProbe()
        let policy = tracedPolicy(probe)

        let presentation: String? = policy.morningSleepPresentation(
            sleepReviewGranted: probe.read(true, named: "grant"),
            consumablePresentation: probe.read("presentation", named: "consume")
        )

        XCTAssertEqual(presentation, "presentation")
        XCTAssertEqual(
            probe.names,
            [
                "scene", "grant", "sheet", "camera", "games", "history",
                "doodle", "settings", "recovery", "sprout", "consume",
            ]
        )
    }

    func testBlockedMorningSleepNeverConsumesThePendingPresentation() {
        let probe = ReadProbe()
        let policy = tracedPolicy(probe)

        let presentation: String? = policy.morningSleepPresentation(
            sleepReviewGranted: probe.read(false, named: "grant"),
            consumablePresentation: probe.read("presentation", named: "consume")
        )

        XCTAssertNil(presentation)
        XCTAssertEqual(probe.names, ["scene", "grant"])
    }

    func testStressCardRequiresPendingRequestAndAnUnoccupiedHome() {
        XCTAssertTrue(policy().shouldPresentStressCard(pendingCardOpen: true))
        XCTAssertFalse(policy().shouldPresentStressCard(pendingCardOpen: false))
        XCTAssertFalse(policy(coverPresented: true).shouldPresentStressCard(
            pendingCardOpen: true
        ))
        XCTAssertFalse(policy(sheetPresented: true).shouldPresentStressCard(
            pendingCardOpen: true
        ))
    }

    func testStressCardPreservesShortCircuitReadOrder() {
        let probe = ReadProbe()
        let policy = tracedPolicy(probe)

        XCTAssertFalse(policy.shouldPresentStressCard(
            pendingCardOpen: probe.read(false, named: "pending")
        ))
        XCTAssertEqual(probe.names, ["pending"])
    }

    private func policy(
        coverPresented: Bool = false,
        sheetPresented: Bool = false
    ) -> HomePresentationPolicy {
        HomePresentationPolicy(
            sceneIsActive: true,
            cameraPresented: coverPresented,
            gamesPresented: false,
            historyPresented: false,
            walkDoodlePresented: false,
            settingsPresented: false,
            storyRecoveryPresented: false,
            sheetPresented: sheetPresented,
            sheetDismissalInProgress: false,
            sproutFlowIsIdle: true
        )
    }

    private func tracedPolicy(_ probe: ReadProbe) -> HomePresentationPolicy {
        HomePresentationPolicy(
            sceneIsActive: probe.read(true, named: "scene"),
            cameraPresented: probe.read(false, named: "camera"),
            gamesPresented: probe.read(false, named: "games"),
            historyPresented: probe.read(false, named: "history"),
            walkDoodlePresented: probe.read(false, named: "doodle"),
            settingsPresented: probe.read(false, named: "settings"),
            storyRecoveryPresented: probe.read(false, named: "recovery"),
            sheetPresented: probe.read(false, named: "sheet"),
            sheetDismissalInProgress: false,
            sproutFlowIsIdle: probe.read(true, named: "sprout")
        )
    }

    private func achievement() -> PiboAnimationAchievementPayload {
        PiboAnimationAchievementPayload(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            kind: .muscle,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            workoutLabel: nil,
            workoutDurationMinutes: nil
        )
    }
}

@MainActor
private final class ReadProbe {
    private(set) var names: [String] = []

    func read<Value>(_ value: Value, named name: String) -> Value {
        names.append(name)
        return value
    }
}

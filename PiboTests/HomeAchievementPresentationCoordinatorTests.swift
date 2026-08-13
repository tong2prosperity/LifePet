import Foundation
import Testing
@testable import Pibo

@Suite
@MainActor
struct HomeAchievementPresentationCoordinatorTests {
    @Test func eligibleAchievementBecomesThePresentedSheet() {
        let payload = achievement(id: uuid(1))
        var destination: HomeSheetDestination?

        HomeAchievementPresentationCoordinator.presentIfPossible(
            policy: policy(),
            animationStateID: "default",
            pendingAchievement: payload,
            destination: &destination
        )

        #expect(destination == .achievement(payload))
    }

    @Test func blockedPresentationLeavesDestinationAndPendingValueUnread() {
        let probe = ReadProbe()
        let existing = achievement(id: uuid(1))
        var destination: HomeSheetDestination? = .achievement(existing)

        HomeAchievementPresentationCoordinator.presentIfPossible(
            policy: policy(sceneIsActive: false),
            animationStateID: probe.read("default"),
            pendingAchievement: probe.read(achievement(id: uuid(2))),
            destination: &destination
        )

        #expect(destination == .achievement(existing))
        #expect(probe.count == 0)
    }

    @Test func reconciliationReplacesThePresentedAchievement() {
        let presented = achievement(id: uuid(1))
        let pending = achievement(id: uuid(2))
        var destination: HomeSheetDestination? = .achievement(presented)

        HomeAchievementPresentationCoordinator.reconcile(
            destination: &destination,
            pendingAchievement: pending
        )

        #expect(destination == .achievement(pending))
    }

    @Test func nonAchievementDestinationLeavesPendingValueUnread() {
        let probe = ReadProbe()
        var destination: HomeSheetDestination?

        HomeAchievementPresentationCoordinator.reconcile(
            destination: &destination,
            pendingAchievement: probe.read(achievement(id: uuid(1)))
        )

        #expect(destination == nil)
        #expect(probe.count == 0)
    }

    private func policy(sceneIsActive: Bool = true) -> HomePresentationPolicy {
        HomePresentationPolicy(
            sceneIsActive: sceneIsActive,
            cameraPresented: false,
            gamesPresented: false,
            historyPresented: false,
            walkDoodlePresented: false,
            settingsPresented: false,
            storyRecoveryPresented: false,
            sheetPresented: false,
            sheetDismissalInProgress: false,
            sproutFlowIsIdle: true
        )
    }

    private func achievement(id: UUID) -> PiboAnimationAchievementPayload {
        PiboAnimationAchievementPayload(
            id: id,
            kind: .muscle,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            workoutLabel: nil,
            workoutDurationMinutes: nil
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

private final class ReadProbe {
    private(set) var count = 0

    func read<Value>(_ value: Value) -> Value {
        count += 1
        return value
    }
}

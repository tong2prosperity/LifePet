import Foundation
import XCTest
@testable import Pibo

@MainActor
final class HomeAchievementPresentationPolicyTests: XCTestCase {
    func testObservedChangesDistinguishPendingReplacementFromPresentationRequest() {
        let previousPendingID = uuid(1)
        let pendingID = uuid(2)
        let previousRequestID = uuid(3)
        let requestID = uuid(4)

        XCTAssertEqual(
            HomeAchievementPresentationPolicy.observedChanges(
                previousPendingAchievementID: previousPendingID,
                pendingAchievementID: pendingID,
                previousNotificationPresentationRequestID: previousRequestID,
                notificationPresentationRequestID: previousRequestID
            ),
            .init(
                pendingAchievementChanged: true,
                notificationPresentationRequested: false
            )
        )
        XCTAssertEqual(
            HomeAchievementPresentationPolicy.observedChanges(
                previousPendingAchievementID: pendingID,
                pendingAchievementID: pendingID,
                previousNotificationPresentationRequestID: previousRequestID,
                notificationPresentationRequestID: requestID
            ),
            .init(
                pendingAchievementChanged: false,
                notificationPresentationRequested: true
            )
        )
    }

    func testPresentationAttemptFollowsEitherObservedChange() {
        let unchanged = changes(pendingChanged: false, requestChanged: false)
        let pendingChanged = changes(pendingChanged: true, requestChanged: false)
        let requestChanged = changes(pendingChanged: false, requestChanged: true)

        XCTAssertFalse(unchanged.shouldAttemptPresentation)
        XCTAssertTrue(pendingChanged.shouldAttemptPresentation)
        XCTAssertTrue(requestChanged.shouldAttemptPresentation)
    }

    func testReconciliationDismissesWhenPendingAchievementDisappears() {
        XCTAssertEqual(
            HomeAchievementPresentationPolicy.reconciliation(
                presentedAchievement: achievement(id: uuid(1)),
                pendingAchievement: nil
            ),
            .dismiss
        )
    }

    func testReconciliationReplacesOnlyAChangedAchievementID() {
        let presented = achievement(id: uuid(1))
        let same = achievement(id: presented.id, kind: .pigu)
        let replacement = achievement(id: uuid(2), kind: .pigu)

        XCTAssertEqual(
            HomeAchievementPresentationPolicy.reconciliation(
                presentedAchievement: presented,
                pendingAchievement: same
            ),
            .unchanged
        )
        XCTAssertEqual(
            HomeAchievementPresentationPolicy.reconciliation(
                presentedAchievement: presented,
                pendingAchievement: replacement
            ),
            .replace(replacement)
        )
    }

    func testReconciliationAppliesOnlyItsSpecifiedDestinationMutation() {
        let presented = achievement(id: uuid(1))
        let replacement = achievement(id: uuid(2), kind: .pigu)
        var destination: HomeSheetDestination? = .achievement(presented)

        HomeAchievementPresentationPolicy.Reconciliation.unchanged.apply(
            to: &destination
        )
        XCTAssertEqual(destination, .achievement(presented))

        HomeAchievementPresentationPolicy.Reconciliation.replace(replacement).apply(
            to: &destination
        )
        XCTAssertEqual(destination, .achievement(replacement))

        HomeAchievementPresentationPolicy.Reconciliation.dismiss.apply(
            to: &destination
        )
        XCTAssertNil(destination)
    }

    func testOnlyAnEnabledStaleFixtureShouldDismiss() {
        XCTAssertTrue(
            HomeAchievementPresentationPolicy.shouldDismissStaleFixture(
                presentedAchievementID: uuid(1),
                pendingAchievementID: uuid(2),
                fixtureEnabled: true
            )
        )
        XCTAssertFalse(
            HomeAchievementPresentationPolicy.shouldDismissStaleFixture(
                presentedAchievementID: uuid(1),
                pendingAchievementID: uuid(1),
                fixtureEnabled: true
            )
        )
        XCTAssertFalse(
            HomeAchievementPresentationPolicy.shouldDismissStaleFixture(
                presentedAchievementID: uuid(1),
                pendingAchievementID: uuid(2),
                fixtureEnabled: false
            )
        )
    }

    func testConfirmationRequiresThePresentedAchievementToRemainPending() {
        XCTAssertTrue(
            HomeAchievementPresentationPolicy.shouldConfirm(
                presentedAchievementID: uuid(1),
                pendingAchievementID: uuid(1)
            )
        )
        XCTAssertFalse(
            HomeAchievementPresentationPolicy.shouldConfirm(
                presentedAchievementID: uuid(1),
                pendingAchievementID: uuid(2)
            )
        )
        XCTAssertFalse(
            HomeAchievementPresentationPolicy.shouldConfirm(
                presentedAchievementID: uuid(1),
                pendingAchievementID: nil
            )
        )
    }

    func testOnlyTheMatchingPiguAchievementConsumesPendingWorkout() {
        let pigu = achievement(id: uuid(1), kind: .pigu)
        let muscle = achievement(id: uuid(2), kind: .muscle)

        XCTAssertTrue(
            HomeAchievementPresentationPolicy.consumesPendingWorkout(
                presentedAchievement: pigu,
                pendingWorkoutID: pigu.id
            )
        )
        XCTAssertFalse(
            HomeAchievementPresentationPolicy.consumesPendingWorkout(
                presentedAchievement: pigu,
                pendingWorkoutID: uuid(3)
            )
        )
        XCTAssertFalse(
            HomeAchievementPresentationPolicy.consumesPendingWorkout(
                presentedAchievement: muscle,
                pendingWorkoutID: muscle.id
            )
        )
    }

    func testWorkoutConsumptionReadsPendingWorkoutOnlyForPigu() {
        let probe = ReadProbe()
        let muscle = achievement(id: uuid(2), kind: .muscle)

        _ = HomeAchievementPresentationPolicy.consumesPendingWorkout(
            presentedAchievement: muscle,
            pendingWorkoutID: probe.read(muscle.id)
        )
        XCTAssertEqual(probe.count, 0)

        let pigu = achievement(id: uuid(4), kind: .pigu)
        _ = HomeAchievementPresentationPolicy.consumesPendingWorkout(
            presentedAchievement: pigu,
            pendingWorkoutID: probe.read(pigu.id)
        )
        XCTAssertEqual(probe.count, 1)
    }

    private func changes(
        pendingChanged: Bool,
        requestChanged: Bool
    ) -> HomeAchievementPresentationPolicy.ObservedChanges {
        HomeAchievementPresentationPolicy.observedChanges(
            previousPendingAchievementID: uuid(1),
            pendingAchievementID: uuid(pendingChanged ? 2 : 1),
            previousNotificationPresentationRequestID: uuid(3),
            notificationPresentationRequestID: uuid(requestChanged ? 4 : 3)
        )
    }

    private func achievement(
        id: UUID,
        kind: PiboAnimationAchievementKind = .muscle
    ) -> PiboAnimationAchievementPayload {
        PiboAnimationAchievementPayload(
            id: id,
            kind: kind,
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

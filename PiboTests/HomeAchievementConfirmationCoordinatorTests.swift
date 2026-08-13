import Foundation
import XCTest
@testable import Pibo

@MainActor
final class HomeAchievementConfirmationCoordinatorTests: XCTestCase {
    func testStaleFixtureOnlyDismissesTheFixture() {
        let presented = achievement(id: uuid(1), kind: .pigu)
        let events = EventLog()

        HomeAchievementConfirmationCoordinator.confirm(
            presentedAchievement: presented,
            staleFixtureEnabled: true,
            handlers: handlers(
                pendingAchievementID: uuid(2),
                pendingWorkoutID: presented.id,
                events: events
            )
        )

        XCTAssertEqual(events.values, ["pending-achievement", "dismiss-stale"])
    }

    func testMismatchedPendingAchievementPerformsNoMutation() {
        let events = EventLog()

        HomeAchievementConfirmationCoordinator.confirm(
            presentedAchievement: achievement(id: uuid(1)),
            staleFixtureEnabled: false,
            handlers: handlers(
                pendingAchievementID: uuid(2),
                pendingWorkoutID: nil,
                events: events
            )
        )

        XCTAssertEqual(
            events.values,
            ["pending-achievement", "pending-achievement"]
        )
    }

    func testMuscleConfirmationSkipsWorkoutReadAndPreservesEffectOrder() {
        let presented = achievement(id: uuid(1), kind: .muscle)
        let events = EventLog()

        HomeAchievementConfirmationCoordinator.confirm(
            presentedAchievement: presented,
            staleFixtureEnabled: false,
            handlers: handlers(
                pendingAchievementID: presented.id,
                pendingWorkoutID: presented.id,
                events: events
            )
        )

        XCTAssertEqual(events.values, [
            "pending-achievement",
            "pending-achievement",
            "confirm",
            "debug-reward",
            "refresh",
            "begin-dismissal",
        ])
    }

    func testMatchingPiguConsumesWorkoutBeforeRemainingEffects() {
        let presented = achievement(id: uuid(1), kind: .pigu)
        let events = EventLog()

        HomeAchievementConfirmationCoordinator.confirm(
            presentedAchievement: presented,
            staleFixtureEnabled: false,
            handlers: handlers(
                pendingAchievementID: presented.id,
                pendingWorkoutID: presented.id,
                events: events
            )
        )

        XCTAssertEqual(events.values, [
            "pending-achievement",
            "pending-achievement",
            "confirm",
            "pending-workout",
            "consume-workout",
            "debug-reward",
            "refresh",
            "begin-dismissal",
        ])
    }

    func testMismatchedPiguWorkoutIsReadButNotConsumed() {
        let presented = achievement(id: uuid(1), kind: .pigu)
        let events = EventLog()

        HomeAchievementConfirmationCoordinator.confirm(
            presentedAchievement: presented,
            staleFixtureEnabled: false,
            handlers: handlers(
                pendingAchievementID: presented.id,
                pendingWorkoutID: uuid(2),
                events: events
            )
        )

        XCTAssertEqual(events.values, [
            "pending-achievement",
            "pending-achievement",
            "confirm",
            "pending-workout",
            "debug-reward",
            "refresh",
            "begin-dismissal",
        ])
    }

    private func handlers(
        pendingAchievementID: UUID?,
        pendingWorkoutID: UUID?,
        events: EventLog
    ) -> HomeAchievementConfirmationCoordinator.Handlers {
        HomeAchievementConfirmationCoordinator.Handlers(
            currentPendingAchievementID: {
                events.append("pending-achievement")
                return pendingAchievementID
            },
            dismissStaleFixture: { events.append("dismiss-stale") },
            confirmPending: { events.append("confirm") },
            currentPendingWorkoutID: {
                events.append("pending-workout")
                return pendingWorkoutID
            },
            consumePendingWorkout: { events.append("consume-workout") },
            applyDebugReward: { events.append("debug-reward") },
            refreshAnimationState: { events.append("refresh") },
            beginSheetDismissal: { events.append("begin-dismissal") }
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
            workoutDurationMinutes: kind == .pigu ? 24 : nil
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

private final class EventLog {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

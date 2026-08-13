import Foundation
import Testing
@testable import Pibo

@MainActor
struct HomeStateObservationCoordinatorTests {
    @Test func animationChangePreservesRefreshReconcilePresentOrder() {
        let events = EventLog()
        let previous = token(pendingID: uuid(1), requestID: uuid(2))
        let current = token(pendingID: uuid(3), requestID: uuid(4))

        HomeStateObservationCoordinator.animationTokenChanged(
            from: previous,
            to: current,
            handlers: events.handlers
        )

        #expect(events.values == ["refresh", "reconcile", "achievement"])
    }

    @Test func unchangedAnimationTokenOnlyRefreshesAnimation() {
        let events = EventLog()
        let value = token(pendingID: uuid(1), requestID: uuid(2))

        HomeStateObservationCoordinator.animationTokenChanged(
            from: value,
            to: value,
            handlers: events.handlers
        )

        #expect(events.values == ["refresh"])
    }

    @Test func activeScenePreservesForegroundEffectOrder() {
        let events = EventLog()

        HomeStateObservationCoordinator.scenePhaseChanged(
            isActive: true,
            handlers: events.handlers
        )

        #expect(events.values == [
            "refresh", "lights", "achievement", "morning-sleep",
        ])
    }

    @Test func inactiveScenePerformsNoEffects() {
        let events = EventLog()

        HomeStateObservationCoordinator.scenePhaseChanged(
            isActive: false,
            handlers: events.handlers
        )

        #expect(events.values.isEmpty)
    }

    @Test func booleanAndPhaseReactionsKeepTheirExistingGates() {
        let events = EventLog()

        HomeStateObservationCoordinator.ripeBoChanged(
            false,
            handlers: events.handlers
        )
        HomeStateObservationCoordinator.animationStateChanged(
            handlers: events.handlers(hasRipeBo: false)
        )
        HomeStateObservationCoordinator.sproutPhaseChanged(
            .pop,
            handlers: events.handlers
        )
        #expect(events.values.isEmpty)

        HomeStateObservationCoordinator.ripeBoChanged(
            true,
            handlers: events.handlers
        )
        HomeStateObservationCoordinator.animationStateChanged(
            handlers: events.handlers(hasRipeBo: true)
        )
        HomeStateObservationCoordinator.sproutPhaseChanged(
            .idle,
            handlers: events.handlers
        )
        #expect(events.values == ["announce", "announce", "resume"])
    }

    private func token(
        pendingID: UUID?,
        requestID: UUID?
    ) -> HomeAnimationRefreshToken {
        HomeAnimationRefreshToken(
            steps: 0,
            sleepHours: 0,
            hasWorkout: false,
            rmssd: nil,
            historyRevision: 0,
            pendingAchievementID: pendingID,
            notificationPresentationRequestID: requestID
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(
            format: "00000000-0000-0000-0000-%012d",
            value
        ))!
    }
}

@MainActor
private final class EventLog {
    private(set) var values: [String] = []

    var handlers: HomeStateObservationCoordinator.Handlers {
        handlers(hasRipeBo: false)
    }

    func handlers(
        hasRipeBo: Bool
    ) -> HomeStateObservationCoordinator.Handlers {
        .init(
            refreshAnimation: { self.values.append("refresh") },
            reconcileAchievement: { self.values.append("reconcile") },
            presentAchievement: { self.values.append("achievement") },
            refreshOrnamentLights: { self.values.append("lights") },
            presentMorningSleep: { self.values.append("morning-sleep") },
            presentStressCard: { self.values.append("stress") },
            currentHasRipeBo: { hasRipeBo },
            announceFirstRipeBo: { self.values.append("announce") },
            resumePendingFlows: { self.values.append("resume") }
        )
    }
}

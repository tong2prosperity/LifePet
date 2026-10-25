import Testing
import Foundation
@testable import Pibo

@Suite
@MainActor
struct HomeStressCardPresentationCoordinatorTests {
    @Test func missingRequestShortCircuitsEveryMutation() {
        let events = EventLog()

        HomeStressCardPresentationCoordinator.presentIfPossible(
            policy: policy(),
            pendingCardOpen: events.read(false, named: "pending"),
            handlers: handlers(events)
        )

        #expect(events.values == ["pending"])
    }

    @Test func occupiedHomeRetainsThePendingRequest() {
        let events = EventLog()

        HomeStressCardPresentationCoordinator.presentIfPossible(
            policy: policy(coverPresented: true),
            pendingCardOpen: events.read(true, named: "pending"),
            handlers: handlers(events)
        )

        #expect(events.values == ["pending"])
    }

    @Test func eligibleRequestClearsThenFocusesThenPresents() {
        let events = EventLog()

        HomeStressCardPresentationCoordinator.presentIfPossible(
            policy: policy(),
            pendingCardOpen: events.read(true, named: "pending"),
            handlers: handlers(events)
        )

        #expect(events.values == ["pending", "clear", "focus", "present"])
    }

    @Test(arguments: [0, 1, 2, 3])
    func blockedRouteWaitsWithoutConsumingItsRequest(boundary: Int) {
        let events = EventLog()
        let presentation = HomePresentationState()
        presentation.sheetDismissalInProgress = boundary == 1
        let guarded = HomePresentationPolicy(
            sceneIsActive: boundary != 0, presentation: presentation,
            sproutFlowIsIdle: boundary != 3, foregroundOverlayPresented: boundary == 2)
        HomeStressCardPresentationCoordinator.presentIfPossible(
            policy: guarded, pendingCardOpen: true, handlers: handlers(events))
        #expect(events.values.isEmpty)
    }

    @Test func pixelWindowDefersBothSleepAndNotificationUntilItCloses() {
        let presentation = HomePresentationState()
        final class Window { var open = true }
        let window = Window()
        let guarded = HomePresentationPolicy(
            sceneIsActive: true, presentation: presentation, sproutFlowIsIdle: true,
            foregroundOverlayPresented: window.open)
        let review = "pending-review"
        #expect(guarded.morningSleepPresentation(sleepReviewGranted: true,
                                                 consumablePresentation: review) == nil)
        #expect(!guarded.shouldPresentStressCard(pendingCardOpen: true))
        window.open = false
        #expect(guarded.morningSleepPresentation(sleepReviewGranted: true,
                                                 consumablePresentation: review) == review)
        #expect(guarded.shouldPresentStressCard(pendingCardOpen: true))
    }

    private func policy(coverPresented: Bool = false) -> HomePresentationPolicy {
        HomePresentationPolicy(
            sceneIsActive: true,
            cameraPresented: coverPresented,
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

    private func handlers(
        _ events: EventLog
    ) -> HomeStressCardPresentationCoordinator.Handlers {
        HomeStressCardPresentationCoordinator.Handlers(
            clearPendingRequest: { events.append("clear") },
            focusStressCard: { events.append("focus") },
            presentHistory: { events.append("present") }
        )
    }
}

private final class EventLog {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func read<Value>(_ value: Value, named name: String) -> Value {
        append(name)
        return value
    }
}

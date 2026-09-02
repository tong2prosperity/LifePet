import XCTest
@testable import Pibo

@MainActor
final class HomeOrnamentInteractionCoordinatorTests: XCTestCase {
    func testBlockedTapReadsNoFeatureDataAndPerformsNoEffects() {
        let events = EventLog()
        var featureDataRead = false

        HomeOrnamentInteractionCoordinator.handleTap(
            ornamentID: .statusObserver,
            canPresent: { false },
            sleepReviewGranted: { featureDataRead = true; return true },
            latestSleepReview: { featureDataRead = true; return nil },
            recoveryStatusGranted: { featureDataRead = true; return true },
            handlers: tapHandlers(events: events)
        )

        XCTAssertFalse(featureDataRead)
        XCTAssertEqual(events.values, [])
    }

    func testDecorativeTapPreservesFeedbackAndDismissalBeforeNoAction() {
        let events = EventLog()
        var featureDataRead = false

        HomeOrnamentInteractionCoordinator.handleTap(
            ornamentID: .chime,
            canPresent: { true },
            sleepReviewGranted: { featureDataRead = true; return true },
            latestSleepReview: { featureDataRead = true; return nil },
            recoveryStatusGranted: { featureDataRead = true; return true },
            handlers: tapHandlers(events: events)
        )

        XCTAssertFalse(featureDataRead)
        XCTAssertEqual(events.values, ["feedback", "dismiss"])
    }

    func testStatusTapTogglesAfterFeedbackAndDismissal() {
        let events = EventLog()

        HomeOrnamentInteractionCoordinator.handleTap(
            ornamentID: .statusObserver,
            canPresent: { true },
            sleepReviewGranted: { false },
            latestSleepReview: { nil },
            recoveryStatusGranted: { true },
            handlers: tapHandlers(events: events)
        )

        XCTAssertEqual(events.values, ["feedback", "dismiss", "toggle"])
    }

    func testInvalidLightTapPreservesLazyGuards() {
        var entitlementReads = 0
        let events = EventLog()
        let handlers = lightHandlers(events: events, succeeds: true)

        HomeOrnamentInteractionCoordinator.handleLightTap(
            ornamentID: .chime,
            index: 0,
            lightingGranted: { entitlementReads += 1; return true },
            handlers: handlers
        )
        XCTAssertEqual(entitlementReads, 0)
        XCTAssertEqual(events.values, [])

        HomeOrnamentInteractionCoordinator.handleLightTap(
            ornamentID: .lantern,
            index: -1,
            lightingGranted: { entitlementReads += 1; return true },
            handlers: handlers
        )
        XCTAssertEqual(entitlementReads, 1)
        XCTAssertEqual(events.values, [])
    }

    func testLightTapOnlyFeedsBackAndTracksAfterSuccessfulMutation() {
        let failedEvents = EventLog()
        HomeOrnamentInteractionCoordinator.handleLightTap(
            ornamentID: .lantern,
            index: 0,
            lightingGranted: { true },
            handlers: lightHandlers(events: failedEvents, succeeds: false)
        )
        XCTAssertEqual(failedEvents.values, ["light:lantern:0"])

        let events = EventLog()
        HomeOrnamentInteractionCoordinator.handleLightTap(
            ornamentID: .lantern,
            index: 1,
            lightingGranted: { true },
            handlers: lightHandlers(events: events, succeeds: true)
        )
        XCTAssertEqual(
            events.values,
            ["light:lantern:1", "feedback", "track:lantern:1"]
        )
    }

    private func tapHandlers(
        events: EventLog
    ) -> HomeOrnamentInteractionCoordinator.TapHandlers {
        HomeOrnamentInteractionCoordinator.TapHandlers(
            feedback: { events.append("feedback") },
            dismissSpeech: { events.append("dismiss") },
            presentMorningSleep: { _ in events.append("sleep") },
            presentStatus: { events.append("status:\($0.status)") },
            toggleStatusObserver: { events.append("toggle") }
        )
    }

    private func lightHandlers(
        events: EventLog,
        succeeds: Bool
    ) -> HomeOrnamentInteractionCoordinator.LightTapHandlers {
        HomeOrnamentInteractionCoordinator.LightTapHandlers(
            light: {
                events.append("light:\($0.rawValue):\($1)")
                return succeeds
            },
            feedback: { events.append("feedback") },
            track: { events.append("track:\($0.rawValue):\($1)") }
        )
    }
}

private final class EventLog {
    var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

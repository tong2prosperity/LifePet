import XCTest
@testable import Pibo

@MainActor
final class HomeStoryRecoveryPolicyTests: XCTestCase {
    func testBannerRequiresFeatureRecoveryAndAnUndismissedState() {
        XCTAssertTrue(shouldShow())
        XCTAssertFalse(shouldShow(featureEnabled: false))
        XCTAssertFalse(shouldShow(needsRecovery: false))
        XCTAssertFalse(shouldShow(dismissed: true))
    }

    func testScheduleControlsAnOtherwiseEligibleBanner() {
        XCTAssertTrue(shouldShow(scheduleAllowsPresentation: true))
        XCTAssertFalse(shouldShow(scheduleAllowsPresentation: false))
    }

    func testIneligibleBannerDoesNotEvaluateItsSchedule() {
        let probe = ReadProbe()

        XCTAssertFalse(
            HomeStoryRecoveryPolicy.shouldShow(
                featureEnabled: false,
                needsRecovery: true,
                dismissed: false,
                scheduleAllowsPresentation: probe.read
            )
        )
        XCTAssertEqual(probe.count, 0)
    }

    private func shouldShow(
        featureEnabled: Bool = true,
        needsRecovery: Bool = true,
        dismissed: Bool = false,
        scheduleAllowsPresentation: Bool = true
    ) -> Bool {
        HomeStoryRecoveryPolicy.shouldShow(
            featureEnabled: featureEnabled,
            needsRecovery: needsRecovery,
            dismissed: dismissed,
            scheduleAllowsPresentation: { scheduleAllowsPresentation }
        )
    }
}

private final class ReadProbe {
    private(set) var count = 0

    func read() -> Bool {
        count += 1
        return true
    }
}

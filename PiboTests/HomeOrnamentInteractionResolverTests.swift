import XCTest
@testable import Pibo

final class HomeOrnamentInteractionResolverTests: XCTestCase {
    func testHammockChecksEntitlementBeforeReadingSleepReview() {
        var sleepGrantRead = false
        var sleepReviewRead = false
        var recoveryGrantRead = false

        let action = HomeOrnamentInteractionResolver.resolve(
            ornamentID: .hammock,
            sleepReviewGranted: read(&sleepGrantRead, value: false),
            latestSleepReview: read(&sleepReviewRead, value: nil),
            recoveryStatusGranted: read(&recoveryGrantRead, value: true)
        )

        XCTAssertEqual(action, .none)
        XCTAssertTrue(sleepGrantRead)
        XCTAssertFalse(sleepReviewRead)
        XCTAssertFalse(recoveryGrantRead)
    }

    func testHammockPresentsExistingSleepReviewUnchanged() {
        let presentation = sleepPresentation()

        let action = HomeOrnamentInteractionResolver.resolve(
            ornamentID: .hammock,
            sleepReviewGranted: true,
            latestSleepReview: presentation,
            recoveryStatusGranted: false
        )

        XCTAssertEqual(action, .presentMorningSleep(presentation))
    }

    func testHammockWithoutSleepDataPreservesWaitingStatusCopy() {
        let action = HomeOrnamentInteractionResolver.resolve(
            ornamentID: .hammock,
            sleepReviewGranted: true,
            latestSleepReview: nil,
            recoveryStatusGranted: false
        )

        XCTAssertEqual(action, .presentStatus(CommonItemStatusModel(
            ornamentID: .hammock,
            title: "睡眠回顾",
            status: "等待数据",
            message: "收到可用的睡眠记录后，可以从吊床重复查看最近一次睡眠回顾。"
        )))
    }

    func testStatusObserverTogglesOnlyAfterEntitlementPasses() {
        var sleepGrantRead = false
        var sleepReviewRead = false
        var recoveryGrantRead = false

        let granted = HomeOrnamentInteractionResolver.resolve(
            ornamentID: .statusObserver,
            sleepReviewGranted: read(&sleepGrantRead, value: true),
            latestSleepReview: read(&sleepReviewRead, value: sleepPresentation()),
            recoveryStatusGranted: read(&recoveryGrantRead, value: true)
        )

        XCTAssertEqual(granted, .toggleStatusObserver)
        XCTAssertFalse(sleepGrantRead)
        XCTAssertFalse(sleepReviewRead)
        XCTAssertTrue(recoveryGrantRead)

        recoveryGrantRead = false
        let denied = HomeOrnamentInteractionResolver.resolve(
            ornamentID: .statusObserver,
            sleepReviewGranted: read(&sleepGrantRead, value: true),
            latestSleepReview: read(&sleepReviewRead, value: sleepPresentation()),
            recoveryStatusGranted: read(&recoveryGrantRead, value: false)
        )
        XCTAssertEqual(denied, .none)
        XCTAssertTrue(recoveryGrantRead)
    }

    func testDecorativeOrnamentsReadNoFeatureData() {
        for ornamentID in [PiboOrnament.ID.chime, .lantern] {
            var sleepGrantRead = false
            var sleepReviewRead = false
            var recoveryGrantRead = false

            let action = HomeOrnamentInteractionResolver.resolve(
                ornamentID: ornamentID,
                sleepReviewGranted: read(&sleepGrantRead, value: true),
                latestSleepReview: read(&sleepReviewRead, value: sleepPresentation()),
                recoveryStatusGranted: read(&recoveryGrantRead, value: true)
            )

            XCTAssertEqual(action, .none)
            XCTAssertFalse(sleepGrantRead)
            XCTAssertFalse(sleepReviewRead)
            XCTAssertFalse(recoveryGrantRead)
        }
    }

    private func sleepPresentation() -> MorningSleepPresentation {
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        let total: TimeInterval = 7 * 3_600
        return MorningSleepPresentation(
            summary: MorningSleepSummary(
                wakeDay: Calendar.current.startOfDay(for: end),
                generatedAt: end,
                start: end.addingTimeInterval(-total),
                end: end,
                total: total,
                core: total,
                deep: 0,
                rem: 0,
                awake: 0,
                segments: [],
                hasDetailedStages: true,
                hasInBedSignal: true,
                hasTerminalAwakeSignal: true,
                awakeningCount: nil,
                continuity: nil,
                baselineDelta: nil,
                overnightHRV: nil,
                sleepingWristTemperature: nil,
                sleepingWristTemperatureDelta: nil,
                respiratoryRate: nil,
                oxygenSaturation: nil,
                sleepHeartRateAverage: nil,
                sleepHeartRateMin: nil,
                sleepLatency: nil
            ),
            isSettled: true,
            isCatchUp: false
        )
    }

    private func read<T>(_ didRead: inout Bool, value: T) -> T {
        didRead = true
        return value
    }
}

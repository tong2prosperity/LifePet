import XCTest
@testable import Pibo

final class HomeOrnamentInteractionResolverTests: XCTestCase {
    func testHammockChecksEntitlementBeforeReadingSleepReview() {
        var sleepGrantRead = false
        var sleepReviewRead = false
        var recoveryGrantRead = false
        var recoveryCalibrationRead = false

        let action = HomeOrnamentInteractionResolver.resolve(
            ornamentID: .hammock,
            sleepReviewGranted: read(&sleepGrantRead, value: false),
            latestSleepReview: read(&sleepReviewRead, value: nil),
            recoveryStatusGranted: read(&recoveryGrantRead, value: true),
            recoveryCalibration: read(&recoveryCalibrationRead, value: .calibrating)
        )

        XCTAssertEqual(action, .none)
        XCTAssertTrue(sleepGrantRead)
        XCTAssertFalse(sleepReviewRead)
        XCTAssertFalse(recoveryGrantRead)
        XCTAssertFalse(recoveryCalibrationRead)
    }

    func testHammockPresentsExistingSleepReviewUnchanged() {
        let presentation = sleepPresentation()

        let action = HomeOrnamentInteractionResolver.resolve(
            ornamentID: .hammock,
            sleepReviewGranted: true,
            latestSleepReview: presentation,
            recoveryStatusGranted: false,
            recoveryCalibration: .waitingForData
        )

        XCTAssertEqual(action, .presentMorningSleep(presentation))
    }

    func testHammockWithoutSleepDataPreservesWaitingStatusCopy() {
        let action = HomeOrnamentInteractionResolver.resolve(
            ornamentID: .hammock,
            sleepReviewGranted: true,
            latestSleepReview: nil,
            recoveryStatusGranted: false,
            recoveryCalibration: .waitingForData
        )

        XCTAssertEqual(action, .presentStatus(CommonItemStatusModel(
            ornamentID: .hammock,
            title: "睡眠回顾",
            status: "等待数据",
            message: "收到可用的睡眠记录后，可以从吊床重复查看最近一次睡眠回顾。"
        )))
    }

    func testStatusObserverPreservesBothCalibrationPresentations() {
        let waiting = resolveStatusObserver(calibration: .waitingForData)
        XCTAssertEqual(waiting, .presentStatus(CommonItemStatusModel(
            ornamentID: .statusObserver,
            title: "恢复状态",
            status: "等待数据",
            message: "状态观测仪会使用已授权的睡眠和身体记录。收到数据后开始校准。"
        )))

        let calibrating = resolveStatusObserver(calibration: .calibrating)
        XCTAssertEqual(calibrating, .presentStatus(CommonItemStatusModel(
            ornamentID: .statusObserver,
            title: "恢复状态",
            status: "正在校准",
            message: "正在依据已授权的原始记录建立个人基线。恢复算法确认前不会显示分数。"
        )))
    }

    func testStatusObserverChecksEntitlementBeforeReadingCalibration() {
        var sleepGrantRead = false
        var sleepReviewRead = false
        var recoveryGrantRead = false
        var recoveryCalibrationRead = false

        let action = HomeOrnamentInteractionResolver.resolve(
            ornamentID: .statusObserver,
            sleepReviewGranted: read(&sleepGrantRead, value: true),
            latestSleepReview: read(&sleepReviewRead, value: sleepPresentation()),
            recoveryStatusGranted: read(&recoveryGrantRead, value: false),
            recoveryCalibration: read(&recoveryCalibrationRead, value: .calibrating)
        )

        XCTAssertEqual(action, .none)
        XCTAssertFalse(sleepGrantRead)
        XCTAssertFalse(sleepReviewRead)
        XCTAssertTrue(recoveryGrantRead)
        XCTAssertFalse(recoveryCalibrationRead)
    }

    func testDecorativeOrnamentsReadNoFeatureData() {
        for ornamentID in [PiboOrnament.ID.chime, .lantern] {
            var sleepGrantRead = false
            var sleepReviewRead = false
            var recoveryGrantRead = false
            var recoveryCalibrationRead = false

            let action = HomeOrnamentInteractionResolver.resolve(
                ornamentID: ornamentID,
                sleepReviewGranted: read(&sleepGrantRead, value: true),
                latestSleepReview: read(&sleepReviewRead, value: sleepPresentation()),
                recoveryStatusGranted: read(&recoveryGrantRead, value: true),
                recoveryCalibration: read(&recoveryCalibrationRead, value: .calibrating)
            )

            XCTAssertEqual(action, .none)
            XCTAssertFalse(sleepGrantRead)
            XCTAssertFalse(sleepReviewRead)
            XCTAssertFalse(recoveryGrantRead)
            XCTAssertFalse(recoveryCalibrationRead)
        }
    }

    private func resolveStatusObserver(
        calibration: RecoveryCalibrationState
    ) -> HomeOrnamentInteractionResolver.Action {
        HomeOrnamentInteractionResolver.resolve(
            ornamentID: .statusObserver,
            sleepReviewGranted: false,
            latestSleepReview: nil,
            recoveryStatusGranted: true,
            recoveryCalibration: calibration
        )
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

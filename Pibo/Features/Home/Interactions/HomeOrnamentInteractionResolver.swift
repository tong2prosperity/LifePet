enum HomeOrnamentInteractionResolver {
    enum Action: Equatable {
        case none
        case presentMorningSleep(MorningSleepPresentation)
        case presentStatus(CommonItemStatusModel)
    }

    static func resolve(
        ornamentID: PiboOrnament.ID,
        sleepReviewGranted: @autoclosure () -> Bool,
        latestSleepReview: @autoclosure () -> MorningSleepPresentation?,
        recoveryStatusGranted: @autoclosure () -> Bool,
        recoveryCalibration: @autoclosure () -> RecoveryCalibrationState
    ) -> Action {
        switch ornamentID {
        case .hammock:
            guard sleepReviewGranted() else { return .none }
            if let presentation = latestSleepReview() {
                return .presentMorningSleep(presentation)
            }
            return .presentStatus(CommonItemStatusModel(
                ornamentID: .hammock,
                title: "睡眠回顾",
                status: "等待数据",
                message: "收到可用的睡眠记录后，可以从吊床重复查看最近一次睡眠回顾。"
            ))
        case .statusObserver:
            guard recoveryStatusGranted() else { return .none }
            let calibration = recoveryCalibration()
            return .presentStatus(CommonItemStatusModel(
                ornamentID: .statusObserver,
                title: "恢复状态",
                status: calibration == .waitingForData ? "等待数据" : "正在校准",
                message: calibration == .waitingForData
                    ? "状态观测仪会使用已授权的睡眠和身体记录。收到数据后开始校准。"
                    : "正在依据已授权的原始记录建立个人基线。恢复算法确认前不会显示分数。"
            ))
        case .chime, .lantern:
            return .none
        }
    }
}

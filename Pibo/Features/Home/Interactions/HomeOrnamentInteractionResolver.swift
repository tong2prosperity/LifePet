enum HomeOrnamentInteractionResolver {
    enum Action: Equatable {
        case none
        case presentMorningSleep(MorningSleepPresentation)
        case presentStatus(CommonItemStatusModel)
        case toggleStatusObserver
    }

    static func resolve(
        ornamentID: PiboOrnament.ID,
        sleepReviewGranted: @autoclosure () -> Bool,
        latestSleepReview: @autoclosure () -> MorningSleepPresentation?,
        recoveryStatusGranted: @autoclosure () -> Bool
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
            return .toggleStatusObserver
        case .chime, .lantern:
            return .none
        }
    }
}

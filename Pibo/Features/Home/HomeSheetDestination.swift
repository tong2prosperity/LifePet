import PiboCore

enum HomeSheetDestination: Equatable, Identifiable {
    case meal(MealType)
    case morningSleep(MorningSleepPresentation, consumesPending: Bool)
    case commonItemStatus(CommonItemStatusModel)
    case achievement(PiboAnimationAchievementPayload)

    var id: String {
        switch self {
        case .meal(let meal): "meal-\(meal.rawValue)"
        case .morningSleep(let presentation, let consumesPending):
            "morning-sleep-\(presentation.id)-\(consumesPending ? "wake" : "hammock")"
        case .commonItemStatus(let model): "common-item-status-\(model.ornamentID.rawValue)"
        case .achievement(let payload): "animation-achievement-\(payload.id)"
        }
    }
}

struct CommonItemStatusModel: Equatable {
    let ornamentID: PiboOrnament.ID
    let title: String
    let status: String
    let message: String
}

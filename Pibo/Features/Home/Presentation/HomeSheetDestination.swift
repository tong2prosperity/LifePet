import PiboCore

enum HomeSheetDestination: Equatable, Identifiable {
    case mealCaptureSelection
    case meal(MealType)
    case morningSleep(MorningSleepPresentation, consumesPending: Bool)
    case commonItemStatus(CommonItemStatusModel)
    case achievement(PiboAnimationAchievementPayload)
    case healthDataStatus
    case ornamentUnlock(PiboOrnament.ID)
    case chimeEcho
    case shadow(manifest: Bool)

    var id: String {
        switch self {
        case .mealCaptureSelection: "meal-capture-selection"
        case .meal(let meal): "meal-\(meal.rawValue)"
        case .morningSleep(let presentation, let consumesPending):
            "morning-sleep-\(presentation.id)-\(consumesPending ? "wake" : "hammock")"
        case .commonItemStatus(let model): "common-item-status-\(model.ornamentID.rawValue)"
        case .achievement(let payload): "animation-achievement-\(payload.id)"
        case .healthDataStatus: "health-data-status"
        case .ornamentUnlock(let id): "ornament-unlock-\(id.rawValue)"
        case .chimeEcho: "chime-echo"
        case .shadow(let manifest): "shadow-friend-\(manifest ? "manifest" : "standard")"
        }
    }
}

struct CommonItemStatusModel: Equatable {
    let ornamentID: PiboOrnament.ID
    let title: String
    let status: String
    let message: String
}

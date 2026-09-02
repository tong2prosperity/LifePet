import Foundation

#if DEBUG
struct HomeDebugLaunchOptions {
    enum ForestHourOverride: Equatable {
        case value(Double?)
    }

    let hidesTuningPanel: Bool
    let forcedAnimationStateID: String?
    let forestHourOverride: ForestHourOverride?
    let simulatesMeal: Bool
    let opensGames: Bool
    let opensHistory: Bool
    let showsMorningSleep: Bool
    let hasAchievementArgument: Bool
    let achievementKind: PiboAnimationAchievementKind?
    let bounceTargetStateID: String?
    let selectedStateIDAfterDelay: String?
    let boProgressMilestone: BoProgressMilestone?
    let opensBoPanel: Bool
    let opensStressCard: Bool
    let showsStatusObserver: Bool

    static var current: Self {
        Self(arguments: ProcessInfo.processInfo.arguments)
    }

    init(
        arguments: [String],
        availableAnimationStateIDs: Set<String> = PiboAnimationStateMap.available
    ) {
        func value(after prefix: String) -> String? {
            guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }) else {
                return nil
            }
            return String(argument.dropFirst(prefix.count))
        }

        hidesTuningPanel = arguments.contains("-PiboHideTuning")
        simulatesMeal = arguments.contains("-PiboSimulateMeal")
        opensGames = arguments.contains("-PiboOpenGames")
        opensHistory = arguments.contains("-PiboOpenHistory")
        showsMorningSleep = arguments.contains("-PiboShowMorningSleep")
        opensBoPanel = arguments.contains("-PiboOpenBoPanel")
        opensStressCard = arguments.contains("-PiboOpenStressCard")
        showsStatusObserver = arguments.contains("-PiboShowStatusObserver")

        let forcedAnimationStateID = value(after: "-PiboAnimationState=")
        self.forcedAnimationStateID = forcedAnimationStateID.flatMap {
            availableAnimationStateIDs.contains($0) ? $0 : nil
        }

        if let forestHour = value(after: "-PiboForestHour=") {
            forestHourOverride = .value(forestHour == "auto" ? nil : Double(forestHour))
        } else {
            forestHourOverride = nil
        }

        let achievement = value(after: "-PiboShowAchievement=")
        hasAchievementArgument = achievement != nil
        achievementKind = achievement.flatMap(PiboAnimationAchievementKind.init(rawValue:))

        let bounceTarget = value(after: "-PiboBounceTo=")
        bounceTargetStateID = bounceTarget.flatMap {
            availableAnimationStateIDs.contains($0) ? $0 : nil
        }

        let selectedState = value(after: "-PiboSelectStateAfter=")
        selectedStateIDAfterDelay = selectedState.flatMap {
            availableAnimationStateIDs.contains($0) ? $0 : nil
        }

        boProgressMilestone = value(after: "-PiboBoProgress=")
            .flatMap(Int.init)
            .flatMap(BoProgressMilestone.init(rawValue:))
    }
}
#endif

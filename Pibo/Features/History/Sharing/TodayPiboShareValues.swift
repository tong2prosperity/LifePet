import Foundation
import PiboCore

struct TodayPiboShareSnapshot: Equatable {
    let petName: String
    let dateLabel: String
    let activityLabel: String
    let assetStateID: String
    let primaryValue: String
    let primaryCaption: String
    let sleepRange: String?
    let activeEnergy: Double?
    let exerciseMinutes: Int?
    let standHours: Int?
    let moveProgress: Double?
    let exerciseProgress: Double?
    let standProgress: Double?

    var hasActivityFacts: Bool {
        activeEnergy != nil || exerciseMinutes != nil || standHours != nil
    }

    var hasHealthFacts: Bool { sleepRange != nil || hasActivityFacts }

    static func make(
        store: PetStateStore,
        record: HealthDayRecord?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Self {
        let sleepSeconds = max(0, store.rawSleepHours * 3_600)
        let active = store.rawActiveEnergy > 0 ? store.rawActiveEnergy : nil
        let exercise = store.rawExerciseMinutes > 0 ? store.rawExerciseMinutes : nil
        let stand = store.rawStandMinutes > 0 ? store.rawStandMinutes / 60 : nil
        var moveProgress: Double?
        var exerciseProgress: Double?
        var standProgress: Double?
        if let record, record.moveGoal > 0, record.exerciseGoal > 0, record.standGoal > 0 {
            let values = PiboCoreActivityWater.intensities(
                activeCalories: store.rawActiveEnergy,
                exerciseMinutes: Double(store.rawExerciseMinutes),
                standHours: Double(store.rawStandMinutes) / 60,
                moveGoal: record.moveGoal,
                exerciseGoal: Double(record.exerciseGoal),
                standGoal: Double(record.standGoal)
            )
            moveProgress = values.move
            exerciseProgress = values.exercise
            standProgress = values.stand
        }

        let primaryValue: String
        let primaryCaption: String
        if sleepSeconds > 0 {
            let minutes = Int((sleepSeconds / 60).rounded())
            primaryValue = "\(minutes / 60) h \(minutes % 60) min"
            primaryCaption = "昨夜睡眠"
        } else if let active {
            primaryValue = "\(Int(active.rounded())) kcal"
            primaryCaption = "今日活动消耗"
        } else {
            primaryValue = store.activityState.displayName
            primaryCaption = "今天的状态"
        }

        return Self(
            petName: String((store.petName.isEmpty ? "Pibo" : store.petName).prefix(24)),
            dateLabel: now.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))),
            activityLabel: store.activityState.displayName,
            assetStateID: assetStateID(for: store.activityState),
            primaryValue: primaryValue,
            primaryCaption: primaryCaption,
            sleepRange: sleepRange(start: store.rawSleepStart, seconds: sleepSeconds),
            activeEnergy: active,
            exerciseMinutes: exercise,
            standHours: stand,
            moveProgress: moveProgress,
            exerciseProgress: exerciseProgress,
            standProgress: standProgress
        )
    }

    static func assetStateID(for state: PiboActivityState) -> String {
        switch state {
        case .sleeping: "pibo-state-sleeping-ground-idle-a"
        case .waking: "pibo-state-waking-ground-behavior-recovering"
        case .energetic: "pibo-event-activity-milestone-celebrate"
        case .tired: "pibo-state-tired-forest-idle"
        default: "pibo-state-stable-forest-idle"
        }
    }

    private static func sleepRange(start: Date?, seconds: TimeInterval) -> String? {
        guard let start, seconds > 0 else { return nil }
        let end = start.addingTimeInterval(seconds)
        return "\(start.formatted(date: .omitted, time: .shortened))—\(end.formatted(date: .omitted, time: .shortened))"
    }
}

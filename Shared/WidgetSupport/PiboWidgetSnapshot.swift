import Foundation

nonisolated enum PiboWidgetConstants {
    static let appGroupID = "group.com.piboworld.app.iPibo"
    static let snapshotKey = "pibo.widget.snapshot.v1"
    static let homeWidgetKind = "fun.tiebao.co.Pibo.widget.home"
}

nonisolated struct PiboWidgetSnapshot: Codable, Hashable, Sendable {
    var petName: String
    var dayCount: Int
    var stateTag: String
    var stateLabel: String
    var vitality: Int
    var energy: Int
    var mood: Int
    var updatedAt: Date
    var pendingWorkoutTitle: String?
    var pendingWorkoutGain: Int?
    /// Real Activity facts only. nil means unavailable, never a synthetic zero.
    var activeEnergy: Double?
    var exerciseMinutes: Int?
    var standHours: Int?
    var moveGoal: Double?
    var exerciseGoal: Double?
    var standGoal: Double?
    var moveProgress: Double?
    var exerciseProgress: Double?
    var standProgress: Double?
    var sceneID: PiboFlatWorldScene?

    static let fallback = PiboWidgetSnapshot(
        petName: "Pibo",
        dayCount: 1,
        stateTag: "dataUnknown",
        stateLabel: "等待数据",
        vitality: 0,
        energy: 0,
        mood: 0,
        updatedAt: Date(),
        pendingWorkoutTitle: nil,
        pendingWorkoutGain: nil,
        activeEnergy: nil,
        exerciseMinutes: nil,
        standHours: nil,
        moveGoal: nil,
        exerciseGoal: nil,
        standGoal: nil,
        moveProgress: nil,
        exerciseProgress: nil,
        standProgress: nil,
        sceneID: .rainGorge
    )
}

nonisolated enum PiboWidgetSnapshotStore {
    static func load() -> PiboWidgetSnapshot {
        let defaults = sharedDefaults()
        guard let data = defaults.data(forKey: PiboWidgetConstants.snapshotKey) else {
            return .fallback
        }

        do {
            return try JSONDecoder().decode(PiboWidgetSnapshot.self, from: data)
        } catch {
            defaults.removeObject(forKey: PiboWidgetConstants.snapshotKey)
            return .fallback
        }
    }

    @discardableResult
    static func save(_ snapshot: PiboWidgetSnapshot) -> Bool {
        do {
            let data = try JSONEncoder().encode(snapshot)
            sharedDefaults().set(data, forKey: PiboWidgetConstants.snapshotKey)
            return true
        } catch {
            return false
        }
    }

    private static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: PiboWidgetConstants.appGroupID) ?? .standard
    }
}

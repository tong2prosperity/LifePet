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

    static let fallback = PiboWidgetSnapshot(
        petName: "Pibo",
        dayCount: 1,
        stateTag: "NORMAL",
        stateLabel: "平稳",
        vitality: 88,
        energy: 74,
        mood: 82,
        updatedAt: Date(),
        pendingWorkoutTitle: nil,
        pendingWorkoutGain: nil
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

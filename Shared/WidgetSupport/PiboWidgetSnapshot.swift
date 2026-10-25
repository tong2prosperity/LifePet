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
    var pixel: PiboCompanionPixelState? = nil
    var activityDayStart: Date? = nil
    /// Health-fact time, separate from metadata/character refreshes.
    var activityUpdatedAt: Date? = nil
    var petID: UUID? = nil
    var standMinutes: Int? = nil
    var activeEnergyUpdatedAt: Date? = nil
    var exerciseMinutesUpdatedAt: Date? = nil
    var standMinutesUpdatedAt: Date? = nil

    /// All widget families render the same persisted character projection.
    @MainActor var pixelLook: PiboPixelCompanionArt.Look {
        .init(stateID: stateTag, bodyStage: pixel?.bodyStage ?? 0,
              leafStage: pixel?.leafStage ?? 0, accessoryMask: pixel?.accessoryMask ?? 0,
              progress: pixel?.boProgress ?? 0, ripe: pixel?.collectionToken != nil,
              form: pixel?.form ?? 0, stuck: pixel?.formStuck ?? false,
              thought: pixel?.thought ?? false)
    }

    func activitySnapshotForDisplay(at date: Date, calendar: Calendar = .current) -> Self {
        var result = self
        let day = activityDayStart ?? activityUpdatedAt ?? updatedAt
        if !calendar.isDate(day, inSameDayAs: date) {
            result.clearActivityFacts()
        }
        return result
    }

    mutating func clearActivityFacts() {
        activeEnergy = nil
        exerciseMinutes = nil
        standMinutes = nil
        standHours = nil
        moveGoal = nil
        exerciseGoal = nil
        standGoal = nil
        moveProgress = nil
        exerciseProgress = nil
        standProgress = nil
        activeEnergyUpdatedAt = nil
        exerciseMinutesUpdatedAt = nil
        standMinutesUpdatedAt = nil
    }

    var activeEnergyText: String { Self.number(activeEnergy) }
    var exerciseMinutesText: String { exerciseMinutes.map { $0 >= 0 ? String($0) : "--" } ?? "--" }
    var standHoursText: String { standHours.map { $0 >= 0 ? String($0) : "--" } ?? "--" }

    private static func number(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "--" }
        return value.rounded(.towardZero).formatted(.number.grouping(.never).precision(.fractionLength(0)))
    }

    /// Ignore transport-only changes when requesting another WidgetKit timeline.
    /// Persist precise acquisition times without reloading for seconds alone.
    func needsReload(comparedTo previous: Self, calendar: Calendar = .current) -> Bool {
        func display(_ snapshot: Self) -> Self {
            var result = snapshot
            result.updatedAt = .distantPast
            result.activeEnergyUpdatedAt = nil
            result.exerciseMinutesUpdatedAt = nil
            result.standMinutesUpdatedAt = nil
            result.activityUpdatedAt = snapshot.activityUpdatedAt.flatMap {
                calendar.dateInterval(of: .minute, for: $0)?.start
            }
            return result
        }
        return display(self) != display(previous)
    }

    func activityStatus(at date: Date, calendar: Calendar = .current) -> String {
        let day = activityDayStart ?? activityUpdatedAt ?? updatedAt
        if !calendar.isDate(day, inSameDayAs: date) { return "等待今日同步" }
        if activeEnergy == nil && exerciseMinutes == nil && standHours == nil { return "等待首次同步" }
        return "更新 " + (activityUpdatedAt ?? updatedAt).formatted(date: .omitted, time: .shortened)
    }

    /// The label a widget should show at `date`.
    func displayStateLabel(at date: Date) -> String {
        return stateLabel
    }

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
        load(from: sharedDefaults())
    }

    static func load(from defaults: UserDefaults?) -> PiboWidgetSnapshot {
        guard let defaults else { return .fallback }
        guard let data = defaults.data(forKey: PiboWidgetConstants.snapshotKey) else {
            return .fallback
        }

        do {
            return try JSONDecoder().decode(PiboWidgetSnapshot.self, from: data)
        } catch {
            return .fallback
        }
    }

    @discardableResult
    static func save(_ snapshot: PiboWidgetSnapshot) -> Bool {
        save(snapshot, to: sharedDefaults())
    }

    @discardableResult
    static func save(_ snapshot: PiboWidgetSnapshot, to defaults: UserDefaults?) -> Bool {
        guard let defaults else { return false }
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: PiboWidgetConstants.snapshotKey)
            return true
        } catch {
            return false
        }
    }

    private static func sharedDefaults() -> UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PiboWidgetConstants.appGroupID) != nil else {
            return nil
        }
        return UserDefaults(suiteName: PiboWidgetConstants.appGroupID)
    }
}

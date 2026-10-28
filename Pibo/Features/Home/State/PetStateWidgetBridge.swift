import Foundation
import os
import PiboCore
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

/// App-owned publishers merge independent identity, health and character updates
/// before replacing the single App Group payload. The extension only reads it.
@MainActor
enum PetStateWidgetBridge {
    static func publishSnapshot(
        petName: @autoclosure () -> String,
        dayCount: @autoclosure () -> Int,
        activityState: @autoclosure () -> PiboActivityState,
        pendingWorkoutTitle: @autoclosure () -> String?,
        petID: UUID? = nil
    ) {
        let previous = PiboWidgetSnapshotStore.load()
        let value = metadataSnapshot(petName: petName(), dayCount: dayCount(), activityState: activityState(),
                                     pendingWorkoutTitle: pendingWorkoutTitle(), petID: petID, retaining: previous)
        save(value, replacing: previous)
    }

    static func reloadHomeWidget() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: PiboWidgetConstants.homeWidgetKind)
        #endif
    }

    static func snapshot(petName: String, dayCount: Int, stateTag: String, stateLabel: String,
                         updatedAt: Date, pendingWorkoutTitle: String?, petID: UUID? = nil) -> PiboWidgetSnapshot {
        PiboWidgetSnapshot(petName: petName, dayCount: dayCount, stateTag: stateTag, stateLabel: stateLabel,
                           vitality: 0, energy: 0, mood: 0, updatedAt: updatedAt,
                           pendingWorkoutTitle: pendingWorkoutTitle,
                           sceneID: PiboFlatWorldScene.recommended(petName: petName, choices: PiboFlatWorldScene.widgetCycle),
                           petID: petID)
    }

    static func metadataSnapshot(petName: String, dayCount: Int, activityState: PiboActivityState,
                                 pendingWorkoutTitle: String? = nil, petID: UUID? = nil,
                                 retaining previous: PiboWidgetSnapshot? = nil, now: Date = .now) -> PiboWidgetSnapshot {
        var value = previous.flatMap { $0.petID == petID ? $0 : nil }
            ?? snapshot(petName: petName, dayCount: dayCount, stateTag: activityState.rawValue,
                        stateLabel: activityState.displayName, updatedAt: now,
                        pendingWorkoutTitle: pendingWorkoutTitle, petID: petID)
        // Adopt the old v1 timestamp once; chrome updates never freshen health facts.
        if value.activityUpdatedAt == nil,
           value.activeEnergy != nil || value.exerciseMinutes != nil || value.standHours != nil {
            value.activityUpdatedAt = value.updatedAt
        }
        value.petName = petName
        value.discardLegacyStandHours()
        value.dayCount = dayCount
        value.stateTag = activityState.rawValue
        value.stateLabel = activityState.displayName
        value.pendingWorkoutTitle = pendingWorkoutTitle
        value.updatedAt = now
        value.sceneID = PiboFlatWorldScene.recommended(petName: petName, choices: PiboFlatWorldScene.widgetCycle)
        return value
    }

    static func publishActivitySnapshot(petName: String, dayCount: Int, activityState: PiboActivityState,
                                        record: HealthDayRecord?, petID: UUID? = nil) {
        let previous = PiboWidgetSnapshotStore.load()
        save(activitySnapshot(petName: petName, dayCount: dayCount, activityState: activityState,
                              record: record, pendingWorkoutTitle: previous.pendingWorkoutTitle,
                              retaining: previous, petID: petID), replacing: previous)
    }

    static func publishPixelSnapshot(petName: String, dayCount: Int, activityState: PiboActivityState,
                                    record: HealthDayRecord?, petID: UUID, pixel: PiboCompanionPixelState) {
        let previous = PiboWidgetSnapshotStore.load()
        var value = activitySnapshot(petName: petName, dayCount: dayCount, activityState: activityState,
                                     record: record, retaining: previous, petID: petID)
        value.pixel = pixel
        save(value, replacing: previous)
    }

    static func activitySnapshot(petName: String, dayCount: Int, activityState: PiboActivityState,
                                 record: HealthDayRecord?, pendingWorkoutTitle: String? = nil,
                                 retaining previous: PiboWidgetSnapshot? = nil,
                                 petID: UUID? = nil) -> PiboWidgetSnapshot {
        var value = metadataSnapshot(petName: petName, dayCount: dayCount, activityState: activityState,
                                     pendingWorkoutTitle: pendingWorkoutTitle, petID: petID, retaining: previous)
        guard let record, adoptActivityDay(record.date, in: &value) else { return value }
        // Legacy rows have only a generic edit time. They may bootstrap a
        // missing field, but must not replace an explicitly queried live value.
        let energyObserved = record.activeEnergyObservedAt
            ?? (value.activeEnergyUpdatedAt == nil ? record.updatedAt : .distantPast)
        let exerciseObserved = record.exerciseObservedAt
            ?? (value.exerciseMinutesUpdatedAt == nil ? record.updatedAt : .distantPast)
        let standObserved = record.standObservedAt
            ?? (value.standMinutesUpdatedAt == nil ? record.updatedAt : .distantPast)
        let standHoursObserved = record.standHoursObservedAt
            ?? (value.standHoursUpdatedAt == nil ? record.updatedAt : .distantPast)
        if let amount = record.recordedActiveEnergy, amount.isFinite, amount >= 0,
           energyObserved >= (value.activeEnergyUpdatedAt ?? (value.activeEnergy != nil ? value.activityUpdatedAt : nil) ?? .distantPast) {
            value.activeEnergy = amount
            value.activeEnergyUpdatedAt = energyObserved
        }
        if let minutes = record.recordedExerciseMinutes, minutes >= 0,
           exerciseObserved >= (value.exerciseMinutesUpdatedAt ?? (value.exerciseMinutes != nil ? value.activityUpdatedAt : nil) ?? .distantPast) {
            value.exerciseMinutes = minutes
            value.exerciseMinutesUpdatedAt = exerciseObserved
        }
        if let minutes = record.recordedStandMinutes, minutes >= 0,
           standObserved >= (value.standMinutesUpdatedAt ?? .distantPast) {
            value.standMinutes = minutes
            value.standMinutesUpdatedAt = standObserved
        }
        if let hours = record.standHours, hours >= 0,
           standHoursObserved >= (value.standHoursUpdatedAt ?? .distantPast) {
            value.standHours = hours
            value.standHoursUpdatedAt = standHoursObserved
        }
        if record.moveGoal.isFinite, record.moveGoal > 0 { value.moveGoal = record.moveGoal }
        if record.exerciseGoal > 0 { value.exerciseGoal = Double(record.exerciseGoal) }
        if record.standGoal > 0 { value.standGoal = Double(record.standGoal) }
        updateActivityTimeAndProgress(&value)
        return value
    }

    static func publishActivityUpdate(_ update: HealthActivityUpdate, petName: String, dayCount: Int,
                                      activityState: PiboActivityState, petID: UUID) {
        let previous = PiboWidgetSnapshotStore.load()
        guard let value = activityUpdateSnapshot(update, petName: petName, dayCount: dayCount,
                                                 activityState: activityState, petID: petID,
                                                 retaining: previous) else { return }
        save(value, replacing: previous)
    }

    static func activityUpdateSnapshot(_ update: HealthActivityUpdate, petName: String, dayCount: Int,
                                       activityState: PiboActivityState, petID: UUID,
                                       retaining previous: PiboWidgetSnapshot?, now: Date = .now,
                                       calendar: Calendar = .current) -> PiboWidgetSnapshot? {
        guard update.dayStart == calendar.startOfDay(for: now),
              calendar.isDate(update.asOf, inSameDayAs: update.dayStart),
              update.asOf >= update.dayStart, update.asOf <= now,
              update.value.map({ $0.isFinite && $0 >= 0 }) ?? true else { return nil }
        var value = metadataSnapshot(petName: petName, dayCount: dayCount, activityState: activityState,
                                     petID: petID, retaining: previous, now: now)
        // A time-zone change can move today's boundary backwards. This is a
        // newly queried current-day window, not an older day's delayed result.
        if value.activityDayStart != update.dayStart {
            value.clearActivityFacts()
            value.activityUpdatedAt = nil
            value.activityDayStart = update.dayStart
        }
        switch update.metric {
        case .activeEnergy:
            guard update.asOf >= (value.activeEnergyUpdatedAt ?? (value.activeEnergy != nil ? value.activityUpdatedAt : nil) ?? .distantPast) else { return nil }
            value.activeEnergy = update.value
            value.activeEnergyUpdatedAt = update.asOf
        case .exerciseMinutes:
            guard update.value.map({ $0 < Double(Int.max) }) ?? true,
                  update.asOf >= (value.exerciseMinutesUpdatedAt ?? (value.exerciseMinutes != nil ? value.activityUpdatedAt : nil) ?? .distantPast) else { return nil }
            value.exerciseMinutes = update.value.map { Int($0) }
            value.exerciseMinutesUpdatedAt = update.asOf
        case .standMinutes:
            guard update.value.map({ $0 < Double(Int.max) }) ?? true,
                  update.asOf >= (value.standMinutesUpdatedAt ?? .distantPast) else { return nil }
            value.standMinutes = update.value.map { Int($0) }
            value.standMinutesUpdatedAt = update.asOf
        case .standHours:
            guard update.value.map({ Int(exactly: $0) != nil }) ?? true,
                  update.asOf >= (value.standHoursUpdatedAt ?? .distantPast) else { return nil }
            value.standHours = update.value.flatMap { Int(exactly: $0) }
            value.standHoursUpdatedAt = update.asOf
            if let goal = update.goal, goal.isFinite, goal > 0 { value.standGoal = goal }
        }
        updateActivityTimeAndProgress(&value)
        return value
    }

    private static func adoptActivityDay(_ day: Date, in value: inout PiboWidgetSnapshot,
                                         calendar: Calendar = .current) -> Bool {
        let incoming = calendar.startOfDay(for: day)
        let previous = value.activityDayStart
            ?? value.activityUpdatedAt.map { calendar.startOfDay(for: $0) }
        if let previous, incoming < previous { return false }
        if previous != incoming {
            value.clearActivityFacts()
            value.activityUpdatedAt = nil
        }
        value.activityDayStart = incoming
        return true
    }

    private static func updateActivityTimeAndProgress(_ value: inout PiboWidgetSnapshot) {
        value.activityUpdatedAt = [value.activityUpdatedAt, value.activeEnergyUpdatedAt,
                                  value.exerciseMinutesUpdatedAt, value.standMinutesUpdatedAt,
                                  value.standHoursUpdatedAt].compactMap { $0 }.max()
        let normalized = PiboCoreActivityWater.intensities(
            activeCalories: value.activeEnergy ?? 0, exerciseMinutes: Double(value.exerciseMinutes ?? 0),
            standHours: Double(value.standHours ?? 0),
            moveGoal: value.moveGoal ?? 0, exerciseGoal: value.exerciseGoal ?? 0, standGoal: value.standGoal ?? 0)
        value.moveProgress = value.activeEnergy != nil && (value.moveGoal ?? 0) > 0 ? normalized.move : nil
        value.exerciseProgress = value.exerciseMinutes != nil && (value.exerciseGoal ?? 0) > 0 ? normalized.exercise : nil
        value.standProgress = value.standHours != nil && (value.standGoal ?? 0) > 0 ? normalized.stand : nil
    }

    private static func save(_ value: PiboWidgetSnapshot, replacing previous: PiboWidgetSnapshot) {
        var comparable = value
        comparable.updatedAt = previous.updatedAt
        guard comparable != previous else { return }
        guard PiboWidgetSnapshotStore.save(value) else {
            LPLog.petState.error("widget App Group snapshot save failed")
            return
        }
        if value.needsReload(comparedTo: previous) { reloadHomeWidget() }
    }

    #if canImport(ActivityKit)
    /// Decision 055 retired workout Live Activities. Clear instances left by
    /// older builds; ordinary widgets and their shared snapshots remain live.
    static func endRetiredWorkoutActivities() {
        Task { @MainActor in
            for activity in Activity<PiboFeedActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    static func finishPendingWorkoutActivity(
        for workout: PendingWorkout,
        completed: Bool,
        activityState: @autoclosure () -> PiboActivityState
    ) {
        let contentState = finishedActivityState(
            for: workout,
            completed: completed,
            stateTag: activityState().rawValue
        )
        let content = ActivityContent(state: contentState, staleDate: Date())

        Task { @MainActor in
            let activities = Activity<PiboFeedActivityAttributes>.activities
                .filter { $0.attributes.workoutID == workout.id }
            guard !activities.isEmpty else { return }

            for activity in activities {
                await activity.end(
                    content,
                    dismissalPolicy: completed
                        ? .after(Date().addingTimeInterval(8))
                        : .immediate
                )
            }
            LPLog.petState.notice(
                "Live Activity ended for pending workout \(workout.id.uuidString, privacy: .public)"
            )
        }
    }

    static func pendingActivityState(
        for workout: PendingWorkout,
        stateTag: String
    ) -> PiboFeedActivityAttributes.ContentState {
        PiboFeedActivityAttributes.ContentState(
            title: workout.titleLabel,
            message: "收到一条新的运动记录",
            vitalityGain: workout.gainVitality,
            stateTag: stateTag,
            endedAt: workout.endedAt,
            isComplete: false
        )
    }

    static func finishedActivityState(
        for workout: PendingWorkout,
        completed: Bool,
        stateTag: String
    ) -> PiboFeedActivityAttributes.ContentState {
        PiboFeedActivityAttributes.ContentState(
            title: "\(workout.titleLabel)已记录",
            message: completed
                ? "运动记录已同步，会用于之后的可见积累"
                : "运动已记录到今天的足迹",
            vitalityGain: workout.gainVitality,
            stateTag: stateTag,
            endedAt: workout.endedAt,
            isComplete: true
        )
    }
    #else
    static func startOrUpdatePendingWorkoutActivity(
        for workout: PendingWorkout,
        petName: @autoclosure () -> String,
        activityState: @autoclosure () -> PiboActivityState
    ) {}

    static func finishPendingWorkoutActivity(
        for workout: PendingWorkout,
        completed: Bool,
        activityState: @autoclosure () -> PiboActivityState
    ) {}
    #endif
}

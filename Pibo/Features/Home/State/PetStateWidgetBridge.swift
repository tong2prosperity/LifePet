import Foundation
import os
import PiboCore
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Owns the widget snapshot and pending-workout Live Activity side effects
/// emitted by `PetStateStore`. Inputs remain lazy where the original store
/// read them lazily, so disabled Live Activities do not trigger extra state
/// derivation.
@MainActor
enum PetStateWidgetBridge {
    static func publishSnapshot(
        petName: @autoclosure () -> String,
        dayCount: @autoclosure () -> Int,
        activityState: @autoclosure () -> PiboActivityState,
        pendingWorkoutTitle: @autoclosure () -> String?
    ) {
        let snapshot = snapshot(
            petName: petName(),
            dayCount: dayCount(),
            stateTag: activityState().rawValue,
            stateLabel: activityState().displayName,
            updatedAt: Date(),
            pendingWorkoutTitle: pendingWorkoutTitle()
        )
        var merged = snapshot
        let previous = PiboWidgetSnapshotStore.load()
        merged.activeEnergy = previous.activeEnergy
        merged.exerciseMinutes = previous.exerciseMinutes
        merged.standHours = previous.standHours
        merged.moveGoal = previous.moveGoal
        merged.exerciseGoal = previous.exerciseGoal
        merged.standGoal = previous.standGoal
        merged.moveProgress = previous.moveProgress
        merged.exerciseProgress = previous.exerciseProgress
        merged.standProgress = previous.standProgress
        merged.sceneID = PiboFlatWorldScene.recommended(
            petName: merged.petName,
            choices: PiboFlatWorldScene.widgetCycle
        )

        if !PiboWidgetSnapshotStore.save(merged) {
            LPLog.petState.error("widget snapshot save failed")
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(
            ofKind: PiboWidgetConstants.homeWidgetKind
        )
        #endif
    }

    static func snapshot(
        petName: String,
        dayCount: Int,
        stateTag: String,
        stateLabel: String,
        updatedAt: Date,
        pendingWorkoutTitle: String?
    ) -> PiboWidgetSnapshot {
        PiboWidgetSnapshot(
            petName: petName,
            dayCount: dayCount,
            stateTag: stateTag,
            stateLabel: stateLabel,
            // Kept in the v1 payload only so installed widgets can decode the
            // snapshot during migration; current product surfaces ignore them.
            vitality: 0,
            energy: 0,
            mood: 0,
            updatedAt: updatedAt,
            pendingWorkoutTitle: pendingWorkoutTitle,
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
            sceneID: PiboFlatWorldScene.recommended(
                petName: petName,
                choices: PiboFlatWorldScene.widgetCycle
            )
        )
    }

    static func publishActivitySnapshot(
        petName: String,
        dayCount: Int,
        activityState: PiboActivityState,
        record: HealthDayRecord?
    ) {
        let value = activitySnapshot(
            petName: petName,
            dayCount: dayCount,
            activityState: activityState,
            record: record,
            pendingWorkoutTitle: PiboWidgetSnapshotStore.load().pendingWorkoutTitle
        )
        if PiboWidgetSnapshotStore.save(value) {
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: PiboWidgetConstants.homeWidgetKind)
            #endif
        }
    }

    static func activitySnapshot(
        petName: String,
        dayCount: Int,
        activityState: PiboActivityState,
        record: HealthDayRecord?,
        pendingWorkoutTitle: String? = nil
    ) -> PiboWidgetSnapshot {
        var value = snapshot(
            petName: petName,
            dayCount: dayCount,
            stateTag: activityState.rawValue,
            stateLabel: activityState.displayName,
            updatedAt: record?.updatedAt ?? .now,
            pendingWorkoutTitle: pendingWorkoutTitle
        )
        if let record {
            value.activeEnergy = record.activeEnergy > 0 ? record.activeEnergy : nil
            value.exerciseMinutes = record.exerciseMinutes > 0 ? record.exerciseMinutes : nil
            value.standHours = record.standMinutes > 0 ? record.standMinutes / 60 : nil
            if record.moveGoal > 0, record.exerciseGoal > 0, record.standGoal > 0 {
                value.moveGoal = record.moveGoal
                value.exerciseGoal = Double(record.exerciseGoal)
                value.standGoal = Double(record.standGoal)
                let normalized = PiboCoreActivityWater.intensities(
                    activeCalories: record.activeEnergy,
                    exerciseMinutes: Double(record.exerciseMinutes),
                    standHours: Double(record.standMinutes) / 60,
                    moveGoal: record.moveGoal,
                    exerciseGoal: Double(record.exerciseGoal),
                    standGoal: Double(record.standGoal)
                )
                value.moveProgress = normalized.move
                value.exerciseProgress = normalized.exercise
                value.standProgress = normalized.stand
            }
        }
        return value
    }

    #if canImport(ActivityKit)
    static func startOrUpdatePendingWorkoutActivity(
        for workout: PendingWorkout,
        petName: @autoclosure () -> String,
        activityState: @autoclosure () -> PiboActivityState
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            LPLog.petState.notice(
                "Live Activity skipped — activities disabled"
            )
            return
        }

        let attributes = PiboFeedActivityAttributes(
            petName: petName(),
            workoutID: workout.id
        )
        let contentState = pendingActivityState(
            for: workout,
            stateTag: activityState().rawValue
        )
        let content = ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(
                PiboCoreWorkoutAdapter.pendingWorkoutMaxAgeSeconds
            )
        )

        Task { @MainActor in
            let activities = Activity<PiboFeedActivityAttributes>.activities
            if let existing = activities.first(where: {
                $0.attributes.workoutID == workout.id
            }) {
                await existing.update(content)
                return
            }

            for activity in activities
            where activity.attributes.workoutID != workout.id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }

            do {
                _ = try Activity<PiboFeedActivityAttributes>.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                LPLog.petState.notice(
                    "Live Activity started for pending workout \(workout.id.uuidString, privacy: .public)"
                )
            } catch {
                LPLog.petState.error(
                    "Live Activity request failed: \(error.localizedDescription, privacy: .public)"
                )
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

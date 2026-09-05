import Foundation
import Testing
@testable import Pibo

@MainActor
struct PetStateWidgetBridgeTests {
    @Test func widgetSnapshotPreservesTheVersionOnePayloadMapping() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)

        let snapshot = PetStateWidgetBridge.snapshot(
            petName: "Pibo",
            dayCount: 17,
            stateTag: PiboActivityState.energetic.rawValue,
            stateLabel: PiboActivityState.energetic.displayName,
            updatedAt: updatedAt,
            pendingWorkoutTitle: "跑步完成"
        )

        #expect(snapshot.petName == "Pibo")
        #expect(snapshot.dayCount == 17)
        #expect(snapshot.stateTag == PiboActivityState.energetic.rawValue)
        #expect(snapshot.stateLabel == PiboActivityState.energetic.displayName)
        #expect(snapshot.vitality == 0)
        #expect(snapshot.energy == 0)
        #expect(snapshot.mood == 0)
        #expect(snapshot.updatedAt == updatedAt)
        #expect(snapshot.pendingWorkoutTitle == "跑步完成")
        #expect(snapshot.pendingWorkoutGain == nil)
        #expect(snapshot.activeEnergy == nil)
        #expect(snapshot.moveProgress == nil)
        #expect(PiboFlatWorldScene.widgetCycle.contains(try #require(snapshot.sceneID)))
    }

    @Test func activitySnapshotUsesRealFactsAndOnlyRealGoals() {
        let record = HealthDayRecord(
            date: Calendar.current.startOfDay(for: .now),
            activeEnergy: 240,
            exerciseMinutes: 18,
            standMinutes: 360,
            moveGoal: 600,
            exerciseGoal: 30,
            standGoal: 12,
            updatedAt: .now
        )
        let value = PetStateWidgetBridge.activitySnapshot(
            petName: "Pibo",
            dayCount: 8,
            activityState: .stable,
            record: record
        )

        #expect(value.activeEnergy == 240)
        #expect(value.exerciseMinutes == 18)
        #expect(value.standHours == 6)
        #expect(value.moveGoal == 600)
        #expect(value.exerciseGoal == 30)
        #expect(value.standGoal == 12)
        #expect(value.moveProgress != nil)
        #expect(value.exerciseProgress != nil)
        #expect(value.standProgress != nil)

        record.moveGoal = 0
        let missingGoals = PetStateWidgetBridge.activitySnapshot(
            petName: "Pibo",
            dayCount: 8,
            activityState: .stable,
            record: record
        )
        #expect(missingGoals.activeEnergy == 240)
        #expect(missingGoals.moveProgress == nil)
        #expect(missingGoals.exerciseProgress == nil)
        #expect(missingGoals.standProgress == nil)
    }

    @Test func versionOneSnapshotWithoutActivityFieldsStillDecodes() throws {
        let data = Data(#"{"petName":"Pibo","dayCount":1,"stateTag":"dataUnknown","stateLabel":"等待数据","vitality":0,"energy":0,"mood":0,"updatedAt":0}"#.utf8)
        let decoded = try JSONDecoder().decode(PiboWidgetSnapshot.self, from: data)
        #expect(decoded.activeEnergy == nil)
        #expect(decoded.exerciseMinutes == nil)
        #expect(decoded.sceneID == nil)
    }

    #if canImport(ActivityKit)
    @Test func pendingActivityStatePreservesWorkoutAndPiboState() {
        let workout = workout()

        let state = PetStateWidgetBridge.pendingActivityState(
            for: workout,
            stateTag: PiboActivityState.tired.rawValue
        )

        #expect(state.title == workout.titleLabel)
        #expect(state.message == "收到一条新的运动记录")
        #expect(state.vitalityGain == workout.gainVitality)
        #expect(state.stateTag == PiboActivityState.tired.rawValue)
        #expect(state.endedAt == workout.endedAt)
        #expect(!state.isComplete)
    }

    @Test(arguments: [
        (true, "运动记录已同步，会用于之后的可见积累"),
        (false, "运动已记录到今天的足迹"),
    ])
    func finishedActivityStatePreservesCompletionCopy(
        completed: Bool,
        message: String
    ) {
        let workout = workout()

        let state = PetStateWidgetBridge.finishedActivityState(
            for: workout,
            completed: completed,
            stateTag: PiboActivityState.stable.rawValue
        )

        #expect(state.title == "\(workout.titleLabel)已记录")
        #expect(state.message == message)
        #expect(state.vitalityGain == workout.gainVitality)
        #expect(state.stateTag == PiboActivityState.stable.rawValue)
        #expect(state.endedAt == workout.endedAt)
        #expect(state.isComplete)
    }
    #endif

    private func workout() -> PendingWorkout {
        PendingWorkout(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            kind: .run,
            label: "跑步",
            durationMin: 24,
            kcal: 180,
            endedAt: Date(timeIntervalSince1970: 1_700_000_000),
            gainVitality: 20
        )
    }
}

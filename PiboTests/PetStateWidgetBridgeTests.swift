import Foundation
import Testing
@testable import Pibo

@MainActor
struct PetStateWidgetBridgeTests {
    @Test func widgetSnapshotPreservesTheVersionOnePayloadMapping() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)

        let snapshot = PetStateWidgetBridge.snapshot(
            petName: "Pibo",
            dayCount: 17,
            stateTag: PiboActivityState.active.rawValue,
            stateLabel: PiboActivityState.active.displayName,
            updatedAt: updatedAt,
            pendingWorkoutTitle: "跑步完成"
        )

        #expect(snapshot.petName == "Pibo")
        #expect(snapshot.dayCount == 17)
        #expect(snapshot.stateTag == PiboActivityState.active.rawValue)
        #expect(snapshot.stateLabel == PiboActivityState.active.displayName)
        #expect(snapshot.vitality == 0)
        #expect(snapshot.energy == 0)
        #expect(snapshot.mood == 0)
        #expect(snapshot.updatedAt == updatedAt)
        #expect(snapshot.pendingWorkoutTitle == "跑步完成")
        #expect(snapshot.pendingWorkoutGain == nil)
    }

    #if canImport(ActivityKit)
    @Test func pendingActivityStatePreservesWorkoutAndPiboState() {
        let workout = workout()

        let state = PetStateWidgetBridge.pendingActivityState(
            for: workout,
            stateTag: PiboActivityState.irritated.rawValue
        )

        #expect(state.title == workout.titleLabel)
        #expect(state.message == "收到一条新的运动记录")
        #expect(state.vitalityGain == workout.gainVitality)
        #expect(state.stateTag == PiboActivityState.irritated.rawValue)
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
            stateTag: PiboActivityState.idle.rawValue
        )

        #expect(state.title == "\(workout.titleLabel)已记录")
        #expect(state.message == message)
        #expect(state.vitalityGain == workout.gainVitality)
        #expect(state.stateTag == PiboActivityState.idle.rawValue)
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

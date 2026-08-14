import Foundation
import Testing
@testable import Pibo

@MainActor
struct PetStateDailySnapshotFactoryTests {
    @Test func projectsEveryPersistedFieldWithoutReorderingCompletedSteps() {
        let petID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let inputDate = Date(timeIntervalSince1970: 1_723_456_789)
        let updatedAt = Date(timeIntervalSince1970: 1_723_499_999)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        var raw = RawMetrics()
        raw.steps = 12_345
        raw.exerciseMinutes = 42
        raw.activeEnergy = 678.5
        raw.standMinutes = 93
        raw.hrv = 57.25
        raw.restingHR = 61
        raw.sleepTotal = 28_800
        raw.sleepDeep = 5_400
        raw.sleepREM = 7_200
        raw.mindfulMinutes = 11

        let snapshot = PetStateDailySnapshotFactory.make(
            petId: petID,
            date: inputDate,
            stats: [
                Stat(kind: .mood, value: 73),
                Stat(kind: .vitality, value: 91),
                Stat(kind: .energy, value: 82)
            ],
            state: .excited,
            raw: raw,
            steps: [
                Self.step(kind: .walk, status: .done),
                Self.step(kind: .sleep, status: .suggest),
                Self.step(kind: .meditate, status: .done)
            ],
            calendar: calendar,
            now: { updatedAt }
        )

        #expect(snapshot.petId == petID)
        #expect(snapshot.date == calendar.startOfDay(for: inputDate))
        #expect(snapshot.vitality == 91)
        #expect(snapshot.energy == 82)
        #expect(snapshot.mood == 73)
        #expect(snapshot.stateTag == "EXCITED")
        #expect(snapshot.steps == 12_345)
        #expect(snapshot.exerciseMinutes == 42)
        #expect(snapshot.activeEnergy == 678.5)
        #expect(snapshot.standMinutes == 93)
        #expect(snapshot.hrv == 57.25)
        #expect(snapshot.restingHR == 61)
        #expect(snapshot.sleepTotal == 28_800)
        #expect(snapshot.sleepDeep == 5_400)
        #expect(snapshot.sleepREM == 7_200)
        #expect(snapshot.mindfulMinutes == 11)
        #expect(snapshot.completedStepKinds == ["walk", "meditate"])
        #expect(snapshot.updatedAt == updatedAt)
    }

    @Test func missingStatsKeepTheExistingZeroFallbackAndClockRunsOnce() {
        var events: [String] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let snapshot = PetStateDailySnapshotFactory.make(
            petId: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            stats: [],
            state: .normal,
            raw: RawMetrics(),
            steps: [],
            calendar: calendar,
            now: {
                events.append("now")
                return Date(timeIntervalSince1970: 1_700_000_100)
            }
        )

        #expect(snapshot.vitality == 0)
        #expect(snapshot.energy == 0)
        #expect(snapshot.mood == 0)
        #expect(events == ["now"])
    }

    private static func step(kind: StepKind, status: StepStatus) -> StepItem {
        StepItem(
            status: status,
            kind: kind,
            actionLabel: "fixture",
            titleValue: "fixture",
            affects: .vitality,
            gain: 0,
            time: "fixture",
            fromAutoSensor: false
        )
    }
}

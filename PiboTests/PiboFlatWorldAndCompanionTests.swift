import Foundation
import Testing
@testable import Pibo

struct PiboFlatWorldAndCompanionTests {
    @Test func recommendationIsStableForOneLocalCivilDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let morning = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 3, hour: 1
        )))
        let night = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 3, hour: 23
        )))

        let first = PiboFlatWorldScene.recommended(
            petName: "Pibo",
            date: morning,
            calendar: calendar,
            choices: PiboFlatWorldScene.widgetCycle
        )
        let second = PiboFlatWorldScene.recommended(
            petName: "Pibo",
            date: night,
            calendar: calendar,
            choices: PiboFlatWorldScene.widgetCycle
        )
        #expect(first == second)
        #expect(PiboFlatWorldScene.widgetCycle.contains(first))
    }

    @Test func companionSnapshotRejectsUnknownFutureStaleAndWrongDayData() {
        let now = Date(timeIntervalSince1970: 1_788_400_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let dayStart = calendar.startOfDay(for: now)

        #expect(snapshot(dayStart: dayStart, generatedAt: now).isAcceptable(now: now, calendar: calendar))
        #expect(!snapshot(dayStart: dayStart, generatedAt: now.addingTimeInterval(301)).isAcceptable(now: now, calendar: calendar))
        #expect(!snapshot(dayStart: dayStart, generatedAt: now.addingTimeInterval(-86_401)).isAcceptable(now: now, calendar: calendar))
        #expect(!snapshot(dayStart: dayStart.addingTimeInterval(-86_400), generatedAt: now).isAcceptable(now: now, calendar: calendar))
        #expect(!snapshot(dayStart: dayStart, generatedAt: now, state: "dataUnknown").isAcceptable(now: now, calendar: calendar))
        #expect(!snapshot(dayStart: dayStart, generatedAt: now, schemaVersion: 2).isAcceptable(now: now, calendar: calendar))
    }

    @Test func companionWireRoundTripsWithoutRawHealthFields() throws {
        let value = snapshot(dayStart: .now, generatedAt: .now)
        let data = try #require(PiboCompanionSnapshotCoding.encode(value))
        #expect(PiboCompanionSnapshotCoding.decode(data) == value)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["heartRate"] == nil)
        #expect(object["stress"] == nil)
        #expect(object["bo"] == nil)
    }

    @Test func shadowProjectionRejectsUnknownAndStalePublicState() {
        let now = Date(timeIntervalSince1970: 1_788_400_000)
        let valid = shadow(state: "stable", syncedAt: now)
        #expect(valid.isAcceptable(now: now))
        #expect(!shadow(state: "dataUnknown", syncedAt: now).isAcceptable(now: now))
        #expect(!shadow(state: "stable", syncedAt: now.addingTimeInterval(-86_401)).isAcceptable(now: now))
    }

    private func snapshot(
        dayStart: Date,
        generatedAt: Date,
        state: String = "stable",
        schemaVersion: Int = 1
    ) -> PiboCompanionSnapshot {
        PiboCompanionSnapshot(
            schemaVersion: schemaVersion,
            petName: "Pibo",
            dayStart: dayStart,
            generatedAt: generatedAt,
            publicStateID: state,
            animationStateID: "pibo-state-stable-forest-idle",
            stateLabel: "平稳",
            activeEnergy: 120,
            exerciseMinutes: 20,
            standHours: 6,
            moveProgress: 0.3,
            exerciseProgress: 0.4,
            standProgress: 0.5,
            sceneID: .riverValley,
            shadow: nil
        )
    }

    private func shadow(state: String, syncedAt: Date) -> PiboCompanionShadowSnapshot {
        PiboCompanionShadowSnapshot(
            displayName: "小岚",
            publicStateID: state,
            publicBehaviorSubstateID: "stable.idle",
            visualVariantKey: "pibo-state-stable-forest-idle",
            revision: 3,
            occurredAt: syncedAt,
            syncedAt: syncedAt
        )
    }
}

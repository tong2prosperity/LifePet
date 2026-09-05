import Foundation
import Testing
import UIKit
@testable import Pibo

@Suite(.serialized)
@MainActor
struct TodayPiboShareTests {
    @Test func factHierarchyPrefersSleepThenActivityThenSemanticState() {
        let store = PetStateStore(demoMode: false)
        store.ingest(.activeEnergy(186))
        store.ingest(.exerciseMinutes(24))
        store.ingest(.standMinutes(360))

        let activity = TodayPiboShareSnapshot.make(store: store, record: nil)
        #expect(activity.primaryCaption == "今日活动消耗")
        #expect(activity.primaryValue == "186 kcal")
        #expect(activity.activeEnergy == 186)
        #expect(activity.moveProgress == nil)

        store.ingest(.sleep(total: 7.5 * 3_600, deep: 0, rem: 0, start: .now.addingTimeInterval(-8 * 3_600)))
        let sleeping = TodayPiboShareSnapshot.make(store: store, record: nil)
        #expect(sleeping.primaryCaption == "昨夜睡眠")
        #expect(sleeping.primaryValue == "7 h 30 min")
        #expect(sleeping.sleepRange != nil)
    }

    @Test func exportIsAnExactLosslessThreeByFourPNG() throws {
        let snapshot = TodayPiboShareSnapshot(
            petName: "Pibo",
            dateLabel: "9月3日",
            activityLabel: "平稳",
            assetStateID: "pibo-state-stable-forest-idle",
            primaryValue: "186 kcal",
            primaryCaption: "今日活动消耗",
            sleepRange: nil,
            activeEnergy: 186,
            exerciseMinutes: 24,
            standHours: 6,
            moveProgress: nil,
            exerciseProgress: nil,
            standProgress: nil
        )
        let url = try TodayPiboShareService.export(
            snapshot: snapshot,
            scene: .riverValley,
            characterImage: nil
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try #require(UIImage(contentsOfFile: url.path)?.cgImage)
        #expect(image.width == 1080)
        #expect(image.height == 1440)
        #expect(url.pathExtension == "png")
    }
}

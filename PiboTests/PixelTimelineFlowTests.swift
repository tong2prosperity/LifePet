import Foundation
import PiboCore
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct PixelTimelineFlowTests {
    @Test func fullCatalogContainsOrderedThreadsAndValidatedMemoryConditions() throws {
        let catalog = try #require(PiboCompanionCatalog.bundled())
        #expect(catalog.threadBeats.count == 14)
        #expect(!catalog.remarks.isEmpty)
        #expect(catalog.firstRecalls.count == 4)
        #expect(catalog.phaseWords.count == 4)
        let pat = PiboPatCatalog.bundled()
        let gentle = pat.units(for: .stableIdle, storyStage: "unresponded", tone: 0)
        let familiar = pat.units(for: .stableIdle, storyStage: "unresponded", tone: 2)
        #expect(familiar.count > gentle.count)
        #expect(gentle.allSatisfy { ($0.minTone ?? 0) == 0 })
    }

    @Test func threadBecomesPersistedDiaryAndSeasonWaitingYieldsTheReturnSlot() throws {
        let key = "PixelTimelineFlowTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let now = Date().timeIntervalSince1970
        let store = PiboCompanionStore(defaults: defaults, clock: { now })
        let timeline = PiboTimelineStore(defaults: defaults, key: "timeline")
        timeline.start(raw: "", now: now)
        let controller = HomeCompanionController(store: store, catalog: try #require(PiboCompanionCatalog.bundled()), clock: { now })
        controller.environment = .init(appActive: { true }, state: { .stable }, timeline: { timeline })
        controller.storyWaiting = true
        #expect(!controller.offer(.returnShort))
        controller.storyWaiting = false
        #expect(controller.offer(.patAfter))
        #expect(timeline.toldLog.count == 1)
        #expect(timeline.beatsToldIn("stones") == 1)
        #expect(!timeline.toldLog[0].lines.isEmpty)
        #expect(timeline.lastBeatDay == timeline.storyDay(now: now))
        controller.leaveHome()
    }
}

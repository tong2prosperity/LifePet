import Foundation
import Testing
@testable import Pibo
import PiboCore

@Suite(.serialized)
struct PiboTimelineStoreTests {
    @Test
    func testSeedFactsAndInitialRecording() {
        let suiteKey = "pibo_test_timeline_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteKey)!

        let facts = TimelineSeedFacts(
            relationshipStarted: true,
            boCollectedBefore: true,
            hammockUnlocked: false
        )
        let store = PiboTimelineStore(defaults: defaults, key: "state.v1")
        store.start(raw: "", facts: facts)

        #expect(store.storyDay() == 1)
        #expect(store.isBlocked(.pat))
        #expect(store.isBlocked(.boCollected))
        #expect(!store.isBlocked(.hammockNight))
        #expect(!store.isBlocked(.meal))
        #expect(!store.hasFirst(.pat))
        #expect(!store.hasFirst(.boCollected))

        defaults.removePersistentDomain(forName: suiteKey)
    }

    @Test
    func testRecordFirstIdempotencyAndBlock() {
        let suiteKey = "pibo_test_timeline_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteKey)!

        let store = PiboTimelineStore(defaults: defaults, key: "state.v1")
        store.start(raw: "")

        let now = 1000.0
        let recorded = store.recordFirst(.meal, at: now, day: 3)
        #expect(recorded)
        #expect(store.hasFirst(.meal))
        #expect(store.first(.meal)?.day == 3)

        // Second recording must be ignored (idempotent)
        let second = store.recordFirst(.meal, at: now + 50, day: 4)
        #expect(!second)
        #expect(store.first(.meal)?.day == 3)

        defaults.removePersistentDomain(forName: suiteKey)
    }

    @Test
    func testBeatToldTrackingAndCounts() {
        let suiteKey = "pibo_test_timeline_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteKey)!

        let store = PiboTimelineStore(defaults: defaults, key: "state.v1")
        store.start(raw: "")

        #expect(store.beatsToldIn("stones") == 0)
        #expect(store.beatsToldIn("beetle") == 0)

        store.markBeatTold("stones:1", storyDay: 1)
        store.markBeatTold("stones:2", storyDay: 2)
        store.markBeatTold("beetle:1", storyDay: 2)

        #expect(store.beatsToldIn("stones") == 2)
        #expect(store.beatsToldIn("beetle") == 1)

        let keys = store.toldLog.map(\.key)
        #expect(keys.count == 3)
        #expect(keys.contains("stones:1"))
        #expect(keys.contains("stones:2"))
        #expect(keys.contains("beetle:1"))

        defaults.removePersistentDomain(forName: suiteKey)
    }

    @Test
    func testPersistenceRoundTrip() {
        let suiteKey = "pibo_test_timeline_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteKey)!

        let store1 = PiboTimelineStore(defaults: defaults, key: "state.v1")
        store1.start(raw: "")
        _ = store1.recordFirst(.hammockNight, at: 500.0, day: 5)
        store1.markBeatTold("stones:1", storyDay: 1)

        let store2 = PiboTimelineStore(defaults: defaults, key: "state.v1")
        #expect(store2.hasFirst(.hammockNight))
        #expect(store2.first(.hammockNight)?.day == 5)
        #expect(store2.beatsToldIn("stones") == 1)

        defaults.removePersistentDomain(forName: suiteKey)
    }
}

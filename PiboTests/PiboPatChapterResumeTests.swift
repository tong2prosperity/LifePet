import Foundation
import PiboCore
import Testing
@testable import Pibo

/// An unfinished pat micro-chapter survives leaving Home and relaunching
/// inside the same state episode (HarmonyOS `test_pat_chapter_resume.mjs`,
/// docs/harmony-first/2026-09-28-拍一拍段落跨访问续讲.md).
@MainActor
@Suite(.serialized)
struct PiboPatChapterResumeTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func chapter(_ lines: [String]) -> PiboPatUnit {
        PiboPatUnit(
            state: "stable",
            context: "idle",
            action: .checkIn,
            speaker: .pibo,
            lines: lines.map { PiboPatLine(text: $0, stages: nil) }
        )
    }

    private static let catalog = PiboPatCatalog(units: [
        chapter(["第一句", "第二句", "第三句"]),
        chapter(["另一段"]),
    ])

    private static func input(episode: String = "stable:1") -> PiboPatConversationInput {
        PiboPatConversationInput(state: .stable, episodeKey: episode, storyStage: "unresponded")
    }

    /// Touch discovery would otherwise take the first stable pats.
    private static func store(
        _ defaults: UserDefaults,
        catalog: PiboPatCatalog = catalog,
        now: Date = start
    ) -> PiboPatConversationStore {
        let store = PiboPatConversationStore(catalog: catalog, defaults: defaults, now: now)
        store.debugSetTouchDiscoveryCompleted(3)
        return store
    }

    @Test func leavingHomeKeepsTheChapterAndMarksTheThread() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = Self.store(defaults)

        #expect(store.resolve(Self.input(), at: Self.start).text == "第一句")
        store.leaveHome()

        let resumed = store.resolve(Self.input(), at: Self.start.addingTimeInterval(600))
        #expect(resumed.text == "……第二句")
        let next = store.resolve(Self.input(), at: Self.start.addingTimeInterval(606))
        #expect(next.text == "第三句", "only the first line after returning carries the mark")
        #expect(next.interactionCompleted)
    }

    @Test func relaunchResumesTheSavedChapter() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        #expect(Self.store(defaults).resolve(Self.input(), at: Self.start).text == "第一句")

        let relaunched = Self.store(defaults, now: Self.start.addingTimeInterval(3600))
        let resumed = relaunched.resolve(Self.input(), at: Self.start.addingTimeInterval(3600))
        #expect(resumed.text == "……第二句")
    }

    @Test func aNewStateEpisodeDropsTheSavedChapter() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        #expect(Self.store(defaults).resolve(Self.input(), at: Self.start).text == "第一句")

        let relaunched = Self.store(defaults, now: Self.start.addingTimeInterval(60))
        let fresh = relaunched.resolve(
            Self.input(episode: "stable:2"),
            at: Self.start.addingTimeInterval(60)
        )
        #expect(fresh.text?.hasPrefix("……") == false)
        #expect(fresh.text == "第一句", "the record restarts; the cursor never advanced")
    }

    @Test func aRewrittenRecordIsNeverResumedMidway() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        #expect(Self.store(defaults).resolve(Self.input(), at: Self.start).text == "第一句")

        let rewritten = PiboPatCatalog(units: [
            Self.chapter(["改写后的第一句", "改写后的第二句"]),
            Self.chapter(["另一段"]),
        ])
        let relaunched = Self.store(defaults, catalog: rewritten, now: Self.start.addingTimeInterval(60))
        let restarted = relaunched.resolve(Self.input(), at: Self.start.addingTimeInterval(60))
        #expect(restarted.text == "改写后的第一句")
    }

    @Test func aChapterOlderThanThirtySixHoursRestarts() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        #expect(Self.store(defaults).resolve(Self.input(), at: Self.start).text == "第一句")

        let later = Self.start.addingTimeInterval(PiboPatConversationStore.activeResumeMaximumAge + 60)
        let relaunched = Self.store(defaults, now: later)
        #expect(relaunched.resolve(Self.input(), at: later).text == "第一句")
    }

    @Test func authoredEllipsisIsNotDoubled() {
        #expect(piboPatContinuationText("…还在想") == "…还在想")
        #expect(piboPatContinuationText("还在想") == "……还在想")
    }

    @Test func fingerprintFollowsTheAuthoredText() {
        #expect(piboPatUnitFingerprint(Self.chapter(["甲", "乙"]))
            != piboPatUnitFingerprint(Self.chapter(["甲", "丙"])))
        #expect(piboPatUnitFingerprint(Self.chapter(["甲", "乙"]))
            == piboPatUnitFingerprint(Self.chapter(["甲", "乙"])))
    }
}

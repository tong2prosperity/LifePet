import Foundation
import PiboCore
import Testing
@testable import Pibo

@MainActor
@Suite(.serialized)
struct PiboPatConversationStoreTests {
    @Test func microChapterAdvancesOnlyAfterCooldownAndThenCycles() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = PiboPatConversationStore(
            catalog: PiboPatCatalog(units: [
                PiboPatUnit(
                    state: "energetic",
                    context: "workout.run",
                    action: .play,
                    speaker: .pibo,
                    lines: [
                        PiboPatLine(text: "第一句", stages: nil),
                        PiboPatLine(text: "第二句", stages: nil),
                    ]
                ),
                PiboPatUnit(
                    state: "energetic",
                    context: "workout.run",
                    action: .play,
                    speaker: .pibo,
                    lines: [PiboPatLine(text: "下一段", stages: nil)]
                ),
            ]),
            defaults: defaults
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let input = PiboPatConversationInput(
            state: .energetic,
            episodeKey: "workout-1",
            storyStage: "unresponded",
            events: [PiboPatEventCandidate(event: .workoutRun, token: "run-1")]
        )

        let first = store.resolve(input, at: date)
        #expect(first.text == "第一句")
        #expect(first.hasNext)
        #expect(first.shouldExecuteAction)
        #expect(!store.resolve(input, at: date.addingTimeInterval(2.9)).accepted)

        let second = store.resolve(input, at: date.addingTimeInterval(3))
        #expect(second.text == "第二句")
        #expect(second.interactionCompleted)
        #expect(!second.shouldExecuteAction)

        let nextInput = PiboPatConversationInput(
            state: .energetic,
            episodeKey: "workout-1",
            storyStage: "unresponded",
            events: [PiboPatEventCandidate(event: .workoutRun, token: "run-2")]
        )
        let next = store.resolve(nextInput, at: date.addingTimeInterval(6))
        #expect(next.text == "下一段")
    }

    @Test func stateChangeClearsAnUnfinishedChapter() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = PiboPatConversationStore(
            catalog: PiboPatCatalog(units: [
                PiboPatUnit(
                    state: "stable",
                    context: "touchDiscovery",
                    action: .checkIn,
                    speaker: .pibo,
                    lines: [
                        PiboPatLine(text: "开始", stages: nil),
                        PiboPatLine(text: "继续", stages: nil),
                    ]
                ),
                PiboPatUnit(
                    state: "tired",
                    context: "awake",
                    action: .rest,
                    speaker: .pibo,
                    lines: [PiboPatLine(text: "困了", stages: nil)]
                ),
            ]),
            defaults: defaults
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let stable = PiboPatConversationInput(
            state: .stable,
            episodeKey: "stable-1",
            storyStage: "unresponded"
        )
        #expect(store.resolve(stable, at: date).text == "开始")

        let tired = PiboPatConversationInput(
            state: .tired,
            episodeKey: "tired-1",
            storyStage: "unresponded"
        )
        #expect(store.resolve(tired, at: date.addingTimeInterval(1)).text == "困了")
    }

    @Test func templateWithoutRequiredValueFallsBackToAmbientContext() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = PiboPatConversationStore(
            catalog: PiboPatCatalog(units: [
                PiboPatUnit(
                    state: "stable",
                    context: "steps",
                    action: .checkIn,
                    speaker: .pibo,
                    lines: [PiboPatLine(text: "{steps} 步", stages: nil)]
                ),
                PiboPatUnit(
                    state: "stable",
                    context: "idle",
                    action: .checkIn,
                    speaker: .pibo,
                    lines: [PiboPatLine(text: "怎么了？", stages: nil)]
                ),
            ]),
            defaults: defaults
        )
        let input = PiboPatConversationInput(
            state: .stable,
            episodeKey: "stable",
            storyStage: "unresponded",
            events: [PiboPatEventCandidate(event: .steps, token: "steps")]
        )

        #expect(store.resolve(input).text == "怎么了？")
    }
}

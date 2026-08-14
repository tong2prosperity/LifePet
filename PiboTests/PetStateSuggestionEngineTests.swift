import Foundation
import Testing
@testable import Pibo

@MainActor
struct PetStateSuggestionEngineTests {
    @Test func lowerMoodRulesWinAndTieOrderMatchesTheRuleTable() {
        let winners = PetStateSuggestionEngine.winners(
            raw: RawMetrics(),
            stats: Self.stats(vitality: 70, mood: 40),
            quitCounts: [:],
            lastInteractionAt: [:],
            now: Date(timeIntervalSince1970: 10_000),
            isWakingHour: { true }
        )

        #expect(winners.map(\.kind) == [.meditate, .breath])
        let steps = winners.map { $0.makeStep() }
        #expect(steps.map(\.kind) == [.meditate, .breath])
        #expect(steps.map(\.gain) == [15, 9])
        #expect(steps.map(\.affects) == [.mood, .mood])
        #expect(steps.allSatisfy { $0.status == .suggest && !$0.fromAutoSensor })
    }

    @Test func vitalityPayloadsPreserveWalkRoundingAndRunValues() throws {
        var raw = RawMetrics()
        raw.steps = 6_501
        let winners = PetStateSuggestionEngine.winners(
            raw: raw,
            stats: Self.stats(vitality: 50, mood: 90),
            quitCounts: [:],
            lastInteractionAt: [:],
            now: Date(timeIntervalSince1970: 10_000),
            isWakingHour: { true }
        )
        let steps = winners.map { $0.makeStep() }

        #expect(winners.map(\.kind) == [.walk, .run])
        try #require(steps.count == 2)
        let walk = try #require(steps.first)
        let run = try #require(steps.last)
        #expect(walk.titleValue == AppLocalization.format("%d 步", 1_500))
        #expect(walk.gain == 4)
        #expect(walk.affects == .vitality)
        #expect(run.titleValue == AppLocalization.format("%d 分钟", 20))
        #expect(run.gain == 20)
        #expect(run.affects == .vitality)
    }

    @Test func quitAndCooldownSuppressionShortCircuitRuleEvaluation() {
        var wakingChecks = 0
        let now = Date(timeIntervalSince1970: 10_000)
        let winners = PetStateSuggestionEngine.winners(
            raw: RawMetrics(),
            stats: Self.stats(vitality: 50, mood: 90),
            quitCounts: [.walk: 3],
            lastInteractionAt: [.run: now.addingTimeInterval(-60)],
            now: now,
            isWakingHour: {
                wakingChecks += 1
                return true
            }
        )

        #expect(winners.isEmpty)
        #expect(wakingChecks == 0)
    }

    @Test func wakingHourIsSampledSeparatelyForWalkAndRun() {
        var answers = [true, false]
        let winners = PetStateSuggestionEngine.winners(
            raw: RawMetrics(),
            stats: Self.stats(vitality: 50, mood: 90),
            quitCounts: [:],
            lastInteractionAt: [:],
            now: Date(timeIntervalSince1970: 10_000),
            isWakingHour: { answers.removeFirst() }
        )

        #expect(winners.map(\.kind) == [.walk])
        #expect(answers.isEmpty)
    }

    private static func stats(vitality: Int, mood: Int) -> [Stat] {
        [
            Stat(kind: .vitality, value: vitality),
            Stat(kind: .energy, value: 50),
            Stat(kind: .mood, value: mood)
        ]
    }
}

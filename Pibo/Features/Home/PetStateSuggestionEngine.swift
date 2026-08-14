import Foundation

/// A lazily materialized suggestion. `PetStateStore` asks for the step only
/// after confirming that kind is not already visible, preserving existing IDs
/// and avoiding unused UUID creation.
struct PetStateSuggestionCandidate {
    let kind: StepKind
    private let raw: RawMetrics

    fileprivate init(kind: StepKind, raw: RawMetrics) {
        self.kind = kind
        self.raw = raw
    }

    func makeStep() -> StepItem {
        switch kind {
        case .walk:
            // Stretch goal toward 8k, capped 500…2000, rounded up to 500.
            let needed = max(500, min(2000, 8000 - raw.steps))
            let deficit = ((needed + 499) / 500) * 500
            let gain = max(2, deficit / 1000 * 4)
            return StepItem(
                status: .suggest,
                kind: .walk,
                actionLabel: AppLocalization.text("再走"),
                titleValue: AppLocalization.format("%d 步", deficit),
                affects: .vitality,
                gain: gain,
                time: "",
                fromAutoSensor: false
            )
        case .run:
            return StepItem(
                status: .suggest,
                kind: .run,
                actionLabel: AppLocalization.text("去跑"),
                titleValue: AppLocalization.format("%d 分钟", 20),
                affects: .vitality,
                gain: 20,
                time: "",
                fromAutoSensor: false
            )
        case .meditate:
            return StepItem(
                status: .suggest,
                kind: .meditate,
                actionLabel: AppLocalization.text("冥想"),
                titleValue: AppLocalization.format("%d 分钟", 5),
                affects: .mood,
                gain: 15,
                time: "",
                fromAutoSensor: false
            )
        case .breath:
            return StepItem(
                status: .suggest,
                kind: .breath,
                actionLabel: AppLocalization.text("深呼吸"),
                titleValue: AppLocalization.format("%d 次", 3),
                affects: .mood,
                gain: 9,
                time: "",
                fromAutoSensor: false
            )
        case .sleep:
            preconditionFailure("Sleep is sensor-driven, never suggested")
        }
    }
}

/// Selects the suggestion kinds Home should surface. Array mutation remains in
/// `PetStateStore` so Observation notifications and existing card identity keep
/// their established behavior.
enum PetStateSuggestionEngine {
    private struct Rule {
        let kind: StepKind
        let affects: StatKind
    }

    private static let rules = [
        Rule(kind: .walk, affects: .vitality),
        Rule(kind: .run, affects: .vitality),
        Rule(kind: .meditate, affects: .mood),
        Rule(kind: .breath, affects: .mood)
    ]

    static func winners(
        raw: RawMetrics,
        stats: [Stat],
        quitCounts: [StepKind: Int],
        lastInteractionAt: [StepKind: Date],
        now: Date,
        isWakingHour: () -> Bool
    ) -> [PetStateSuggestionCandidate] {
        let cooldown: TimeInterval = 2 * 60 * 60
        let eligible = rules.filter { rule in
            if (quitCounts[rule.kind] ?? 0) >= 3 { return false }
            if let last = lastInteractionAt[rule.kind],
               now.timeIntervalSince(last) < cooldown { return false }
            return isEligible(
                rule.kind,
                raw: raw,
                stats: stats,
                isWakingHour: isWakingHour
            )
        }
        let prioritized = eligible.sorted { lhs, rhs in
            statValue(lhs.affects, in: stats) < statValue(rhs.affects, in: stats)
        }
        return prioritized.prefix(2).map {
            PetStateSuggestionCandidate(kind: $0.kind, raw: raw)
        }
    }

    private static func isEligible(
        _ kind: StepKind,
        raw: RawMetrics,
        stats: [Stat],
        isWakingHour: () -> Bool
    ) -> Bool {
        switch kind {
        case .walk:
            return raw.steps < 8000
                && statValue(.vitality, in: stats) < 85
                && isWakingHour()
        case .run:
            return raw.exerciseMinutes < 20
                && statValue(.vitality, in: stats) < 75
                && isWakingHour()
        case .meditate:
            return raw.mindfulMinutes < 5
                && statValue(.mood, in: stats) < 85
        case .breath:
            return statValue(.mood, in: stats) < 65
        case .sleep:
            return false
        }
    }

    private static func statValue(_ kind: StatKind, in stats: [Stat]) -> Int {
        stats.first(where: { $0.kind == kind })?.value ?? 50
    }
}

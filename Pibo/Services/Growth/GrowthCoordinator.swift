import Foundation
import os
import Observation
import PiboCore

/// Everything one refresh reads from the platform: the ledger owns the totals,
/// history owns the days, and the caller passes the live health values it has
/// already gated (nil = not shared, never a fake zero).
struct GrowthRefreshContext {
    var ledger: BoLedgerStore
    var history: HealthHistoryStore
    var relationshipDays: Int
    var cameraEnabled: Bool
    var companionEnabled: Bool
    var entering: Bool
    var now: Date
    var steps: Double?
    var activeMinutes: Double?
    /// Live sleep hours when today's history row is not written yet.
    var fallbackSleepHours: Double?
    var lastWorkoutEndedAt: Date?
}

struct GrowthBaselines {
    var steps: Double?
    var activeMinutes: Double?
    var sleepHours: Double?
}

/// Today's health energy attributed to each source, through Core's score and split.
@MainActor
func growthTodaySplit(_ record: HealthDayRecord?) -> GrowthSourceSplit {
    guard let record,
          record.sleepTotal > 0 || record.steps > 0 || record.exerciseMinutes > 0 else {
        return .empty
    }
    let breakdown = PiboCoreBoEconomy.scoreDay(PiboCoreBoAdapter.metrics(for: record))
    let split = PiboCoreGrowth.energySplit(
        sleepScore: breakdown.sleepScore,
        stepsScore: breakdown.stepsScore,
        mvpaScore: breakdown.mvpaScore,
        energy: breakdown.energy
    )
    return GrowthSourceSplit(sleep: split.sleep, steps: split.steps, activity: split.activity)
}

/// The person's own typical values over recent whole days, through Core's median rule.
@MainActor
func growthBaselines(_ history: HealthHistoryStore, now: Date, calendar: Calendar = .current) -> GrowthBaselines {
    let today = calendar.startOfDay(for: now)
    let start = calendar.date(byAdding: .day, value: -14, to: today) ?? today
    let end = calendar.date(byAdding: .day, value: -1, to: today) ?? today
    let records = history.verifiedHealthRecords(from: start, to: end)
    return GrowthBaselines(
        steps: PiboCoreGrowth.personalBaseline(records.filter { $0.steps > 0 }.map { Double($0.steps) }),
        activeMinutes: PiboCoreGrowth.personalBaseline(
            records.filter { $0.exerciseMinutes > 0 }.map { Double($0.exerciseMinutes) }
        ),
        sleepHours: PiboCoreGrowth.personalBaseline(
            records.filter { $0.sleepTotal > 0 }.map { $0.sleepTotal / 3600 }
        )
    )
}

/// Glue between health, the ledger and growth (decision 057). It reads platform
/// stores, asks Core every question and turns answers into queued moments.
/// Ported from HarmonyOS `entry/src/main/ets/services/growth/GrowthCoordinator.ets`.
@MainActor
@Observable
final class GrowthCoordinator {
    /// Nil means "nothing known yet" — Core's struct has no public empty
    /// initialiser, and unknown must never read as a low band.
    private(set) var cues: PiboCoreGrowthBodyCues?
    /// -1 when step data is not shared.
    private(set) var steps: Double = -1
    /// Today is one of Core's relationship anniversaries; the forest shows a cake.
    private(set) var anniversaryToday = false
    /// The latest interaction award, for the stage's "+n" pop.
    private(set) var lastAwardXP = 0
    private(set) var lastAwardAt: Date?
    private(set) var revision = 0

    @ObservationIgnored private var growth: GrowthStore?
    @ObservationIgnored private var wishes: WishStore?
    @ObservationIgnored private var lastFacts: WishFacts?

    func bind(growth: GrowthStore, wishes: WishStore) {
        self.growth = growth
        self.wishes = wishes
    }

    func refresh(_ context: GrowthRefreshContext) {
        guard let growth, let wishes else { return }
        let now = context.now
        let today = context.history.record(on: now)

        growth.sync(
            GrowthSyncInput(
                lifetimeMinted: context.ledger.lifetimeMinted,
                energyPool: context.ledger.state.energyPool,
                energyPerBo: PiboCoreBoEconomy.energyPerBo,
                relationshipDays: context.relationshipDays,
                todaySplit: growthTodaySplit(today),
                now: now,
                entering: context.entering
            )
        )

        let baselines = growthBaselines(context.history, now: now)
        let steps = context.steps
        let activeMinutes = context.activeMinutes
        let sleepHours: Double?
        if let today, today.sleepTotal > 0 {
            sleepHours = today.sleepTotal / 3600
        } else if let fallback = context.fallbackSleepHours, fallback > 0 {
            sleepHours = fallback
        } else {
            sleepHours = nil
        }
        let secondsSinceWorkout = context.lastWorkoutEndedAt.map { max(0, now.timeIntervalSince($0)) }

        cues = PiboCoreGrowth.bodyCues(
            sleepHours: sleepHours,
            baselineSleepHours: baselines.sleepHours,
            steps: steps,
            baselineSteps: baselines.steps,
            activeMinutes: activeMinutes,
            secondsSinceWorkout: secondsSinceWorkout
        )
        self.steps = steps ?? -1

        let facts = WishFacts(
            now: now,
            localHour: Calendar.current.component(.hour, from: now),
            baselineSteps: baselines.steps,
            baselineActiveMinutes: baselines.activeMinutes,
            baselineSleepMinutes: baselines.sleepHours.map { $0 * 60 },
            cameraEnabled: context.cameraEnabled,
            companionEnabled: context.companionEnabled,
            steps: steps,
            activeMinutes: activeMinutes,
            lastNightSleepMinutes: sleepHours.map { $0 * 60 },
            pats: growth.countToday(.pat, now: now),
            meals: growth.countToday(.meal, now: now),
            answers: growth.countToday(.companionAnswer, now: now)
        )
        lastFacts = facts
        for slot in wishes.update(facts) {
            rewardWish(slot.kind)
        }

        if context.entering, let cues, cues.sleepBand >= 0, growth.claimMorning(now: now) {
            growth.push(GrowthFeedbackEvent(kind: .morningSleep, band: cues.sleepBand))
        }
        let day = context.relationshipDays
        anniversaryToday = PiboCoreGrowth.anniversary(relationshipDay: day) != nil
        if anniversaryToday, growth.claimAnniversary(relationshipDay: day) {
            growth.push(GrowthFeedbackEvent(kind: .anniversary, day: day))
        }
        revision += 1
    }

    // MARK: - Interaction awards

    /// Each returns Core's answer so the stage can show "+n".
    func onPat() -> PiboCoreGrowthAward? {
        interaction(.pat)
    }

    func onMealRecognized() -> PiboCoreGrowthAward? {
        interaction(.meal)
    }

    func onCompanionAnswer() -> PiboCoreGrowthAward? {
        interaction(.companionAnswer)
    }

    func onShootingStar() -> PiboCoreGrowthAward? {
        guard let growth else { return nil }
        // The moment is queued before the award so it plays ahead of any level-up it causes.
        let event = GrowthFeedbackEvent(kind: .star)
        growth.push(event)
        let award = growth.award(.shootingStar)
        event.xp = award.xp
        return award
    }

    // MARK: - Private

    /// Awards one interaction and re-judges the care wishes right away, so a
    /// third pat stamps its wish without waiting for the next health refresh.
    private func interaction(_ source: PiboCoreGrowthSource, now: Date = .now) -> PiboCoreGrowthAward? {
        guard let growth, let wishes else { return nil }
        let award = growth.award(source, now: now)
        if award.xp > 0 {
            lastAwardXP = award.xp
            lastAwardAt = now
        }
        // Health facts from another day must never fill today's wishes.
        if var facts = lastFacts, growthDayKey(facts.now) == growthDayKey(now) {
            facts.localHour = Calendar.current.component(.hour, from: now)
            facts.pats = growth.countToday(.pat, now: now)
            facts.meals = growth.countToday(.meal, now: now)
            facts.answers = growth.countToday(.companionAnswer, now: now)
            lastFacts = facts
            for slot in wishes.update(facts) {
                rewardWish(slot.kind)
            }
        }
        revision += 1
        return award
    }

    private func rewardWish(_ kind: PiboCoreWishKind) {
        guard let growth else { return }
        let event = GrowthFeedbackEvent(kind: .wish, wish: Int(kind.rawValue))
        growth.push(event)
        event.xp = growth.award(.wish).xp
        // Analytics: `Analytics.Event` has no `wishCompleted` case yet; the caller
        // adds it and tracks `wishAnalyticsKey(kind)` there. This layer must not
        // invent an event name.
    }

    /// Stable analytics key per wish kind (decision 057 dashboard vocabulary).
    static func wishAnalyticsKey(_ kind: PiboCoreWishKind) -> String {
        switch kind {
        case .steps: return "steps"
        case .activeMinutes: return "active"
        case .pats: return "pats"
        case .mealPhoto: return "meal"
        case .answerPrompt: return "answer"
        case .sleepEnough: return "sleep"
        default: return "none"
        }
    }
}

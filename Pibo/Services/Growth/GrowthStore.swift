import Foundation
import os
import Observation
import PiboCore

/// Health facts for one sync, already reduced to ledger totals and Core's
/// per-source split; the store never reads raw health numbers.
struct GrowthSyncInput {
    var lifetimeMinted: Int
    var energyPool: Double
    var energyPerBo: Double
    var relationshipDays: Int
    var todaySplit: GrowthSourceSplit
    var now: Date
    /// True for the first sync after the person comes back to Home.
    var entering: Bool
}

/// Level, familiarity and the feedback queue (decision 057).
///
/// Health experience is derived from the bo ledger on every sync, so it follows
/// ledger restores and sync; only interaction experience, daily counters and
/// "already seen" marks persist. Ported from HarmonyOS
/// `entry/src/main/ets/services/growth/GrowthStore.ets`.
///
/// Persistence mapping: HarmonyOS keeps `preferences` store `pibo_growth` with
/// key `snapshot.v1`. iOS uses one `UserDefaults` key, `pibo_growth/snapshot.v1`
/// (store name and key joined by `/`), holding the same JSON snapshot, so
/// `reset()` clears exactly the same logical record.
@MainActor
@Observable
final class GrowthStore: GrowthCopyCursorStore {
    nonisolated static let defaultsKey = "pibo_growth/snapshot.v1"

    private(set) var level = 1
    private(set) var xpIntoLevel = 0
    private(set) var xpForNext = 0
    private(set) var totalXP = 0
    private(set) var healthXP = 0
    private(set) var hearts = 0
    private(set) var tone: PiboCoreGrowthTone = .gentle
    /// Nil only before the first `recompute()`; Core's struct has no public
    /// empty initialiser, so the unknown value is nil rather than a zeroed copy.
    private(set) var appearance: PiboCoreGrowthAppearance?
    private(set) var todaySplit = GrowthSourceSplit.empty
    private(set) var pendingCount = 0
    private(set) var revision = 0

    @ObservationIgnored private var relationshipDays = 1
    @ObservationIgnored private var snapshot = GrowthSnapshot()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistenceKey: String
    @ObservationIgnored private var sequence = 0

    init(defaults: UserDefaults = .standard, persistenceKey: String = GrowthStore.defaultsKey) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        restore(raw: defaults.string(forKey: persistenceKey) ?? "")
    }

    func restore(raw: String) {
        snapshot = GrowthSnapshot.decode(raw)
        recompute()
        publish()
    }

    /// Folds the latest ledger totals in and queues what changed since the
    /// person last looked. The very first sync only records a baseline, so an
    /// existing ledger never replays as a backlog of level-ups.
    func sync(_ input: GrowthSyncInput) {
        rollDay(input.now)
        relationshipDays = max(1, input.relationshipDays)
        healthXP = PiboCoreGrowth.healthXP(
            lifetimeMinted: input.lifetimeMinted,
            energyPool: input.energyPool,
            energyPerBo: input.energyPerBo
        )
        todaySplit = input.todaySplit
        recompute()

        let today = growthDayKey(input.now)
        if snapshot.seenLevel < 0 || snapshot.seenHealthXP < 0 {
            snapshot.seenLevel = level
            snapshot.seenHearts = hearts
            snapshot.seenHealthXP = healthXP
        } else {
            let gained = healthXP - snapshot.seenHealthXP
            let delta: GrowthSourceSplit
            if snapshot.seenSplitDay == today {
                delta = GrowthSourceSplit(
                    sleep: max(0, input.todaySplit.sleep - snapshot.seenSplit.sleep),
                    steps: max(0, input.todaySplit.steps - snapshot.seenSplit.steps),
                    activity: max(0, input.todaySplit.activity - snapshot.seenSplit.activity)
                )
            } else {
                delta = input.todaySplit
            }
            if gained > 0 {
                let dominant = PiboCoreGrowth.awayDominant(
                    sleepEnergy: delta.sleep,
                    stepsEnergy: delta.steps,
                    activityEnergy: delta.activity
                )
                push(
                    GrowthFeedbackEvent(
                        kind: input.entering && dominant != nil ? .away : .pop,
                        sleep: Int(delta.sleep.rounded()),
                        steps: Int(delta.steps.rounded()),
                        activity: Int(delta.activity.rounded()),
                        dominant: dominant,
                        xp: gained
                    )
                )
            }
            snapshot.seenHealthXP = healthXP
            queueMilestones()
        }
        snapshot.seenSplitDay = today
        snapshot.seenSplit = input.todaySplit
        persist()
        publish()
    }

    /// Counts one interaction and returns Core's award for it (zero past the
    /// daily cap). The counter still advances so caps hold across restarts.
    @discardableResult
    func award(_ source: PiboCoreGrowthSource, now: Date = .now) -> PiboCoreGrowthAward {
        rollDay(now)
        let index = Int(source.rawValue)
        let award = PiboCoreGrowth.award(source, countedToday: snapshot.counter(at: index))
        if snapshot.counters.indices.contains(index) {
            snapshot.counters[index] += 1
        }
        snapshot.eventXP += max(0, award.xp)
        snapshot.eventFamiliarity += max(0, award.familiarity)
        let today = growthDayKey(now)
        if award.justCapped, source == .pat, snapshot.patCapToldDay != today {
            snapshot.patCapToldDay = today
            push(GrowthFeedbackEvent(kind: .patCap))
        }
        recompute()
        if snapshot.seenLevel >= 0 { queueMilestones() }
        persist()
        publish()
        return award
    }

    func countToday(_ source: PiboCoreGrowthSource, now: Date = .now) -> Int {
        rollDay(now)
        return snapshot.counter(at: Int(source.rawValue))
    }

    func push(_ event: GrowthFeedbackEvent) {
        sequence += 1
        event.id = "\(Int(Date().timeIntervalSince1970 * 1000)):\(event.kind.rawValue):\(sequence)"
        // Source pops merge so a quick refresh burst becomes one sparkle.
        if event.kind == .pop, let last = snapshot.pending.last, last.kind == .pop {
            last.sleep = (last.sleep ?? 0) + (event.sleep ?? 0)
            last.steps = (last.steps ?? 0) + (event.steps ?? 0)
            last.activity = (last.activity ?? 0) + (event.activity ?? 0)
            last.xp = (last.xp ?? 0) + (event.xp ?? 0)
        } else {
            snapshot.pending.append(event)
        }
        if snapshot.pending.count > GrowthValues.pendingLimit {
            // Drop the oldest disposable pop first; milestones survive.
            let pop = snapshot.pending.firstIndex { $0.kind == .pop } ?? 0
            snapshot.pending.remove(at: pop)
        }
        persist()
        publish()
    }

    func peek() -> GrowthFeedbackEvent? {
        snapshot.pending.first
    }

    func consume(id: String) {
        guard let index = snapshot.pending.firstIndex(where: { $0.id == id }) else { return }
        snapshot.pending.remove(at: index)
        persist()
        publish()
    }

    // MARK: - Copy cursors

    func copyCursor(key: String) -> Int {
        snapshot.copyCursors.first { $0.key == key }?.cursor ?? 0
    }

    func setCopyCursor(key: String, cursor: Int) {
        let value = max(0, Int(cursor))
        if let index = snapshot.copyCursors.firstIndex(where: { $0.key == key }) {
            snapshot.copyCursors[index].cursor = value
        } else {
            snapshot.copyCursors.append(GrowthCopyCursor(key: key, cursor: value))
        }
        persist()
    }

    // MARK: - Once-a-day and surprise bookkeeping

    var lastStarAt: Int { snapshot.lastStarAt }

    func markStarShown(nowSeconds: Double) {
        snapshot.lastStarAt = max(0, Int(nowSeconds.rounded(.down)))
        persist()
    }

    func claimMorning(now: Date) -> Bool {
        let today = growthDayKey(now)
        if snapshot.morningToldDay == today { return false }
        snapshot.morningToldDay = today
        persist()
        return true
    }

    func claimAnniversary(relationshipDay: Int) -> Bool {
        if snapshot.anniversaryToldDay == relationshipDay { return false }
        snapshot.anniversaryToldDay = relationshipDay
        persist()
        return true
    }

    func claimWorkout(endedAt: Double) -> Bool {
        if endedAt <= Double(snapshot.workoutToldAt) { return false }
        snapshot.workoutToldAt = max(0, Int(endedAt.rounded(.down)))
        persist()
        return true
    }

    func reset() {
        snapshot = GrowthSnapshot()
        healthXP = 0
        todaySplit = .empty
        relationshipDays = 1
        recompute()
        persist()
        publish()
    }

    /// Fraction of the current level, for the HUD bar.
    func levelProgress() -> Double {
        xpForNext > 0 ? min(1, Double(xpIntoLevel) / Double(xpForNext)) : 1
    }

    // MARK: - Private

    private func queueMilestones() {
        if level > snapshot.seenLevel {
            for next in (snapshot.seenLevel + 1)...level {
                push(GrowthFeedbackEvent(kind: .level, level: next))
            }
            snapshot.seenLevel = level
            GrowthLog.growth.info("level up to \(self.level, privacy: .public)")
        }
        if hearts > snapshot.seenHearts {
            let unlocked = snapshot.seenHearts >= 0
                && PiboCoreGrowth.highestTone(hearts: hearts).rawValue
                    > PiboCoreGrowth.highestTone(hearts: snapshot.seenHearts).rawValue
            push(GrowthFeedbackEvent(kind: .heart, hearts: hearts, toneUnlocked: unlocked))
            snapshot.seenHearts = hearts
        }
    }

    private func recompute() {
        totalXP = healthXP + snapshot.eventXP
        let levelAnswer = PiboCoreGrowth.level(totalXP: totalXP)
        level = levelAnswer.level
        xpIntoLevel = levelAnswer.xpIntoLevel
        xpForNext = levelAnswer.xpForNext
        appearance = PiboCoreGrowth.appearance(level: level)
        hearts = PiboCoreGrowth.hearts(
            familiarityPoints: PiboCoreGrowth.familiarityPoints(
                relationshipDays: relationshipDays,
                eventPoints: snapshot.eventFamiliarity
            )
        )
        tone = PiboCoreGrowth.highestTone(hearts: hearts)
    }

    private func rollDay(_ now: Date) {
        let today = growthDayKey(now)
        if snapshot.counterDay == today { return }
        snapshot.counterDay = today
        snapshot.counters = [Int](repeating: 0, count: GrowthValues.sourceCount)
    }

    private func publish() {
        pendingCount = snapshot.pending.count
        revision += 1
    }

    private func persist() {
        guard let raw = snapshot.jsonString else {
            GrowthLog.growth.error("growth snapshot encode failed; keeping previous value")
            return
        }
        defaults.set(raw, forKey: persistenceKey)
    }
}

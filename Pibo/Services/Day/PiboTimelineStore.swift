import Foundation
import Observation
import PiboCore

// Pibo's timeline memory (决定 056): which beats of its own threads it has told,
// the shared firsts it can verify, and when each remark was last said. Local
// only: never uploaded, tracked, synced or shown on the service widget. Which
// unit is due is decided by pibo-core (`PiboCoreTimeline`).
//
// Ported from HarmonyPibo `services/PiboTimelineStore.ets`.

struct TimelineFirstRecord: Codable, Equatable, Sendable {
    var kind: Int
    /// When it happened (seconds since 1970).
    var at: Double
    /// Relationship day (1-based) on which it happened.
    var day: Int
}

/// One beat as it was told, for the footprints diary (决定 063). Beats told before this
/// record existed stay in `toldBeats` only: their day is unknown and never guessed.
struct TimelineToldBeat: Codable, Equatable, Sendable {
    var key: String
    var at: Double
    var lines: [String]
}

struct TimelineRemarkUsage: Codable, Equatable, Sendable {
    var id: String
    var lastAt: Double
}

/// What the app already knows the first time the timeline starts. A relationship
/// that predates the timeline never gets a first recorded that may already have
/// happened without a record (决定 056: no guessing).
struct TimelineSeedFacts {
    var relationshipStarted: Bool = false
    var boCollectedBefore: Bool = false
    var hammockUnlocked: Bool = false
}

/// The earliest saved meal of this relationship, if any.
struct TimelineMealFact {
    var at: Double
    var day: Int
    /// The saved record was confirmed as food.
    var verified: Bool
}

private struct TimelineSnapshot: Codable {
    /// Local midnight of story day 1 (seconds since 1970).
    var startedAt: Double
    var toldBeats: [String]
    /// Story day of the last beat told; 0 when none.
    var lastBeatDay: Int
    var firsts: [TimelineFirstRecord]
    /// Append-only, one per beat; absent in snapshots saved before 决定 063.
    var toldLog: [TimelineToldBeat]?
    /// Firsts that will never be recorded for this relationship.
    var blockedMask: UInt32
    var recalledMask: UInt32
    /// Relationship day of the last recall; 0 when none.
    var lastRecallDay: Int
    var remarkUsage: [TimelineRemarkUsage]
}

func timelineBeatKey(_ threadKey: String, _ beat: Int) -> String {
    "\(threadKey):\(beat)"
}

private func localMidnight(_ now: Double) -> Double {
    let date = Date(timeIntervalSince1970: now)
    return Calendar.current.startOfDay(for: date).timeIntervalSince1970
}

private func emptySnapshot(_ now: Double) -> TimelineSnapshot {
    TimelineSnapshot(
        startedAt: localMidnight(now),
        toldBeats: [],
        lastBeatDay: 0,
        firsts: [],
        toldLog: [],
        blockedMask: 0,
        recalledMask: 0,
        lastRecallDay: 0,
        remarkUsage: []
    )
}

/// Firsts a relationship that predates the timeline may already have had.
private func predatingBlockedMask(_ facts: TimelineSeedFacts) -> UInt32 {
    guard facts.relationshipStarted else { return 0 }
    var mask: UInt32 = PiboCoreTimelineFirst.pat.mask
    if facts.boCollectedBefore { mask |= PiboCoreTimelineFirst.boCollected.mask }
    if facts.hammockUnlocked { mask |= PiboCoreTimelineFirst.hammockNight.mask }
    return mask
}

@MainActor
@Observable
final class PiboTimelineStore {
    static let defaultsKey = "pibo_timeline/state.v1"

    /// Bumped on every mutation so observing controllers can refresh.
    private(set) var revision: Int = 0
    #if DEBUG
    var debugDayOffset: Int = 0
    #endif

    private let defaults: UserDefaults
    private let key: String
    private var snapshot: TimelineSnapshot

    init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
        self.snapshot = emptySnapshot(Date().timeIntervalSince1970)
        load()
    }

    /// Restores a snapshot, or starts the story today.
    func start(raw: String, facts: TimelineSeedFacts = TimelineSeedFacts(), now: Double = Date().timeIntervalSince1970) {
        if let data = raw.data(using: .utf8),
           let restored = try? JSONDecoder().decode(TimelineSnapshot.self, from: data),
           restored.startedAt > 0 {
            var valid = restored
            valid.startedAt = localMidnight(restored.startedAt)
            self.snapshot = valid
            touch()
            return
        }
        // Existing relationships start their threads today, at beat one (决定 056).
        self.snapshot = emptySnapshot(now)
        self.snapshot.blockedMask = predatingBlockedMask(facts)
        persist()
    }

    /// Settings 「重新开始」: a new relationship with nothing to block.
    func reset(now: Double = Date().timeIntervalSince1970) {
        self.snapshot = emptySnapshot(now)
        #if DEBUG
        self.debugDayOffset = 0
        #endif
        persist()
    }

    /// The first meal comes from saved records: the earliest one of this
    /// relationship, only when it was confirmed as food.
    func seedMeal(_ meal: TimelineMealFact?) {
        guard let meal,
              !hasFirst(.meal),
              !isBlocked(.meal) else { return }
        if !meal.verified {
            snapshot.blockedMask |= PiboCoreTimelineFirst.meal.mask
            persist()
            return
        }
        _ = recordFirst(.meal, at: meal.at, day: meal.day)
    }

    /// Story day (1-based) of `now`; the day the threads began is day 1.
    func storyDay(now: Double = Date().timeIntervalSince1970) -> Int {
        let baseDay = footprintsDayNumber(Date(timeIntervalSince1970: now),
                                          meetingDay: Date(timeIntervalSince1970: snapshot.startedAt))
        #if DEBUG
        return max(1, baseDay + debugDayOffset)
        #else
        return max(1, baseDay)
        #endif
    }

    var lastBeatDay: Int { snapshot.lastBeatDay }

    var recordedMask: UInt32 {
        snapshot.firsts.reduce(0) { mask, first in
            guard let kind = PiboCoreTimelineFirst(rawValue: Int32(first.kind)) else { return mask }
            return mask | kind.mask
        }
    }

    var recalledMask: UInt32 { snapshot.recalledMask }
    var lastRecallDay: Int { snapshot.lastRecallDay }

    func beatTold(_ key: String) -> Bool {
        snapshot.toldBeats.contains(key)
    }

    /// How many beats of one thread Pibo has told, for traces in the forest (决定 057).
    func beatsToldIn(_ threadKey: String) -> Int {
        let prefix = "\(threadKey):"
        return snapshot.toldBeats.filter { $0.hasPrefix(prefix) }.count
    }

    /// Shared firsts and told beats, as recorded, for the footprints diary.
    var firsts: [TimelineFirstRecord] { snapshot.firsts }
    var toldLog: [TimelineToldBeat] { snapshot.toldLog ?? [] }

    func markBeatTold(_ key: String, storyDay: Int, at: Double = Date().timeIntervalSince1970,
                      lines: [String] = []) {
        if !snapshot.toldBeats.contains(key) {
            snapshot.toldBeats.append(key)
            var log = snapshot.toldLog ?? []
            log.append(TimelineToldBeat(key: key, at: at, lines: lines))
            snapshot.toldLog = log
        }
        snapshot.lastBeatDay = storyDay
        persist()
    }

    func first(_ kind: PiboCoreTimelineFirst) -> TimelineFirstRecord? {
        snapshot.firsts.first { $0.kind == Int(kind.rawValue) }
    }

    func hasFirst(_ kind: PiboCoreTimelineFirst) -> Bool {
        first(kind) != nil
    }

    func isBlocked(_ kind: PiboCoreTimelineFirst) -> Bool {
        (snapshot.blockedMask & kind.mask) != 0
    }

    /// Records a shared first once. Returns true only when it was newly recorded.
    @discardableResult
    func recordFirst(_ kind: PiboCoreTimelineFirst, at: Double, day: Int) -> Bool {
        guard at.isFinite, !hasFirst(kind), !isBlocked(kind) else { return false }
        snapshot.firsts.append(TimelineFirstRecord(kind: Int(kind.rawValue), at: at, day: max(1, day)))
        persist()
        return true
    }

    func markRecalled(_ kind: PiboCoreTimelineFirst, relationshipDay: Int) {
        snapshot.recalledMask |= kind.mask
        snapshot.lastRecallDay = relationshipDay
        persist()
    }

    func remarkLastAt(_ id: String) -> Double {
        snapshot.remarkUsage.first { $0.id == id }?.lastAt ?? 0
    }

    func markRemarkUsed(_ id: String, now: Double) {
        if let index = snapshot.remarkUsage.firstIndex(where: { $0.id == id }) {
            snapshot.remarkUsage[index].lastAt = now
        } else {
            snapshot.remarkUsage.append(TimelineRemarkUsage(id: id, lastAt: now))
        }
        persist()
    }

    private func touch() {
        revision += 1
    }

    private func load() {
        if let raw = defaults.string(forKey: key),
           let data = raw.data(using: .utf8),
           let restored = try? JSONDecoder().decode(TimelineSnapshot.self, from: data),
           restored.startedAt > 0 {
            var valid = restored
            valid.startedAt = localMidnight(restored.startedAt)
            self.snapshot = valid
            touch()
        }
    }

    private func persist() {
        touch()
        if let data = try? JSONEncoder().encode(snapshot),
           let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: key)
        }
    }
}

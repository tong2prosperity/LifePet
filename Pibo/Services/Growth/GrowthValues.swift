import Foundation
import os

/// Persisted shapes for decision 057's visible growth. Everything here is
/// bookkeeping — counters, what the person has already seen, copy cursors.
/// Curves, caps, thresholds and unlocks are answered by `pibo-core`.
///
/// Ported from HarmonyOS `entry/src/main/ets/services/growth/GrowthValues.ets`.
enum GrowthValues {
    static let snapshotVersion = 1
    /// `PiboCoreGrowthSource` cases: wish, pat, meal, companionAnswer, shootingStar.
    static let sourceCount = 5
    /// Oldest disposable pops are dropped past this; milestones survive.
    static let pendingLimit = 12
}

/// Log table for the growth layer. `LPLog` owns the app-wide table but lives in
/// `Shared/`, outside this port's write scope: move this entry into `LPLog`
/// (category "Growth") and delete this enum once that change is allowed.
nonisolated enum GrowthLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "fun.tiebao.co.Pibo"
    static let growth = Logger(subsystem: subsystem, category: "Growth")
}

/// One day's health energy attributed to sleep, steps and activity, as Core's
/// split answers it.
struct GrowthSourceSplit: Equatable {
    var sleep: Double = 0
    var steps: Double = 0
    var activity: Double = 0

    static let empty = GrowthSourceSplit()
}

struct GrowthCopyCursor: Equatable {
    var key: String
    var cursor: Int
}

/// Serial queue kinds (decision 057). Only semantic values travel here; the
/// line is resolved at presentation time so tone is always current.
enum GrowthFeedbackKind: String, CaseIterable {
    case away
    case pop
    case level
    case heart
    case wish
    case patCap
    case decor
    case star
    case anniversary
    case workout
    case morningSleep
}

/// Reference type on purpose: the coordinator pushes a moment and fills `xp`
/// after the award lands, exactly like the ArkTS interface object.
final class GrowthFeedbackEvent {
    let kind: GrowthFeedbackKind
    var id: String
    var level: Int?
    var hearts: Int?
    var toneUnlocked: Bool?
    var sleep: Int?
    var steps: Int?
    var activity: Int?
    var dominant: Int?
    var wish: Int?
    var decor: Int?
    var xp: Int?
    var day: Int?
    var band: Int?

    init(
        kind: GrowthFeedbackKind,
        id: String = "",
        level: Int? = nil,
        hearts: Int? = nil,
        toneUnlocked: Bool? = nil,
        sleep: Int? = nil,
        steps: Int? = nil,
        activity: Int? = nil,
        dominant: Int? = nil,
        wish: Int? = nil,
        decor: Int? = nil,
        xp: Int? = nil,
        day: Int? = nil,
        band: Int? = nil
    ) {
        self.kind = kind
        self.id = id
        self.level = level
        self.hearts = hearts
        self.toneUnlocked = toneUnlocked
        self.sleep = sleep
        self.steps = steps
        self.activity = activity
        self.dominant = dominant
        self.wish = wish
        self.decor = decor
        self.xp = xp
        self.day = day
        self.band = band
    }
}

struct GrowthSnapshot {
    var version = GrowthValues.snapshotVersion
    var eventXP = 0
    var eventFamiliarity = 0
    var counterDay = ""
    var counters = [Int](repeating: 0, count: GrowthValues.sourceCount)
    /// -1 until the first sync, so an existing ledger never replays as level-ups.
    var seenLevel = -1
    var seenHearts = -1
    var seenHealthXP = -1
    var seenSplitDay = ""
    var seenSplit = GrowthSourceSplit.empty
    var pending: [GrowthFeedbackEvent] = []
    var copyCursors: [GrowthCopyCursor] = []
    var lastStarAt = 0
    var patCapToldDay = ""
    var morningToldDay = ""
    var anniversaryToldDay = 0
    var workoutToldAt = 0

    /// Counters are indexed by `PiboCoreGrowthSource.rawValue`.
    func counter(at index: Int) -> Int {
        counters.indices.contains(index) ? counters[index] : 0
    }
}

// MARK: - Day keys

/// Local day key `YYYY-MM-DD`, the unit every daily counter rolls on.
func growthDayKey(_ date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    let year = parts.year ?? 0
    let month = parts.month ?? 1
    let day = parts.day ?? 1
    return String(format: "%04d-%02d-%02d", year, month, day)
}

/// Stable numeric seed for one local day (`YYYYMMDD`).
func growthDaySeed(_ date: Date, calendar: Calendar = .current) -> Int {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return (parts.year ?? 0) * 10_000 + (parts.month ?? 1) * 100 + (parts.day ?? 1)
}

// MARK: - Lenient decoding

private func growthFinite(_ value: Any?, fallback: Double) -> Double {
    guard let number = value as? NSNumber else { return fallback }
    let double = number.doubleValue
    return double.isFinite ? double : fallback
}

private func growthNonnegative(_ value: Any?) -> Int {
    max(0, Int(growthFinite(value, fallback: 0).rounded(.down)))
}

private func growthFloored(_ value: Any?, fallback: Int) -> Int {
    Int(growthFinite(value, fallback: Double(fallback)).rounded(.down))
}

private func growthText(_ value: Any?) -> String {
    value as? String ?? ""
}

private func growthSplit(_ value: Any?) -> GrowthSourceSplit {
    guard let dictionary = value as? [String: Any] else { return .empty }
    return GrowthSourceSplit(
        sleep: max(0, growthFinite(dictionary["sleep"], fallback: 0)),
        steps: max(0, growthFinite(dictionary["steps"], fallback: 0)),
        activity: max(0, growthFinite(dictionary["activity"], fallback: 0))
    )
}

private func growthOptionalInt(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }
    return Int(number.doubleValue.rounded(.down))
}

extension GrowthFeedbackEvent {
    convenience init?(json: Any?) {
        guard let dictionary = json as? [String: Any],
              let id = dictionary["id"] as? String,
              let rawKind = dictionary["kind"] as? String,
              let kind = GrowthFeedbackKind(rawValue: rawKind) else {
            return nil
        }
        self.init(
            kind: kind,
            id: id,
            level: growthOptionalInt(dictionary["level"]),
            hearts: growthOptionalInt(dictionary["hearts"]),
            toneUnlocked: dictionary["toneUnlocked"] as? Bool,
            sleep: growthOptionalInt(dictionary["sleep"]),
            steps: growthOptionalInt(dictionary["steps"]),
            activity: growthOptionalInt(dictionary["activity"]),
            dominant: growthOptionalInt(dictionary["dominant"]),
            wish: growthOptionalInt(dictionary["wish"]),
            decor: growthOptionalInt(dictionary["decor"]),
            xp: growthOptionalInt(dictionary["xp"]),
            day: growthOptionalInt(dictionary["day"]),
            band: growthOptionalInt(dictionary["band"])
        )
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = ["id": id, "kind": kind.rawValue]
        if let level { object["level"] = level }
        if let hearts { object["hearts"] = hearts }
        if let toneUnlocked { object["toneUnlocked"] = toneUnlocked }
        if let sleep { object["sleep"] = sleep }
        if let steps { object["steps"] = steps }
        if let activity { object["activity"] = activity }
        if let dominant { object["dominant"] = dominant }
        if let wish { object["wish"] = wish }
        if let decor { object["decor"] = decor }
        if let xp { object["xp"] = xp }
        if let day { object["day"] = day }
        if let band { object["band"] = band }
        return object
    }
}

extension GrowthSnapshot {
    /// Missing or corrupt data degrades to an empty state, never a crash.
    static func decode(_ raw: String) -> GrowthSnapshot {
        guard !raw.isEmpty else { return GrowthSnapshot() }
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            GrowthLog.growth.error("growth snapshot unreadable; starting fresh")
            return GrowthSnapshot()
        }
        return GrowthSnapshot(json: dictionary)
    }

    init(json: [String: Any]) {
        var snapshot = GrowthSnapshot()
        let counters = json["counters"] as? [Any] ?? []
        for index in 0..<GrowthValues.sourceCount {
            snapshot.counters[index] = growthNonnegative(counters.indices.contains(index) ? counters[index] : nil)
        }
        snapshot.eventXP = growthNonnegative(json["eventXP"])
        snapshot.eventFamiliarity = growthNonnegative(json["eventFamiliarity"])
        snapshot.counterDay = growthText(json["counterDay"])
        snapshot.seenLevel = growthFloored(json["seenLevel"], fallback: -1)
        snapshot.seenHearts = growthFloored(json["seenHearts"], fallback: -1)
        snapshot.seenHealthXP = growthFloored(json["seenHealthXP"], fallback: -1)
        snapshot.seenSplitDay = growthText(json["seenSplitDay"])
        snapshot.seenSplit = growthSplit(json["seenSplit"])
        snapshot.pending = (json["pending"] as? [Any] ?? [])
            .compactMap(GrowthFeedbackEvent.init(json:))
            .suffix(GrowthValues.pendingLimit)
            .map { $0 }
        snapshot.copyCursors = (json["copyCursors"] as? [Any] ?? []).compactMap { item in
            guard let dictionary = item as? [String: Any], let key = dictionary["key"] as? String else {
                return nil
            }
            return GrowthCopyCursor(key: key, cursor: growthNonnegative(dictionary["cursor"]))
        }
        snapshot.lastStarAt = growthNonnegative(json["lastStarAt"])
        snapshot.patCapToldDay = growthText(json["patCapToldDay"])
        snapshot.morningToldDay = growthText(json["morningToldDay"])
        snapshot.anniversaryToldDay = growthNonnegative(json["anniversaryToldDay"])
        snapshot.workoutToldAt = growthNonnegative(json["workoutToldAt"])
        self = snapshot
    }

    var jsonObject: [String: Any] {
        [
            "version": version,
            "eventXP": eventXP,
            "eventFamiliarity": eventFamiliarity,
            "counterDay": counterDay,
            "counters": counters,
            "seenLevel": seenLevel,
            "seenHearts": seenHearts,
            "seenHealthXP": seenHealthXP,
            "seenSplitDay": seenSplitDay,
            "seenSplit": ["sleep": seenSplit.sleep, "steps": seenSplit.steps, "activity": seenSplit.activity],
            "pending": pending.map(\.jsonObject),
            "copyCursors": copyCursors.map { ["key": $0.key, "cursor": $0.cursor] },
            "lastStarAt": lastStarAt,
            "patCapToldDay": patCapToldDay,
            "morningToldDay": morningToldDay,
            "anniversaryToldDay": anniversaryToldDay,
            "workoutToldAt": workoutToldAt
        ]
    }

    var jsonString: String? {
        guard let data = try? JSONSerialization.data(withJSONObject: jsonObject) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

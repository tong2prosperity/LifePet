import Foundation
import Observation

// Pibo's day kept on this phone only (decision 058): which scene Pibo is in, today's
// trips, invitations and hide-and-seek, the shelf of finds and the away diary.
// Core decides everything about them; this only remembers what happened.
//
// Ported from HarmonyPibo `services/day/PiboDayStore.ets`. HarmonyOS keeps
// `preferences` store `pibo_day` with key `state.v1`; iOS uses one `UserDefaults` key,
// `pibo_day/state.v1`, holding the same JSON snapshot.

/// One kind of find on Pibo's shelf.
struct PiboFindRecord: Equatable {
    var item = 0
    var count = 0
    /// Relationship day it first came home.
    var firstDay = 0
    var firstAt: Double = 0
    var destination = 0
}

/// One exploring trip, as the away diary tells it.
struct PiboDiaryEntry: Equatable {
    var day = ""
    var dayCount = 0
    var steps = 0
    var destination = 0
    var item = 0
    var at: Double = 0
    var read = false
}

struct PiboTripRecord: Equatable {
    var tripIndex = 0
    var destination = 0
    var item = 0
    var stepsThreshold = 0
}

private let diaryKeep = 60
/// Meal stickers Pibo has sniffed; the mat holds at most a day's few, so a short list does.
private let sniffedKeep = 12
private let sceneCount = 3

@MainActor
@Observable
final class PiboDayStore {
    static let defaultsKey = "pibo_day/state.v1"

    var scene = 0
    private(set) var finds: [PiboFindRecord] = []
    private(set) var diary: [PiboDiaryEntry] = []
    /// The newest find not yet carried in on screen (-1 none).
    private(set) var pendingFind = -1
    /// Decision 065: the find out on display in each scene (-1 none).
    private(set) var displayed = [-1, -1, -1]
    private(set) var revision = 0
    private var sniffed: [String] = []
    private var dayKey = ""
    private var trips = 0
    private var invites = 0
    private var hidden = false
    private var echoes: UInt32 = 0
    private var lastSeenAt: Double = 0

    private let defaults: UserDefaults
    private let persistenceKey: String

    init(defaults: UserDefaults = .standard, persistenceKey: String = PiboDayStore.defaultsKey) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        restore(defaults.string(forKey: persistenceKey) ?? "")
    }

    func restore(_ raw: String) {
        scene = 0
        finds = []
        diary = []
        pendingFind = -1
        dayKey = ""
        trips = 0
        invites = 0
        hidden = false
        echoes = 0
        lastSeenAt = 0
        displayed = [-1, -1, -1]
        sniffed = []
        if !raw.isEmpty, let data = raw.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            scene = parsed["scene"] as? Int ?? 0
            dayKey = parsed["dayKey"] as? String ?? ""
            trips = parsed["tripsToday"] as? Int ?? 0
            invites = parsed["invitesToday"] as? Int ?? 0
            hidden = parsed["hiddenToday"] as? Bool ?? false
            if let value = parsed["echoesToday"] as? NSNumber {
                echoes = UInt32(truncatingIfNeeded: value.int64Value)
            }
            let rawFinds = parsed["finds"] as? [[String: Any]] ?? []
            finds = rawFinds.compactMap { find in
                guard let item = find["item"] as? Int, item >= 0,
                      let count = find["count"] as? Int, count > 0 else { return nil }
                return PiboFindRecord(item: item, count: count,
                                      firstDay: find["firstDay"] as? Int ?? 0,
                                      firstAt: (find["firstAt"] as? NSNumber)?.doubleValue ?? 0,
                                      destination: find["destination"] as? Int ?? 0)
            }
            let rawDiary = parsed["diary"] as? [[String: Any]] ?? []
            diary = rawDiary.compactMap { entry in
                guard let day = entry["day"] as? String, let item = entry["item"] as? Int else { return nil }
                return PiboDiaryEntry(day: day,
                                      dayCount: entry["dayCount"] as? Int ?? 0,
                                      steps: entry["steps"] as? Int ?? 0,
                                      destination: entry["destination"] as? Int ?? 0,
                                      item: item,
                                      at: (entry["at"] as? NSNumber)?.doubleValue ?? 0,
                                      read: entry["read"] as? Bool ?? false)
            }
            pendingFind = parsed["pendingFind"] as? Int ?? -1
            lastSeenAt = (parsed["lastSeenAt"] as? NSNumber)?.doubleValue ?? 0
            let shown = parsed["displayed"] as? [Int] ?? []
            for scene in 0..<sceneCount {
                let item = scene < shown.count ? shown[scene] : -1
                displayed[scene] = count(item) > 0 ? item : -1
            }
            let ids = parsed["sniffed"] as? [String] ?? []
            sniffed = Array(ids.suffix(sniffedKeep))
        }
        revision += 1
    }

    /// Per-day counters start over on a new local day.
    func rollDay(_ now: Double) {
        let today = dayKeyFor(now)
        if today == dayKey { return }
        dayKey = today
        trips = 0
        invites = 0
        hidden = false
        echoes = 0
        persist()
    }

    func tripsToday(_ now: Double) -> Int {
        rollDay(now)
        return trips
    }

    func invitesToday(_ now: Double) -> Int {
        rollDay(now)
        return invites
    }

    func hiddenToday(_ now: Double) -> Bool {
        rollDay(now)
        return hidden
    }

    /// Bit per item id already on the shelf, as Core's `found_mask`.
    func foundMask() -> UInt32 {
        var mask: UInt32 = 0
        for find in finds where find.item < 32 {
            mask |= 1 << UInt32(find.item)
        }
        return mask
    }

    func count(_ item: Int) -> Int {
        finds.first { $0.item == item }?.count ?? 0
    }

    /// A trip Core said was due: the find goes on the shelf and into the diary now, so
    /// nothing is lost if the app closes before Pibo walks it in.
    func recordTrip(_ trip: PiboTripRecord, dayCount: Int, now: Double) {
        rollDay(now)
        trips = max(trips, trip.tripIndex + 1)
        if let index = finds.firstIndex(where: { $0.item == trip.item }) {
            finds[index].count += 1
        } else {
            finds.append(PiboFindRecord(item: trip.item, count: 1, firstDay: dayCount,
                                        firstAt: now, destination: trip.destination))
        }
        let entry = PiboDiaryEntry(day: dayKey, dayCount: dayCount, steps: trip.stepsThreshold,
                                   destination: trip.destination, item: trip.item, at: now, read: false)
        diary = [entry] + diary
        if diary.count > diaryKeep { diary = Array(diary.prefix(diaryKeep)) }
        pendingFind = trip.item
        persist()
    }

    /// The find to carry in on screen, once.
    func takePendingFind() -> Int {
        let item = pendingFind
        if item < 0 { return -1 }
        pendingFind = -1
        persist()
        return item
    }

    func noteInvite(_ now: Double) {
        rollDay(now)
        invites += 1
        persist()
    }

    /// The life echoes already played today, as Core's `done_mask`.
    func echoesToday(_ now: Double) -> UInt32 {
        rollDay(now)
        return echoes
    }

    func noteEcho(_ echo: Int, _ now: Double) {
        rollDay(now)
        if echo <= 0 || echo >= 32 { return }
        echoes |= 1 << UInt32(echo)
        persist()
    }

    func noteHidden(_ now: Double) {
        rollDay(now)
        hidden = true
        persist()
    }

    func setScene(_ scene: Int) {
        if scene == self.scene { return }
        self.scene = scene
        persist()
    }

    /// Home was on screen at `now`; written while visible and on leaving.
    func noteSeen(_ now: Double, flush: Bool = false) {
        lastSeenAt = now
        if flush { persist() }
    }

    func awayMinutes(_ now: Double) -> Int {
        if lastSeenAt <= 0 { return 0 }
        return max(0, Int((now - lastSeenAt) / 60000))
    }

    /// The newest diary line not yet told, if any.
    func unreadDiary() -> PiboDiaryEntry? {
        diary.first { !$0.read }
    }

    func markDiaryRead() {
        if !diary.contains(where: { !$0.read }) { return }
        diary = diary.map { entry in
            var read = entry
            read.read = true
            return read
        }
        persist()
    }

    /// The find out on display in `scene`, or -1.
    func displayedIn(_ scene: Int) -> Int {
        displayed.indices.contains(scene) ? displayed[scene] : -1
    }

    /// Puts a found item out in `scene` (one spot per scene), or takes it back in with -1.
    /// An item shows in one scene at a time.
    func setDisplayed(_ scene: Int, _ item: Int) {
        if scene < 0 || scene >= sceneCount || (item >= 0 && count(item) <= 0) { return }
        var next = displayed.map { $0 == item ? -1 : $0 }
        next[scene] = item
        displayed = next
        persist()
    }

    func sniffedMeal(_ id: String) -> Bool {
        sniffed.contains(id)
    }

    func noteSniffed(_ ids: [String]) {
        let fresh = ids.filter { !sniffed.contains($0) }
        if fresh.isEmpty { return }
        sniffed = Array((sniffed + fresh).suffix(sniffedKeep))
        persist()
    }

    func reset() {
        restore("")
        persist()
    }

    private func persist() {
        revision += 1
        var snapshot: [String: Any] = [
            "scene": scene,
            "dayKey": dayKey,
            "tripsToday": trips,
            "invitesToday": invites,
            "hiddenToday": hidden,
            "echoesToday": NSNumber(value: echoes),
            "finds": finds.map { ["item": $0.item, "count": $0.count, "firstDay": $0.firstDay,
                                  "firstAt": $0.firstAt, "destination": $0.destination] },
            "diary": diary.map { ["day": $0.day, "dayCount": $0.dayCount, "steps": $0.steps,
                                  "destination": $0.destination, "item": $0.item, "at": $0.at,
                                  "read": $0.read] },
            "pendingFind": pendingFind,
            "lastSeenAt": lastSeenAt,
            "displayed": displayed,
            "sniffed": sniffed,
        ]
        if echoes > UInt32(Int32.max) { snapshot["echoesToday"] = NSNumber(value: Int64(echoes)) }
        if let data = try? JSONSerialization.data(withJSONObject: snapshot),
           let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: persistenceKey)
        }
    }

    private func dayKeyFor(_ now: Double) -> String {
        growthDayKey(Date(timeIntervalSince1970: now / 1000))
    }
}

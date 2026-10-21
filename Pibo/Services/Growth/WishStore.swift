import Foundation
import os
import Observation
import PiboCore

/// Where a sleep wish sits in the evening → morning hand-off.
enum WishNight: Int {
    case none = 0
    /// Judged by last night's sleep, offered yesterday evening.
    case lastNight = 1
    /// Offered this evening, judged tomorrow morning.
    case tonight = 2
}

struct WishSlot: Equatable {
    var kind: PiboCoreWishKind
    var target: Double
    var value: Double
    var fraction: Double
    var done: Bool
    var rewarded: Bool
    var night: WishNight

    init(
        kind: PiboCoreWishKind,
        target: Double,
        value: Double = 0,
        fraction: Double = 0,
        done: Bool = false,
        rewarded: Bool = false,
        night: WishNight = .none
    ) {
        self.kind = kind
        self.target = target
        self.value = value
        self.fraction = fraction
        self.done = done
        self.rewarded = rewarded
        self.night = night
    }
}

/// Facts the plan and the progress read. Baselines come from Core's personal
/// baseline over the person's own recent days; nil means no data shared.
struct WishFacts {
    var now: Date
    var localHour: Int
    var baselineSteps: Double?
    var baselineActiveMinutes: Double?
    var baselineSleepMinutes: Double?
    var cameraEnabled: Bool
    var companionEnabled: Bool
    var steps: Double?
    var activeMinutes: Double?
    /// Last night's sleep for the local day of `now`.
    var lastNightSleepMinutes: Double?
    var pats: Int
    var meals: Int
    var answers: Int
}

private struct WishSnapshot {
    var day = ""
    var slots: [WishSlot] = []
    /// The sleep wish offered last evening, waiting for this morning's data.
    var carried: WishSlot?
    var eveningOffered = false

    static func decode(_ raw: String) -> WishSnapshot? {
        guard !raw.isEmpty else { return nil }
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        var snapshot = WishSnapshot()
        snapshot.day = dictionary["day"] as? String ?? ""
        snapshot.slots = (dictionary["slots"] as? [Any] ?? []).compactMap(WishSlot.init(json:))
        if let carried = dictionary["carried"] as? [String: Any] {
            snapshot.carried = WishSlot(json: carried)
        }
        snapshot.eveningOffered = dictionary["eveningOffered"] as? Bool ?? false
        return snapshot
    }

    var jsonString: String? {
        var object: [String: Any] = [
            "day": day,
            "slots": slots.map(\.jsonObject),
            "eveningOffered": eveningOffered
        ]
        if let carried { object["carried"] = carried.jsonObject }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private extension WishSlot {
    init?(json: Any?) {
        guard let dictionary = json as? [String: Any],
              let rawKind = dictionary["kind"] as? NSNumber,
              let kind = PiboCoreWishKind(rawValue: rawKind.int32Value),
              let target = (dictionary["target"] as? NSNumber)?.doubleValue,
              target.isFinite, target > 0 else {
            return nil
        }
        self.init(
            kind: kind,
            target: target,
            value: (dictionary["value"] as? NSNumber)?.doubleValue ?? 0,
            fraction: (dictionary["fraction"] as? NSNumber)?.doubleValue ?? 0,
            done: dictionary["done"] as? Bool ?? false,
            rewarded: dictionary["rewarded"] as? Bool ?? false,
            night: WishNight(rawValue: (dictionary["night"] as? NSNumber)?.intValue ?? 0) ?? .none
        )
    }

    var jsonObject: [String: Any] {
        [
            "kind": Int(kind.rawValue),
            "target": target,
            "value": value,
            "fraction": fraction,
            "done": done,
            "rewarded": rewarded,
            "night": night.rawValue
        ]
    }
}

/// Today's small wishes (decision 057). Core picks kinds and targets and judges
/// progress; this store keeps the day's plan stable, carries the evening sleep
/// wish to the next morning and reports each wish once when it completes. A
/// missed wish quietly expires: no streaks, no reminders, no penalty.
///
/// Persistence mapping: HarmonyOS `preferences` store `pibo_growth_wishes` with
/// key `wishes.v1` → one `UserDefaults` key `pibo_growth_wishes/wishes.v1`.
@MainActor
@Observable
final class WishStore {
    static let defaultsKey = "pibo_growth_wishes/wishes.v1"

    private(set) var day = ""
    private(set) var slots: [WishSlot] = []
    private(set) var revision = 0
    /// Set once the evening sleep wish has actually been on screen.
    private(set) var eveningOffered = false

    @ObservationIgnored private var carried: WishSlot?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistenceKey: String

    init(defaults: UserDefaults = .standard, persistenceKey: String = WishStore.defaultsKey) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        restore(raw: defaults.string(forKey: persistenceKey) ?? "")
    }

    func restore(raw: String) {
        if raw.isEmpty { return }
        guard let snapshot = WishSnapshot.decode(raw) else {
            // Corrupt data degrades to an empty plan, never a crash.
            day = ""
            slots = []
            carried = nil
            eveningOffered = false
            revision += 1
            return
        }
        day = snapshot.day
        slots = snapshot.slots
        carried = snapshot.carried
        eveningOffered = snapshot.eveningOffered
        revision += 1
    }

    func reset() {
        day = ""
        slots = []
        carried = nil
        eveningOffered = false
        persist()
        revision += 1
    }

    /// Wishes the person can see right now, in display order.
    func visible(localHour: Int) -> [WishSlot] {
        slots.filter { slot in
            slot.night == .lastNight || PiboCoreWishes.visible(slot.kind, localHour: localHour)
        }
    }

    /// Plans a new day when needed, refreshes progress and returns the wishes
    /// that completed on this update, each exactly once.
    func update(_ facts: WishFacts) -> [WishSlot] {
        let today = growthDayKey(facts.now)
        if day != today { planDay(today, facts: facts) }

        var completed: [WishSlot] = []
        for index in slots.indices {
            guard let value = valueFor(slots[index], facts: facts) else { continue }
            slots[index].value = value
            let progress = PiboCoreWishes.progress(slots[index].kind, target: slots[index].target, value: value)
            slots[index].fraction = progress.fraction
            if progress.done && !slots[index].done { slots[index].done = true }
            if slots[index].done && !slots[index].rewarded {
                slots[index].rewarded = true
                completed.append(slots[index])
            }
        }
        persist()
        revision += 1
        if !completed.isEmpty {
            GrowthLog.growth.info("wishes completed=\(completed.count, privacy: .public)")
        }
        return completed
    }

    func markEveningSeen(localHour: Int) {
        if eveningOffered { return }
        guard let evening = slots.first(where: { $0.night == .tonight }),
              PiboCoreWishes.visible(evening.kind, localHour: localHour) else {
            return
        }
        eveningOffered = true
        persist()
    }

    // MARK: - Private

    private func planDay(_ today: String, facts: WishFacts) {
        // Yesterday's evening wish rolls into this morning only if it was offered.
        let evening = slots.first { $0.kind == .sleepEnough && $0.night == .tonight }
        carried = evening != nil && eveningOffered
            ? WishSlot(kind: .sleepEnough, target: evening?.target ?? 0, night: .lastNight)
            : nil

        let plan = PiboCoreWishes.plan(
            daySeed: UInt64(clamping: growthDaySeed(facts.now)),
            baselineSteps: facts.baselineSteps,
            baselineActiveMinutes: facts.baselineActiveMinutes,
            baselineSleepMinutes: facts.baselineSleepMinutes,
            cameraEnabled: facts.cameraEnabled,
            companionEnabled: facts.companionEnabled
        )
        var next: [WishSlot] = []
        if let carried { next.append(carried) }
        for wish in plan {
            next.append(WishSlot(kind: wish.kind, target: wish.target,
                                 night: wish.kind == .sleepEnough ? .tonight : .none))
        }
        day = today
        slots = next
        eveningOffered = false
    }

    private func valueFor(_ slot: WishSlot, facts: WishFacts) -> Double? {
        switch slot.kind {
        case .steps: return facts.steps
        case .activeMinutes: return facts.activeMinutes
        case .pats: return Double(facts.pats)
        case .mealPhoto: return Double(facts.meals)
        case .answerPrompt: return Double(facts.answers)
        // Tonight's wish waits for tomorrow; only the carried one reads last night.
        case .sleepEnough: return slot.night == .lastNight ? facts.lastNightSleepMinutes : nil
        }
    }

    private func persist() {
        let snapshot = WishSnapshot(day: day, slots: slots, carried: carried, eveningOffered: eveningOffered)
        guard let raw = snapshot.jsonString else {
            GrowthLog.growth.error("wish snapshot encode failed; keeping previous value")
            return
        }
        defaults.set(raw, forKey: persistenceKey)
    }
}

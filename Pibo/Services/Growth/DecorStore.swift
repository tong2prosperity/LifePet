import Foundation
import os
import Observation
import PiboCore

struct DecorOwnership: Equatable {
    var id: PiboCoreDecorID
    var placedAt: Date
}

/// Forest decorations bought with collected bo (decision 057). Core owns the
/// catalog, costs and level gates; the ledger owns the balance and the spend.
/// Ported from HarmonyOS `entry/src/main/ets/services/growth/DecorStore.ets`.
///
/// Persistence mapping: HarmonyOS `preferences` store `pibo_growth_decor` with
/// key `owned.v1` → one `UserDefaults` key `pibo_growth_decor/owned.v1`, holding
/// the same JSON array of `{id, placedAt}` (placedAt in milliseconds since 1970).
@MainActor
@Observable
final class DecorStore {
    private struct PendingPurchase: Codable {
        var decor: Int32
        var eventID: String
        var placedAt: Date
    }
    nonisolated static let defaultsKey = "pibo_growth_decor/owned.v1"

    private(set) var owned: [DecorOwnership] = []
    private(set) var revision = 0
    /// Debug only: show every decoration for this run without owning or persisting it.
    var debugShowAll = false

    @ObservationIgnored private var catalogCache: [PiboCoreDecorDefinition] = []
    @ObservationIgnored private var buying = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistenceKey: String

    init(defaults: UserDefaults = .standard, persistenceKey: String = DecorStore.defaultsKey) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        restore(raw: defaults.string(forKey: persistenceKey) ?? "")
    }

    func restore(raw: String) {
        guard !raw.isEmpty else {
            revision += 1
            return
        }
        guard let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let items = parsed as? [Any] else {
            owned = []
            revision += 1
            return
        }
        var seen = Set<Int32>()
        owned = items.compactMap { item in
            guard let dictionary = item as? [String: Any],
                  let rawID = (dictionary["id"] as? NSNumber)?.int32Value,
                  let id = PiboCoreDecorID(rawValue: rawID),
                  !seen.contains(rawID) else {
                return nil
            }
            seen.insert(rawID)
            let placedAt = (dictionary["placedAt"] as? NSNumber)?.doubleValue ?? 0
            return DecorOwnership(id: id, placedAt: Date(timeIntervalSince1970: placedAt / 1000))
        }
        revision += 1
    }

    func reset() {
        owned = []
        revision += 1
        defaults.removeObject(forKey: persistenceKey)
        defaults.removeObject(forKey: pendingKey)
    }

    func catalog() -> [PiboCoreDecorDefinition] {
        if catalogCache.isEmpty { catalogCache = PiboCoreDecor.catalog }
        return catalogCache
    }

    func definition(_ id: PiboCoreDecorID) -> PiboCoreDecorDefinition? {
        catalog().first { $0.id == id }
    }

    func isOwned(_ id: PiboCoreDecorID) -> Bool {
        owned.contains { $0.id == id }
    }

    func ownedIDs() -> [PiboCoreDecorID] {
        if debugShowAll { return catalog().map(\.id) }
        return owned.map(\.id)
    }

    /// The owned pieces that stand in `scene` (decision 065: Core says which scene each
    /// belongs to; the first ten are the clearing's).
    func ownedIn(_ scene: Int) -> [PiboCoreDecorID] {
        ownedIDs().filter { PiboCoreDecor.scene($0) == scene }
    }

    func state(_ id: PiboCoreDecorID, level: Int, balance: Int) -> PiboCoreDecorState {
        PiboCoreDecor.state(for: id, level: level, balance: balance, owned: isOwned(id))
    }

    /// Something new the person could buy right now — the HUD's quiet dot.
    func hasPurchasable(level: Int, balance: Int) -> Bool {
        catalog().contains { state($0.id, level: level, balance: balance) == .purchasable }
    }

    /// Spends through the ledger first; ownership is written only after the
    /// spend is durable, so a failed write never hands out a free decoration.
    func purchase(_ id: PiboCoreDecorID, level: Int, ledger: BoLedgerStore) -> Bool {
        if buying { return false }
        recoverPendingPurchase(using: ledger)
        guard let item = definition(id),
              state(id, level: level, balance: ledger.availableBo) == .purchasable else {
            return false
        }
        buying = true
        defer { buying = false }
        let pending = PendingPurchase(decor: id.rawValue, eventID: "decor:\(UUID().uuidString)", placedAt: .now)
        guard let encoded = try? JSONEncoder().encode(pending) else { return false }
        defaults.set(encoded, forKey: pendingKey)
        guard ledger.spend(item.cost, eventID: pending.eventID) else {
            defaults.removeObject(forKey: pendingKey)
            return false
        }
        owned.append(DecorOwnership(id: id, placedAt: pending.placedAt))
        revision += 1
        persist()
        defaults.removeObject(forKey: pendingKey)
        GrowthLog.growth.info("decor placed id=\(id.rawValue, privacy: .public)")
        Analytics.track(.decorPurchased, screen: "home", [
            "decor": .string("decor_\(id.rawValue)"), "cost": .int(item.cost),
            "scene": .string(PiboAnalyticsKeys.scene(PiboCoreDecor.scene(id)))
        ])
        Analytics.track(.decorPlaced, screen: "home", ["decor": .string("decor_\(id.rawValue)")])
        return true
    }

    private var pendingKey: String {
        persistenceKey == Self.defaultsKey ? "pibo.decor.purchase.v1" : persistenceKey + "/pending.v1"
    }

    /// A crash between spend and ownership must not charge again or lose the
    /// decoration. A journal without a durable spend grants nothing.
    func recoverPendingPurchase(using ledger: BoLedgerStore) {
        guard let data = defaults.data(forKey: pendingKey),
              let pending = try? JSONDecoder().decode(PendingPurchase.self, from: data),
              let id = PiboCoreDecorID(rawValue: pending.decor) else { return }
        if ledger.hasProcessedSpend(eventID: pending.eventID), !isOwned(id) {
            owned.append(DecorOwnership(id: id, placedAt: pending.placedAt))
            persist()
            revision += 1
        }
        defaults.removeObject(forKey: pendingKey)
    }

    private func persist() {
        let items: [[String: Any]] = owned.map { ownership in
            [
                "id": Int(ownership.id.rawValue),
                "placedAt": Int(ownership.placedAt.timeIntervalSince1970 * 1000)
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items),
              let raw = String(data: data, encoding: .utf8) else {
            GrowthLog.growth.error("decor snapshot encode failed; keeping previous value")
            return
        }
        defaults.set(raw, forKey: persistenceKey)
    }
}

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
    static let defaultsKey = "pibo_growth_decor/owned.v1"

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
        guard let item = definition(id),
              state(id, level: level, balance: ledger.availableBo) == .purchasable else {
            return false
        }
        buying = true
        defer { buying = false }
        guard ledger.spend(item.cost) else { return false }
        owned.append(DecorOwnership(id: id, placedAt: .now))
        revision += 1
        persist()
        GrowthLog.growth.info("decor placed id=\(id.rawValue, privacy: .public)")
        return true
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

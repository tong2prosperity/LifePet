import Foundation
import Observation
import PiboCore
import os

enum OrnamentPurchaseResult: Equatable {
    case purchased
    case unavailable
    case prerequisiteMissing
    case insufficientBalance
    case alreadyOwned
}

private struct PendingOrnamentPurchase: Codable {
    let id: PiboOrnament.ID
    let cost: Int
    let balanceBefore: Int
}

private struct OrnamentInventoryPersistence {
    let defaults: UserDefaults
    let ownershipKey: String
    let eligibilityKey: String
    let pendingPurchaseKey: String

    func loadOwned() -> Set<PiboOrnament.ID> {
        loadIDs(forKey: ownershipKey)
    }

    func loadEligibility() -> Set<PiboOrnament.ID> {
        loadIDs(forKey: eligibilityKey)
    }

    func hasSeenUnlockGuide() -> Bool {
        defaults.bool(forKey: PiboPersistenceKeys.Defaults.boUnlockGuideSeen)
    }

    func markUnlockGuideSeen() {
        defaults.set(true, forKey: PiboPersistenceKeys.Defaults.boUnlockGuideSeen)
    }

    private func loadIDs(forKey key: String) -> Set<PiboOrnament.ID> {
        Set((defaults.array(forKey: key) as? [String] ?? [])
            .compactMap(PiboOrnament.ID.init(rawValue:)))
    }

    func saveInventory(
        owned: Set<PiboOrnament.ID>,
        eligible: Set<PiboOrnament.ID>
    ) {
        defaults.set(owned.map(\.rawValue).sorted(), forKey: ownershipKey)
        defaults.set(eligible.map(\.rawValue).sorted(), forKey: eligibilityKey)
    }

    func loadPendingPurchase() -> PendingOrnamentPurchase? {
        guard let data = defaults.data(forKey: pendingPurchaseKey) else { return nil }
        return try? JSONDecoder().decode(PendingOrnamentPurchase.self, from: data)
    }

    func savePendingPurchase(_ pending: PendingOrnamentPurchase) {
        defaults.set(try? JSONEncoder().encode(pending), forKey: pendingPurchaseKey)
    }

    func clearPendingPurchase() {
        defaults.removeObject(forKey: pendingPurchaseKey)
    }
}

/// Local, permanent inventory. Eligibility and ownership are separate so
/// future story/function milestones can grant the right to exchange without
/// silently granting the item itself.
@MainActor
@Observable
final class OrnamentUnlockStore {
    private(set) var owned: Set<PiboOrnament.ID>
    private(set) var eligible: Set<PiboOrnament.ID>
    private(set) var hasSeenUnlockGuide: Bool

    @ObservationIgnored private let persistence: OrnamentInventoryPersistence
    @ObservationIgnored private let debugUnlockOverride: Bool

    init(
        defaults: UserDefaults = .standard,
        ownershipKey: String = PiboPersistenceKeys.Defaults.boOwnedOrnaments,
        eligibilityKey: String = PiboPersistenceKeys.Defaults.boEligibleOrnaments,
        pendingPurchaseKey: String = PiboPersistenceKeys.Defaults.boPendingOrnamentPurchase,
        debugUnlockOverride: Bool? = nil
    ) {
        let persistence = OrnamentInventoryPersistence(
            defaults: defaults,
            ownershipKey: ownershipKey,
            eligibilityKey: eligibilityKey,
            pendingPurchaseKey: pendingPurchaseKey
        )
        self.persistence = persistence
        self.debugUnlockOverride = debugUnlockOverride ?? Self.launchArgumentUnlockOverride
        self.hasSeenUnlockGuide = persistence.hasSeenUnlockGuide()
        self.owned = persistence.loadOwned()
        self.eligible = persistence.loadEligibility().union(Self.initialEligibility)
        persistInventory()
    }

    /// Debug is a read-time override only. It never enters `owned` or storage.
    var unlocked: Set<PiboOrnament.ID> {
        debugUnlockOverride ? Set(PiboOrnament.ID.allCases) : owned
    }

    func isUnlocked(_ id: PiboOrnament.ID) -> Bool { unlocked.contains(id) }

    /// Capabilities are always derived from permanent ownership through Core.
    /// No platform feature keeps a second entitlement flag, so users who
    /// already own an item automatically receive newly connected routes.
    func grants(_ capability: PiboCoreUnlockableCapability) -> Bool {
        unlocked.contains { id in
            PiboCoreUnlockableItems.grants(capability, from: id.coreID)
        }
    }

    var nextLocked: PiboOrnament? {
        PiboOrnament.ordered.first { !isUnlocked($0.id) }
    }

    func state(_ id: PiboOrnament.ID, balance: Int) -> PiboCoreUnlockableItemState {
        let definition = PiboOrnament.coreDefinition(id)
        let prerequisiteOwned = definition.prerequisiteID
            .flatMap(coreItemID)
            .map(isUnlocked) ?? true
        return PiboCoreUnlockableItems.state(
            for: id.coreID,
            eligible: eligible.contains(id),
            prerequisiteOwned: prerequisiteOwned,
            balance: balance,
            owned: isUnlocked(id)
        )
    }

    func canUnlock(_ id: PiboOrnament.ID, balance: Int) -> Bool {
        state(id, balance: balance) == .purchasable
    }

    func grantEligibility(_ id: PiboOrnament.ID) {
        guard eligible.insert(id).inserted else { return }
        persistInventory()
    }

    func purchase(_ id: PiboOrnament.ID, using ledger: BoLedgerStore) -> OrnamentPurchaseResult {
        switch state(id, balance: ledger.balance) {
        case .owned: return .alreadyOwned
        case .unavailable: return .unavailable
        case .eligible:
            let prerequisite = PiboOrnament.coreDefinition(id).prerequisiteID.flatMap(coreItemID)
            return prerequisite.map(isUnlocked) == false ? .prerequisiteMissing : .insufficientBalance
        case .purchasable: break
        }

        let cost = PiboOrnament.coreDefinition(id).cost
        persistence.savePendingPurchase(
            PendingOrnamentPurchase(id: id, cost: cost, balanceBefore: ledger.balance)
        )
        guard ledger.spend(cost) else {
            persistence.clearPendingPurchase()
            return .insufficientBalance
        }
        owned.insert(id)
        persistInventory()
        persistence.clearPendingPurchase()
        LPLog.bo.notice("ornament purchased=\(id.rawValue, privacy: .public) cost=\(cost, privacy: .public)")
        return .purchased
    }

    /// Completes the only crash window: ledger persisted its debit but inventory
    /// did not yet persist ownership. No other item purchase can overlap on the
    /// main actor, so the before/after balance identifies that committed debit.
    @discardableResult
    func recoverPendingPurchase(using ledger: BoLedgerStore) -> PiboOrnament.ID? {
        guard let pending = persistence.loadPendingPurchase() else { return nil }
        var recoveredID: PiboOrnament.ID?
        if ledger.balance <= pending.balanceBefore - pending.cost {
            owned.insert(pending.id)
            persistInventory()
            recoveredID = pending.id
            LPLog.bo.notice("recovered ornament purchase=\(pending.id.rawValue, privacy: .public)")
        }
        persistence.clearPendingPurchase()
        return recoveredID
    }

    func shouldHighlightUnlockGuide(balance: Int) -> Bool {
        guard !hasSeenUnlockGuide, let first = PiboOrnament.ordered.first else { return false }
        return state(first.id, balance: balance) == .purchasable
    }

    func markUnlockGuideSeen() {
        guard !hasSeenUnlockGuide else { return }
        hasSeenUnlockGuide = true
        persistence.markUnlockGuideSeen()
    }

    func reset() {
        owned = []
        eligible = Self.initialEligibility
        persistInventory()
        persistence.clearPendingPurchase()
    }

    private func coreItemID(_ id: PiboCoreUnlockableItemID) -> PiboOrnament.ID? {
        PiboOrnament.ID.allCases.first { $0.coreID == id }
    }

    private func persistInventory() {
        persistence.saveInventory(owned: owned, eligible: eligible)
    }

    private static var initialEligibility: Set<PiboOrnament.ID> {
        Set(PiboOrnament.all.compactMap { ornament in
            PiboOrnament.coreDefinition(ornament.id).initiallyEligible ? ornament.id : nil
        })
    }

    private static var launchArgumentUnlockOverride: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-PiboUnlockAllCommonItems")
        #else
        false
        #endif
    }
}

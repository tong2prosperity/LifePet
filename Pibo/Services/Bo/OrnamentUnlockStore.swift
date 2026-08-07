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

/// Local, permanent inventory. Eligibility and ownership are separate so
/// future story/function milestones can grant the right to exchange without
/// silently granting the item itself.
@MainActor
@Observable
final class OrnamentUnlockStore {
    private(set) var owned: Set<PiboOrnament.ID>
    private(set) var eligible: Set<PiboOrnament.ID>
    private(set) var hasSeenUnlockGuide: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let ownershipKey: String
    @ObservationIgnored private let eligibilityKey: String
    @ObservationIgnored private let pendingPurchaseKey: String
    @ObservationIgnored private let debugUnlockOverride: Bool

    init(
        defaults: UserDefaults = .standard,
        ownershipKey: String = PiboPersistenceKeys.Defaults.boOwnedOrnaments,
        eligibilityKey: String = PiboPersistenceKeys.Defaults.boEligibleOrnaments,
        pendingPurchaseKey: String = PiboPersistenceKeys.Defaults.boPendingOrnamentPurchase,
        debugUnlockOverride: Bool? = nil
    ) {
        self.defaults = defaults
        self.ownershipKey = ownershipKey
        self.eligibilityKey = eligibilityKey
        self.pendingPurchaseKey = pendingPurchaseKey
        self.debugUnlockOverride = debugUnlockOverride ?? Self.launchArgumentUnlockOverride
        self.hasSeenUnlockGuide = defaults.bool(forKey: PiboPersistenceKeys.Defaults.boUnlockGuideSeen)
        self.owned = Set((defaults.array(forKey: ownershipKey) as? [String] ?? [])
            .compactMap(PiboOrnament.ID.init(rawValue:)))
        let persistedEligibility = Set((defaults.array(forKey: eligibilityKey) as? [String] ?? [])
            .compactMap(PiboOrnament.ID.init(rawValue:)))
        let initialEligibility = Set(PiboOrnament.all.compactMap { ornament in
            PiboOrnament.coreDefinition(ornament.id).initiallyEligible ? ornament.id : nil
        })
        self.eligible = persistedEligibility.union(initialEligibility)
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
        persistPending(PendingOrnamentPurchase(id: id, cost: cost, balanceBefore: ledger.balance))
        guard ledger.spend(cost) else {
            clearPending()
            return .insufficientBalance
        }
        owned.insert(id)
        persistInventory()
        clearPending()
        LPLog.bo.notice("ornament purchased=\(id.rawValue, privacy: .public) cost=\(cost, privacy: .public)")
        return .purchased
    }

    /// Completes the only crash window: ledger persisted its debit but inventory
    /// did not yet persist ownership. No other item purchase can overlap on the
    /// main actor, so the before/after balance identifies that committed debit.
    @discardableResult
    func recoverPendingPurchase(using ledger: BoLedgerStore) -> PiboOrnament.ID? {
        guard let data = defaults.data(forKey: pendingPurchaseKey),
              let pending = try? JSONDecoder().decode(PendingOrnamentPurchase.self, from: data)
        else { return nil }
        var recoveredID: PiboOrnament.ID?
        if ledger.balance <= pending.balanceBefore - pending.cost {
            owned.insert(pending.id)
            persistInventory()
            recoveredID = pending.id
            LPLog.bo.notice("recovered ornament purchase=\(pending.id.rawValue, privacy: .public)")
        }
        clearPending()
        return recoveredID
    }

    func shouldHighlightUnlockGuide(balance: Int) -> Bool {
        guard !hasSeenUnlockGuide, let first = PiboOrnament.ordered.first else { return false }
        return state(first.id, balance: balance) == .purchasable
    }

    func markUnlockGuideSeen() {
        guard !hasSeenUnlockGuide else { return }
        hasSeenUnlockGuide = true
        defaults.set(true, forKey: PiboPersistenceKeys.Defaults.boUnlockGuideSeen)
    }

    func reset() {
        owned = []
        eligible = Set(PiboOrnament.all.compactMap { ornament in
            PiboOrnament.coreDefinition(ornament.id).initiallyEligible ? ornament.id : nil
        })
        persistInventory()
        clearPending()
    }

    private func coreItemID(_ id: PiboCoreUnlockableItemID) -> PiboOrnament.ID? {
        PiboOrnament.ID.allCases.first { $0.coreID == id }
    }

    private func persistInventory() {
        defaults.set(owned.map(\.rawValue).sorted(), forKey: ownershipKey)
        defaults.set(eligible.map(\.rawValue).sorted(), forKey: eligibilityKey)
    }

    private func persistPending(_ pending: PendingOrnamentPurchase) {
        defaults.set(try? JSONEncoder().encode(pending), forKey: pendingPurchaseKey)
    }

    private func clearPending() {
        defaults.removeObject(forKey: pendingPurchaseKey)
    }

    private static var launchArgumentUnlockOverride: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-PiboUnlockAllCommonItems")
        #else
        false
        #endif
    }
}

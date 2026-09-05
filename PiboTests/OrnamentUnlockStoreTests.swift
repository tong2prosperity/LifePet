import Foundation
import CoreGraphics
import PiboCore
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct OrnamentUnlockStoreTests {
    private func fixture(debug: Bool = false) throws -> (
        OrnamentUnlockStore, BoLedgerStore, UserDefaults, String
    ) {
        let suite = "OrnamentUnlockStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let ledger = BoLedgerStore(defaults: defaults, persistenceKey: "test.ledger")
        let inventory = OrnamentUnlockStore(
            defaults: defaults,
            ownershipKey: "test.owned",
            eligibilityKey: "test.eligible",
            pendingPurchaseKey: "test.pending",
            debugUnlockOverride: debug
        )
        return (inventory, ledger, defaults, suite)
    }

    @Test func coreCatalogDefinesOrderPricesAndInitialEligibility() {
        #expect(PiboOrnament.ordered.map(\.id.coreID) == PiboCoreUnlockableItems.catalog.map(\.id))
        #expect(PiboOrnament.ordered.map(\.cost) == PiboCoreUnlockableItems.catalog.map(\.cost))
        #expect(PiboOrnament.ordered.map(\.id) == [.hammock, .statusObserver, .chime, .lantern])
        #expect(PiboOrnament.ordered.map(\.cost) == [1, 3, 6, 10])
        #expect(PiboOrnament.ordered.allSatisfy { PiboOrnament.coreDefinition($0.id).initiallyEligible })
        let observer = PiboOrnament.ornament(.statusObserver)?.placement
        #expect(observer?.frame == CGRect(x: 24, y: 606, width: 76, height: 96))
        #expect(observer?.zPosition == 30)
    }

    @Test func releaseInventoryStartsEligibleButUnowned() throws {
        let (inventory, _, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(inventory.owned.isEmpty)
        #expect(inventory.eligible == Set(PiboOrnament.ID.allCases))
        #expect(inventory.state(.hammock, balance: 1) == .purchasable)
        #expect(inventory.state(.chime, balance: 99) == .eligible)
    }

    @Test func purchasesAreSequentialExactAndPersistent() throws {
        let (inventory, ledger, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        ledger.debugSet(balance: 20)

        #expect(inventory.purchase(.chime, using: ledger) == .prerequisiteMissing)
        #expect(inventory.purchase(.hammock, using: ledger) == .purchased)
        #expect(ledger.balance == 19)
        #expect(inventory.purchase(.hammock, using: ledger) == .alreadyOwned)
        #expect(inventory.purchase(.statusObserver, using: ledger) == .purchased)
        #expect(ledger.balance == 16)
        #expect(inventory.purchase(.lantern, using: ledger) == .prerequisiteMissing)
        #expect(inventory.purchase(.chime, using: ledger) == .purchased)
        #expect(ledger.balance == 10)
        #expect(inventory.purchase(.lantern, using: ledger) == .purchased)
        #expect(ledger.balance == 0)

        let restored = OrnamentUnlockStore(
            defaults: defaults,
            ownershipKey: "test.owned",
            eligibilityKey: "test.eligible",
            pendingPurchaseKey: "test.pending",
            debugUnlockOverride: false
        )
        #expect(restored.owned == Set(PiboOrnament.ID.allCases))
        restored.reset()
        #expect(restored.owned.isEmpty)
        #expect(restored.eligible == Set(PiboOrnament.ID.allCases))
    }

    @Test func insufficientBalanceNeverMutatesInventoryOrLedger() throws {
        let (inventory, ledger, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(inventory.purchase(.hammock, using: ledger) == .insufficientBalance)
        #expect(inventory.owned.isEmpty)
        #expect(ledger.balance == 0)
    }

    @Test func aRipeBoCanWakeTheFirstObjectDirectly() throws {
        let (inventory, ledger, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        ledger.debugSet(ripe: 1)

        #expect(ledger.balance == 0)
        #expect(ledger.availableBo == 1)
        #expect(inventory.purchase(.hammock, using: ledger) == .purchased)
        #expect(ledger.state.ripeCount == 0)
        #expect(inventory.owned == [.hammock])
    }

    @Test func debugOverrideIsEffectiveButNeverPersisted() throws {
        let (inventory, _, defaults, suite) = try fixture(debug: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(inventory.unlocked == Set(PiboOrnament.ID.allCases))
        #expect(inventory.owned.isEmpty)
        #expect((defaults.array(forKey: "test.owned") as? [String]) == [])
    }

    @Test func capabilitiesAreDerivedFromPermanentItemOwnership() throws {
        let (inventory, ledger, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        ledger.debugSet(balance: 20)

        #expect(!inventory.grants(.sleepReview))
        #expect(!inventory.grants(.dewCamera))
        #expect(inventory.purchase(.hammock, using: ledger) == .purchased)
        #expect(inventory.grants(.sleepReview))
        #expect(inventory.grants(.wakeNotification))
        #expect(!inventory.grants(.dewCamera))

        #expect(inventory.purchase(.statusObserver, using: ledger) == .purchased)
        #expect(inventory.grants(.recoveryStatus))
        #expect(inventory.purchase(.chime, using: ledger) == .purchased)
        #expect(inventory.grants(.walkEchoCollection))
        #expect(!inventory.grants(.dewCamera))
        #expect(!inventory.grants(.walkDoodle))
        #expect(!inventory.grants(.shadowPiboEligibility))
        #expect(inventory.purchase(.lantern, using: ledger) == .purchased)
        #expect(inventory.grants(.lanternLighting))
    }

    @Test func pendingDebitIsRecoveredAfterRelaunch() throws {
        let (inventory, ledger, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        ledger.debugSet(balance: 4)
        let pending: [String: Any] = ["id": "hammock", "cost": 1, "balanceBefore": 5]
        defaults.set(try JSONSerialization.data(withJSONObject: pending), forKey: "test.pending")

        let recovered = inventory.recoverPendingPurchase(using: ledger)
        #expect(recovered == .hammock)
        #expect(inventory.owned == [.hammock])
        #expect(defaults.object(forKey: "test.pending") == nil)
    }
}

import Foundation
import PiboCore
import Testing
@testable import Pibo

@MainActor
struct DecorPurchaseRecoveryTests {
    private struct Journal: Codable {
        var decor: Int32
        var eventID: String
        var placedAt: Date
    }

    @Test func paidPurchaseRecoversOwnershipAfterRelaunchWithoutSpendingTwice() throws {
        let key = "DecorPurchaseRecovery.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let ledger = BoLedgerStore(defaults: defaults, persistenceKey: "ledger")
        ledger.debugSet(balance: 20)
        let decor = DecorStore(defaults: defaults, persistenceKey: "decor")
        let definition = try #require(decor.catalog().first)
        #expect(decor.purchase(definition.id, level: 100, ledger: ledger))
        let after = ledger.availableBo
        let event = try #require(ledger.state.processedSpendEventIDs.first)
        // Simulate termination after the journal and debit, before ownership.
        defaults.removeObject(forKey: "decor")
        defaults.set(try JSONEncoder().encode(Journal(decor: definition.id.rawValue, eventID: event, placedAt: .now)),
                     forKey: "decor/pending.v1")
        let restoredLedger = BoLedgerStore(defaults: defaults, persistenceKey: "ledger")
        let restored = DecorStore(defaults: defaults, persistenceKey: "decor")
        restored.recoverPendingPurchase(using: restoredLedger)
        restored.recoverPendingPurchase(using: restoredLedger)
        #expect(restored.isOwned(definition.id))
        #expect(restored.owned.count == 1)
        #expect(restoredLedger.availableBo == after)
        #expect(restoredLedger.spend(definition.cost, eventID: event))
        #expect(restoredLedger.availableBo == after)
    }

    @Test func journalWrittenBeforePaymentDoesNotGrantFreeOwnership() throws {
        let key = "DecorPurchaseRecovery.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let ledger = BoLedgerStore(defaults: defaults, persistenceKey: "ledger")
        ledger.debugSet(balance: 20)
        defaults.set(try JSONEncoder().encode(Journal(decor: 0, eventID: "unpaid", placedAt: .now)),
                     forKey: "decor/pending.v1")
        let restored = DecorStore(defaults: defaults, persistenceKey: "decor")
        restored.recoverPendingPurchase(using: ledger)
        #expect(restored.owned.isEmpty)
        #expect(ledger.availableBo == 20)
        #expect(defaults.data(forKey: "decor/pending.v1") == nil)
    }
}

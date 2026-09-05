import Foundation
import PiboCore
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct BoLedgerSyncTests {
    @Test func retryBatchIsFrozenAndSurvivesRelaunch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let first = fixture.ledger.syncRequest()
        #expect(first.ledgerEvents.count == 1)

        fixture.ledger.debugSet(balance: 2)
        #expect(fixture.ledger.syncRequest() == first)

        let restored = fixture.restoredLedger()
        #expect(restored.syncRequest() == first)

        restored.acknowledgeSync(response(nextCursor: 0))
        let next = restored.syncRequest()
        #expect(next.requestID != first.requestID)
        #expect(!next.ledgerEvents.isEmpty)
        #expect(next.ledgerEvents.allSatisfy { record in
            !first.ledgerEvents.contains(where: { $0.recordID == record.recordID })
        })
    }

    @Test func requestUsesServerWireKeysAndCarriesEligibilityBoundary() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let acceptedAt = Calendar.current.date(byAdding: .day, value: -2, to: today)!
        let fixture = try Fixture(acceptedAt: acceptedAt)
        defer { fixture.cleanUp() }
        fixture.ledger.recompute(days: [(today, metrics())])

        let request = fixture.ledger.syncRequest()
        let data = try JSONCoding.encoder.encode(request)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["request_id"] != nil)
        #expect(object["device_id"] != nil)
        #expect(object["health_records"] != nil)
        #expect(object["domain_events"] != nil)
        #expect(object["ledger_events"] != nil)
        let health = try #require(object["health_records"] as? [[String: Any]])
        #expect(health.count == 1)
        #expect(health[0]["accepted_at"] != nil)
        #expect((health[0]["payload"] as? [String: Any])?["target_energy"] != nil)
    }

    @Test func remoteHealthTargetsOnlyMoveForwardEvenWhenChangesAreOutOfOrder() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        _ = fixture.ledger.syncRequest()
        let day = BoLedgerStore.dayKey(Calendar.current.startOfDay(for: .now))

        fixture.ledger.acknowledgeSync(response(
            nextCursor: 2,
            changes: [
                entry(cursor: 2, semanticKey: "bo.health.day:\(day)", targetEnergy: 80),
                entry(cursor: 1, semanticKey: "bo.health.day:\(day)", targetEnergy: 30),
            ]
        ))

        #expect(fixture.ledger.state.grantedEnergyByDay[day] == 80)
        let expected = PiboCoreBoEconomy.applyEnergy(energyPool: 0, grantedEnergy: 80)
        #expect(abs(fixture.ledger.state.energyPool - expected.newEnergyPool) < 0.001)
        #expect(fixture.ledger.state.ripeCount == expected.mintedCount)
    }

    @Test func remoteBootstrapAndInventoryMergeAreMonotonic() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.ledger.debugSet(balance: 2, ripe: 1)
        fixture.ledger.mergeUnlockedItems(bit(.hammock))
        _ = fixture.ledger.syncRequest()

        let remoteMask = bit(.statusObserver) | bit(.chime)
        fixture.ledger.acknowledgeSync(response(
            nextCursor: 3,
            changes: [entry(
                cursor: 3,
                semanticKey: "bo.bootstrap",
                payload: BoLedgerSyncPayload(
                    energyPool: 40,
                    ripeCount: 0,
                    storedCount: 5,
                    spentTotal: 7,
                    lifetimeMinted: 12,
                    lifetimeCollected: 9,
                    unlockedItems: remoteMask
                )
            )]
        ))

        #expect(fixture.ledger.balance >= 5)
        #expect(fixture.ledger.state.ripeCount >= 1)
        #expect(fixture.ledger.unlockedItems == remoteMask | bit(.hammock))

        let inventory = OrnamentUnlockStore(
            defaults: fixture.defaults,
            ownershipKey: "test.owned",
            eligibilityKey: "test.eligible",
            pendingPurchaseKey: "test.pending",
            debugUnlockOverride: false
        )
        inventory.reconcileUnlockedBitmask(fixture.ledger.unlockedItems)
        #expect(inventory.owned == [.hammock, .statusObserver, .chime])
        #expect(!inventory.isUnlocked(.lantern))
    }

    private func metrics() -> PiboCoreBoDailyMetrics {
        PiboCoreBoAdapter.metrics(
            sleepTotal: 7 * 3_600,
            sleepDeep: 3_600,
            sleepREM: 3_600,
            awakeSeconds: 0,
            awakeSegmentCount: nil,
            steps: 8_000,
            exerciseMinutes: 30,
            hrv: 0,
            restingHR: 0
        )
    }

    private func bit(_ id: PiboCoreUnlockableItemID) -> UInt32 {
        UInt32(1) << UInt32(id.rawValue)
    }

    private func response(
        nextCursor: UInt64,
        changes: [BoLedgerSyncEntryDTO] = []
    ) -> BoLedgerSyncResponse {
        BoLedgerSyncResponse(
            accepted: 0,
            duplicates: 0,
            nextCursor: nextCursor,
            hasMore: false,
            changes: changes,
            serverTime: .now
        )
    }

    private func entry(
        cursor: UInt64,
        semanticKey: String,
        targetEnergy: Double
    ) -> BoLedgerSyncEntryDTO {
        entry(
            cursor: cursor,
            semanticKey: semanticKey,
            payload: BoLedgerSyncPayload(targetEnergy: targetEnergy)
        )
    }

    private func entry(
        cursor: UInt64,
        semanticKey: String,
        payload: BoLedgerSyncPayload
    ) -> BoLedgerSyncEntryDTO {
        BoLedgerSyncEntryDTO(
            cursor: cursor,
            kind: semanticKey.hasPrefix("bo.health.day:") ? .healthRecord : .ledgerEvent,
            recordID: "remote:\(cursor)",
            deviceID: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            epoch: 1,
            semanticKey: semanticKey,
            scoringVersion: PiboCoreBoEconomy.scoringVersion,
            occurredAt: .now,
            acceptedAt: nil,
            payload: payload,
            createdAt: .now
        )
    }
}

@MainActor
private struct Fixture {
    let suite: String
    let defaults: UserDefaults
    let ledger: BoLedgerStore

    init(acceptedAt: Date? = nil) throws {
        suite = "BoLedgerSyncTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        ledger = BoLedgerStore(
            defaults: defaults,
            persistenceKey: "test.ledger",
            syncPersistenceKey: "test.sync",
            acceptedAt: acceptedAt,
            eligibilitySource: acceptedAt == nil ? nil : .temporaryCooperation,
            eligibilityEnabled: acceptedAt != nil
        )
    }

    func restoredLedger() -> BoLedgerStore {
        BoLedgerStore(
            defaults: defaults,
            persistenceKey: "test.ledger",
            syncPersistenceKey: "test.sync"
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
    }
}

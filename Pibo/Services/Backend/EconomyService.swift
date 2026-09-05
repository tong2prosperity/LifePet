import Foundation
import os

/// App-facing economy client: uploads health/behaviour deltas and reads the
/// authoritative bo state. The server is the single source of truth for the
/// *server-side* ledger — this holds only a display mirror that the latest
/// `/sync` or `/state` overwrites.
///
/// **The on-device `bo` the user actually sees comes from `BoLedgerStore`, not
/// from here** (决定 031：本地优先，未登录和离线不阻塞第一枚). This client is the
/// future merge path for a logged-in account; it deliberately does **not** feed
/// `BoProgressFeedbackStore` — the local ledger is that queue's only producer, so
/// logging in can't double-fire the 25/50/75/90% 里程碑提示.
@MainActor
@Observable
final class EconomyService {
    private(set) var lastSync: SyncResponse?
    private(set) var lastLedgerSync: BoLedgerSyncResponse?
    private(set) var state: EconomyState?
    private(set) var config: EconomyConfigDTO?
    private(set) var isSyncing = false
    private(set) var lastError: APIError?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Relays immutable local-ledger records between this account's devices.
    /// The response is merged by `BoLedgerStore`; this service never overwrites
    /// local assets with a server projection.
    func syncLedger(_ request: BoLedgerSyncRequest) async -> BoLedgerSyncResponse? {
        do {
            let response: BoLedgerSyncResponse = try await api.post(
                "/api/v1/economy/ledger/sync",
                body: request,
                authed: true
            )
            lastLedgerSync = response
            lastError = nil
            return response
        } catch {
            lastError = .from(error)
            LPLog.economySync.notice("local ledger sync deferred: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Upload an incremental batch and apply the authoritative result.
    ///
    /// Pass a STABLE `idempotencyKey` (persisted with the queued batch) so a
    /// network retry replays the cached response instead of double-minting.
    @discardableResult
    func sync(samples: [HealthSampleDTO] = [],
              actions: [EconomyActionDTO] = [],
              idempotencyKey: String = UUID().uuidString) async -> SyncResponse? {
        isSyncing = true; lastError = nil
        defer { isSyncing = false }
        let request = SyncRequest(idempotencyKey: idempotencyKey, samples: samples, actions: actions)
        do {
            let resp: SyncResponse = try await api.post("/api/v1/economy/sync", body: request, authed: true)
            lastSync = resp
            // Keep the state mirror coherent with the just-applied result.
            state = EconomyState(boPending: resp.boPending, boBalance: resp.boBalance,
                                 energyPool: resp.energyPool, piboState: resp.piboState,
                                 serverTime: resp.serverTime)
            LPLog.economy.debug("sync → pending=\(resp.boPending) minted=\(resp.minted.count) state=\(resp.piboState, privacy: .public)")
            return resp
        } catch {
            lastError = .from(error)
            LPLog.economy.error("sync failed: \(String(describing: error))")
            return nil
        }
    }

    /// Foreground reconciliation — the authoritative state always wins over the
    /// local cache.
    @discardableResult
    func refreshState() async -> EconomyState? {
        lastError = nil
        do {
            let s: EconomyState = try await api.get("/api/v1/economy/state", authed: true)
            state = s
            return s
        } catch {
            lastError = .from(error)
            return nil
        }
    }

    /// Loads the energy curve (cheap; cache for the session).
    @discardableResult
    func loadConfig() async -> EconomyConfigDTO? {
        do {
            let c: EconomyConfigDTO = try await api.get("/api/v1/economy/config", authed: true)
            config = c
            return c
        } catch {
            lastError = .from(error)
            return nil
        }
    }
}

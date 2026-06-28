import Foundation
import os

/// App-facing economy client: uploads health/behaviour deltas and reads the
/// authoritative bo state. The server is the single source of truth — this
/// holds only a display mirror that the latest `/sync` or `/state` overwrites.
///
/// Animations are server-driven: callers should play exactly `lastSync.animations`
/// and bump the head-bo count only when `lastSync.minted` is non-empty.
@MainActor
@Observable
final class EconomyService {
    private(set) var lastSync: SyncResponse?
    private(set) var state: EconomyState?
    private(set) var config: EconomyConfigDTO?
    private(set) var isSyncing = false
    private(set) var lastError: APIError?

    private let api: APIClient
    private let log = Logger(subsystem: "fun.tiebao.co.Pibo", category: "economy")

    init(api: APIClient = .shared) {
        self.api = api
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
            log.debug("sync → pending=\(resp.boPending) minted=\(resp.minted.count) state=\(resp.piboState, privacy: .public)")
            return resp
        } catch {
            lastError = .from(error)
            log.error("sync failed: \(String(describing: error))")
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

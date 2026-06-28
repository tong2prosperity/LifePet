import Foundation

/// Wire types for the economy endpoints. camelCase ⇄ snake_case via the shared
/// coders; these match `internal/economy/...` on the server exactly.

// MARK: - Requests

/// One normalized raw health sample. `dedupKey` carries the platform's stable
/// sample UUID (HealthKit `HKSample.uuid`) or a derived hash for aggregate
/// buckets — it gives the server sample-level idempotency.
struct HealthSampleDTO: Encodable, Sendable {
    let metric: String
    let value: Double
    let unit: String
    let startTs: Date
    let endTs: Date
    let sourcePlatform: String
    let externalSampleId: String?
    let dedupKey: String

    init(metric: String, value: Double, unit: String, startTs: Date, endTs: Date,
         sourcePlatform: String = "ios", externalSampleId: String? = nil, dedupKey: String) {
        self.metric = metric
        self.value = value
        self.unit = unit
        self.startTs = startTs
        self.endTs = endTs
        self.sourcePlatform = sourcePlatform
        self.externalSampleId = externalSampleId
        self.dedupKey = dedupKey
    }
}

/// One in-app behaviour event (photo / game / pat). `eventId` is a client UUID
/// giving the server event-level idempotency.
struct EconomyActionDTO: Encodable, Sendable {
    let eventId: String
    let actionType: String
    let occurredAt: Date

    init(eventId: String = UUID().uuidString, actionType: String, occurredAt: Date = .now) {
        self.eventId = eventId
        self.actionType = actionType
        self.occurredAt = occurredAt
    }
}

struct SyncRequest: Encodable, Sendable {
    /// Per-call UUID; reuse the SAME value on retry so the server replays the
    /// cached response instead of double-minting.
    let idempotencyKey: String
    /// Diagnostics only — the server never uses it for any decision.
    let clientTime: Date
    let samples: [HealthSampleDTO]
    let actions: [EconomyActionDTO]

    init(idempotencyKey: String = UUID().uuidString,
         clientTime: Date = .now,
         samples: [HealthSampleDTO] = [],
         actions: [EconomyActionDTO] = []) {
        self.idempotencyKey = idempotencyKey
        self.clientTime = clientTime
        self.samples = samples
        self.actions = actions
    }
}

// MARK: - Responses

struct Mint: Decodable, Sendable {
    let reason: String
    let delta: Int
}

/// Response to `/sync`. The server is authoritative — `minted`/`animations`
/// drive the UI, the client never decides whether to play an animation.
struct SyncResponse: Decodable, Sendable {
    let boPending: Int
    let boBalance: Int
    let energyPool: Double
    let minted: [Mint]
    let piboState: String
    let animations: [String]
    let serverTime: Date
}

/// Response to `/state` — sync-shaped, minus per-call minted/animations.
struct EconomyState: Decodable, Sendable {
    let boPending: Int
    let boBalance: Int
    let energyPool: Double
    let piboState: String
    let serverTime: Date
}

/// Response to `/config` — the energy curve, for client cost previews.
struct EconomyConfigDTO: Decodable, Sendable {
    struct MetricRule: Decodable, Sendable {
        let energyPerUnit: Double
        let perEventCap: Double
    }
    let energyPerBo: Double
    let dailyEnergyCap: Double
    let metrics: [String: MetricRule]
    let actions: [String: Double]
    let serverTime: Date
}

import Foundation

enum BoLedgerSyncKind: String, Codable, Sendable {
    case healthRecord = "health_record"
    case domainEvent = "domain_event"
    case ledgerEvent = "ledger_event"
}

struct BoLedgerSyncPayload: Codable, Equatable, Sendable {
    var energyPool: Double? = nil
    var ripeCount: Int? = nil
    var storedCount: Int? = nil
    var spentTotal: Int? = nil
    var lifetimeMinted: Int? = nil
    var lifetimeCollected: Int? = nil
    var unlockedItems: UInt32? = nil
    var targetEnergy: Double? = nil
    var amount: Double? = nil
    var itemID: Int? = nil
    var eventID: String? = nil
}

struct BoLedgerSyncRecord: Codable, Equatable, Sendable {
    let kind: BoLedgerSyncKind
    let recordID: String
    let semanticKey: String
    let scoringVersion: UInt32
    let occurredAt: Date
    let acceptedAt: Date?
    let payload: BoLedgerSyncPayload
}

struct BoLedgerSyncEntryDTO: Codable, Equatable, Sendable {
    let cursor: UInt64
    let kind: BoLedgerSyncKind
    let recordID: String
    let deviceID: String
    let epoch: UInt32
    let semanticKey: String
    let scoringVersion: UInt32
    let occurredAt: Date
    let acceptedAt: Date?
    let payload: BoLedgerSyncPayload
    let createdAt: Date
}

struct BoLedgerSyncRequest: Codable, Equatable, Sendable {
    let requestID: String
    let deviceID: String
    let cursor: UInt64
    let epoch: UInt32
    let healthRecords: [BoLedgerSyncRecord]
    let domainEvents: [BoLedgerSyncRecord]
    let ledgerEvents: [BoLedgerSyncRecord]
}

struct BoLedgerSyncResponse: Codable, Equatable, Sendable {
    let accepted: Int
    let duplicates: Int
    let nextCursor: UInt64
    let hasMore: Bool
    let changes: [BoLedgerSyncEntryDTO]
    let serverTime: Date
}

struct BoLedgerSyncState: Codable, Equatable, Sendable {
    var deviceID: UUID
    var cursor: UInt64 = 0
    var sequence: UInt64 = 0
    var outbox: [BoLedgerSyncRecord] = []
    var activeRequestID: UUID?
    var activeRecordIDs: [String] = []
}

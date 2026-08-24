import Foundation

enum ShadowRelationshipState: String, Codable, Sendable {
    case none
    case inviteOutgoing = "invite_outgoing"
    case activeWaitingSnapshot = "active_waiting_snapshot"
    case activeFresh = "active_fresh"
    case activeCached = "active_cached"
    case activePaused = "active_paused"
    case ended
    case blocked

    var isActive: Bool {
        switch self {
        case .activeWaitingSnapshot, .activeFresh, .activeCached, .activePaused: true
        default: false
        }
    }
}

struct ShadowInvitationDTO: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let inviteUrl: String
    let token: String
    let shortCode: String
    let expiresAt: Date
}

struct ShadowInvitationPreviewDTO: Codable, Equatable, Sendable {
    let invitationId: String
    let inviterDisplayName: String
    let expiresAt: Date
    let canAccept: Bool
    let reason: String?
}

struct ShadowSnapshotDTO: Codable, Equatable, Sendable {
    let publicStateId: String
    let publicBehaviorSubstateId: String
    let visualVariantKey: String
    let snapshotRevision: Int64
    let occurredAt: Date
    let syncedAt: Date
}

struct ShadowFriendDTO: Codable, Equatable, Sendable {
    let displayName: String
    let sharingPaused: Bool
    let snapshot: ShadowSnapshotDTO?
}

struct ShadowLightDTO: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let senderName: String
    let createdAt: Date
    let expiresAt: Date
}

struct ShadowEndedEventDTO: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let createdAt: Date
}

struct ShadowStateDTO: Codable, Equatable, Sendable {
    let state: ShadowRelationshipState
    let cursor: Int64
    let serverTime: Date
    let relationshipId: String?
    let connectedAt: Date?
    let mySharingPaused: Bool
    let mySnapshotRevision: Int64
    let outgoingInvitation: ShadowInvitationDTO?
    let friend: ShadowFriendDTO?
    let pendingLight: ShadowLightDTO?
    let endedEvent: ShadowEndedEventDTO?
    let blockedCount: Int
}

struct ShadowSyncDTO: Codable, Equatable, Sendable {
    let changed: Bool
    let view: ShadowStateDTO
}

struct ShadowBlockDTO: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let createdAt: Date
}

struct ShadowBlocksDTO: Codable, Equatable, Sendable {
    let blocks: [ShadowBlockDTO]
}

struct ShadowSnapshotDraft: Equatable, Sendable {
    let displayName: String
    let publicStateId: String
    let publicBehaviorSubstateId: String
    let visualVariantKey: String
    let occurredAt: Date

    var signature: String {
        [displayName, publicStateId, publicBehaviorSubstateId, visualVariantKey]
            .joined(separator: "|")
    }
}

struct ShadowSnapshotRequest: Codable, Equatable, Sendable {
    let displayName: String
    let publicStateId: String
    let publicBehaviorSubstateId: String
    let visualVariantKey: String
    let occurredAt: Date
    let snapshotRevision: Int64
}

struct ShadowInvitationCreateRequest: Encodable { let displayName: String }
struct ShadowInvitationCredentialRequest: Encodable { let credential: String }
struct ShadowInvitationAcceptRequest: Encodable { let credential: String; let displayName: String }
struct ShadowSharingRequest: Encodable { let paused: Bool }
struct ShadowEmptyRequest: Encodable {}

import Foundation
import Observation

@MainActor
@Observable
final class ShadowFriendStore {
    private struct Record: Codable {
        var schemaVersion = 1
        var userID: String
        var view: ShadowStateDTO?
        var hideOnHome = false
        var relationshipID = ""
        var lastSnapshotRevision: Int64 = 0
        var lastSnapshotSignature = ""
        var manifestedRelationshipID = ""
    }

    private(set) var activeUserID = ""
    private(set) var cachedView: ShadowStateDTO?
    private(set) var hideOnHome = false
    private(set) var revision = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var record = Record(userID: "")

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    @discardableResult
    func activate(userID: String) -> ShadowStateDTO? {
        activeUserID = userID
        record = Self.loadRecord(userID: userID, defaults: defaults)
        cachedView = record.view
        hideOnHome = record.hideOnHome
        revision += 1
        return cachedView
    }

    func deactivate() {
        activeUserID = ""
        cachedView = nil
        hideOnHome = false
        record = Record(userID: "")
        revision += 1
    }

    func applyServerView(_ view: ShadowStateDTO) {
        guard !activeUserID.isEmpty else { return }
        let relationshipID = view.relationshipId ?? ""
        if relationshipID != record.relationshipID {
            record.relationshipID = relationshipID
            record.lastSnapshotRevision = max(0, view.mySnapshotRevision)
            record.lastSnapshotSignature = ""
        } else {
            record.lastSnapshotRevision = max(record.lastSnapshotRevision, view.mySnapshotRevision)
        }
        if view.state.isActive {
            let clean = Self.sanitizedActiveView(view)
            cachedView = clean
            record.view = clean
        } else {
            cachedView = nil
            record.view = nil
            if relationshipID.isEmpty {
                record.relationshipID = ""
                record.lastSnapshotRevision = 0
                record.lastSnapshotSignature = ""
            }
        }
        revision += 1
        persist()
    }

    func setHideOnHome(_ hidden: Bool) {
        guard !activeUserID.isEmpty, hidden != hideOnHome else { return }
        hideOnHome = hidden
        record.hideOnHome = hidden
        revision += 1
        persist()
    }

    func needsManifestTeaching(_ view: ShadowStateDTO) -> Bool {
        guard let relationshipID = view.relationshipId, !relationshipID.isEmpty else { return false }
        return view.friend?.snapshot != nil && record.manifestedRelationshipID != relationshipID
    }

    func markManifestTeachingShown(_ view: ShadowStateDTO) {
        guard let relationshipID = view.relationshipId,
              !relationshipID.isEmpty,
              record.manifestedRelationshipID != relationshipID else { return }
        record.manifestedRelationshipID = relationshipID
        persist()
    }

    func snapshotRequest(
        view: ShadowStateDTO,
        draft: ShadowSnapshotDraft,
        force: Bool = false
    ) -> ShadowSnapshotRequest? {
        guard view.state.isActive,
              let relationshipID = view.relationshipId,
              !relationshipID.isEmpty,
              !view.mySharingPaused else { return nil }
        if relationshipID != record.relationshipID {
            record.relationshipID = relationshipID
            record.lastSnapshotRevision = max(0, view.mySnapshotRevision)
            record.lastSnapshotSignature = ""
        }
        let serverRevision = max(0, view.mySnapshotRevision)
        if !force,
           draft.signature == record.lastSnapshotSignature,
           record.lastSnapshotRevision >= serverRevision,
           record.lastSnapshotRevision > 0 { return nil }
        return ShadowSnapshotRequest(
            displayName: draft.displayName,
            publicStateId: draft.publicStateId,
            publicBehaviorSubstateId: draft.publicBehaviorSubstateId,
            visualVariantKey: draft.visualVariantKey,
            occurredAt: draft.occurredAt,
            snapshotRevision: max(serverRevision, record.lastSnapshotRevision) + 1
        )
    }

    func confirmSnapshot(_ request: ShadowSnapshotRequest) {
        record.lastSnapshotRevision = request.snapshotRevision
        record.lastSnapshotSignature = [
            request.displayName,
            request.publicStateId,
            request.publicBehaviorSubstateId,
            request.visualVariantKey,
        ].joined(separator: "|")
        persist()
    }

    private static func sanitizedActiveView(_ view: ShadowStateDTO) -> ShadowStateDTO {
        ShadowStateDTO(
            state: view.state,
            cursor: view.cursor,
            serverTime: view.serverTime,
            relationshipId: view.relationshipId,
            connectedAt: view.connectedAt,
            mySharingPaused: view.mySharingPaused,
            mySnapshotRevision: view.mySnapshotRevision,
            outgoingInvitation: nil,
            friend: view.friend,
            pendingLight: nil,
            endedEvent: nil,
            blockedCount: view.blockedCount
        )
    }

    private static func loadRecord(userID: String, defaults: UserDefaults) -> Record {
        guard !userID.isEmpty,
              let data = defaults.data(forKey: key(userID)),
              let value = try? JSONDecoder().decode(Record.self, from: data),
              value.schemaVersion == 1,
              value.userID == userID else { return Record(userID: userID) }
        return value
    }

    private func persist() {
        guard !activeUserID.isEmpty,
              let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: Self.key(activeUserID))
    }

    private static func key(_ userID: String) -> String {
        "pibo.shadow.friend.account.\(userID).v1"
    }
}

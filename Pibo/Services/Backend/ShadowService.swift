import Foundation
import Observation
import os

@MainActor
@Observable
final class ShadowService {
    private(set) var view: ShadowStateDTO?
    private(set) var incoming: ShadowInvitationPreviewDTO?
    private(set) var incomingCredential = ""
    private(set) var blocks = ShadowBlocksDTO(blocks: [])
    private(set) var usingCachedView = false
    private(set) var isBusy = false
    private(set) var lastError: APIError?

    @ObservationIgnored var onServerView: ((ShadowStateDTO) -> Void)?
    private let api: APIClient

    init(api: APIClient = .shared) { self.api = api }

    func applyCachedView(_ view: ShadowStateDTO?) {
        self.view = view
        usingCachedView = view != nil
    }

    func clearSession() {
        view = nil
        incoming = nil
        incomingCredential = ""
        blocks = ShadowBlocksDTO(blocks: [])
        usingCachedView = false
        isBusy = false
        lastError = nil
    }

    @discardableResult
    func refreshState() async -> ShadowStateDTO? {
        do {
            let value: ShadowStateDTO = try await api.get("/api/v1/shadow/state", authed: true)
            publish(value)
            return value
        } catch {
            record(error)
            return nil
        }
    }

    func sync(cursor: Int64, waitSeconds: Int) async -> ShadowSyncDTO? {
        let cursor = max(-1, cursor)
        let wait = max(0, min(25, waitSeconds))
        do {
            let result: ShadowSyncDTO = try await api.get(
                "/api/v1/shadow/sync?cursor=\(cursor)&wait_seconds=\(wait)",
                authed: true,
                timeout: 35
            )
            publish(result.view)
            return result
        } catch {
            if !Task.isCancelled { record(error) }
            return nil
        }
    }

    func createInvitation(displayName: String) async -> ShadowInvitationDTO? {
        await busy {
            let invitation: ShadowInvitationDTO = try await api.post(
                "/api/v1/shadow/invitations",
                body: ShadowInvitationCreateRequest(displayName: displayName),
                authed: true
            )
            _ = await refreshState()
            return invitation
        }
    }

    func setIncomingCredential(_ credential: String) {
        incomingCredential = Self.normalizedCredential(credential)
        incoming = nil
    }

    func handleInviteURL(_ url: URL) -> Bool {
        let path = url.pathComponents.filter { $0 != "/" }
        let isCustom = url.scheme?.lowercased() == "pibo"
            && url.host?.lowercased() == "shadow"
            && path.first?.lowercased() == "invite"
        let isWeb = ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            && path.suffix(2).first?.lowercased() == "invite"
        guard isCustom || isWeb, let credential = path.last else { return false }
        setIncomingCredential(credential)
        return !incomingCredential.isEmpty
    }

    func previewInvitation(_ credential: String? = nil) async -> ShadowInvitationPreviewDTO? {
        if let credential { setIncomingCredential(credential) }
        guard !incomingCredential.isEmpty else { return nil }
        return await busy {
            let encoded = incomingCredential.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                ?? incomingCredential
            let preview: ShadowInvitationPreviewDTO = try await api.get(
                "/api/v1/shadow/invitations/preview?credential=\(encoded)",
                authed: true
            )
            incoming = preview
            return preview
        }
    }

    func dismissIncoming() {
        incoming = nil
        incomingCredential = ""
    }

    func rejectIncoming(block: Bool) async -> Bool {
        guard !incomingCredential.isEmpty else { return false }
        return await busy {
            let endpoint = block ? "block" : "reject"
            try await api.postNoContent(
                "/api/v1/shadow/invitations/\(endpoint)",
                body: ShadowInvitationCredentialRequest(credential: incomingCredential),
                authed: true
            )
            dismissIncoming()
            _ = await refreshState()
            return true
        } ?? false
    }

    func acceptInvitation(displayName: String) async -> ShadowStateDTO? {
        guard !incomingCredential.isEmpty else { return nil }
        return await busy {
            let value: ShadowStateDTO = try await api.post(
                "/api/v1/shadow/invitations/accept",
                body: ShadowInvitationAcceptRequest(
                    credential: incomingCredential,
                    displayName: displayName
                ),
                authed: true
            )
            dismissIncoming()
            publish(value)
            return value
        }
    }

    func cancelInvitation(id: String) async -> Bool {
        await busy {
            try await api.deleteNoContent(
                "/api/v1/shadow/invitations/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)",
                authed: true
            )
            _ = await refreshState()
            return true
        } ?? false
    }

    func publishSnapshot(_ request: ShadowSnapshotRequest) async -> ShadowStateDTO? {
        do {
            let value: ShadowStateDTO = try await api.put(
                "/api/v1/shadow/snapshot", body: request, authed: true
            )
            publish(value)
            return value
        } catch {
            record(error)
            return nil
        }
    }

    func setSharingPaused(_ paused: Bool) async -> ShadowStateDTO? {
        await busy {
            let value: ShadowStateDTO = try await api.put(
                "/api/v1/shadow/sharing",
                body: ShadowSharingRequest(paused: paused),
                authed: true
            )
            publish(value)
            return value
        }
    }

    func sendLight() async -> ShadowLightDTO? {
        await busy {
            try await api.post(
                "/api/v1/shadow/light", body: ShadowEmptyRequest(), authed: true
            )
        }
    }

    func acknowledgeLight(id: String) async {
        do {
            try await api.postNoContent(
                "/api/v1/shadow/light/\(id)/ack", body: ShadowEmptyRequest(), authed: true
            )
        } catch { record(error) }
    }

    func acknowledgeEnded(id: String) async {
        do {
            try await api.postNoContent(
                "/api/v1/shadow/ended/\(id)/ack", body: ShadowEmptyRequest(), authed: true
            )
            _ = await refreshState()
        } catch { record(error) }
    }

    func disconnect(block: Bool) async -> Bool {
        await busy {
            if block {
                try await api.postNoContent(
                    "/api/v1/shadow/relationship/block",
                    body: ShadowEmptyRequest(),
                    authed: true
                )
            } else {
                try await api.deleteNoContent("/api/v1/shadow/relationship", authed: true)
            }
            _ = await refreshState()
            return true
        } ?? false
    }

    func refreshBlocks() async {
        do {
            blocks = try await api.get("/api/v1/shadow/blocks", authed: true)
        } catch { record(error) }
    }

    func unblock(id: String) async -> Bool {
        await busy {
            try await api.deleteNoContent("/api/v1/shadow/blocks/\(id)", authed: true)
            await refreshBlocks()
            _ = await refreshState()
            return true
        } ?? false
    }

    private func publish(_ value: ShadowStateDTO) {
        view = value
        usingCachedView = false
        lastError = nil
        onServerView?(value)
    }

    private func busy<T>(_ operation: () async throws -> T) async -> T? {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do { return try await operation() }
        catch {
            record(error)
            return nil
        }
    }

    private func record(_ error: Error) {
        lastError = .from(error)
        LPLog.shadow.warning("Shadow backend request failed: \(String(describing: error), privacy: .public)")
    }

    private static func normalizedCredential(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

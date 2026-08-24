import Foundation
import Observation

@MainActor
@Observable
final class ShadowSyncCoordinator {
    private let auth: AuthService
    private let service: ShadowService
    private let store: ShadowFriendStore
    private let lightStore: ShadowFriendLightStore

    private var activeUserID = ""
    private var appActive = true
    private var generation = 0
    private var publishing = false
    private var initialized = false
    private var latestDraft: ShadowSnapshotDraft?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(
        auth: AuthService,
        service: ShadowService,
        store: ShadowFriendStore,
        lightStore: ShadowFriendLightStore
    ) {
        self.auth = auth
        self.service = service
        self.store = store
        self.lightStore = lightStore
    }

    func initialize() {
        guard !initialized else { return }
        initialized = true
        service.onServerView = { [weak self] view in self?.applyServerView(view) }
        lightStore.onConsumed = { [weak self] id in
            Task { await self?.service.acknowledgeLight(id: id) }
        }
        auth.onSessionChanged = { [weak self] userID in
            Task { await self?.activateAccount(userID ?? "") }
        }
        Task { await activateAccount(auth.userId ?? "") }
    }

    func setAppActive(_ active: Bool) {
        guard appActive != active else { return }
        appActive = active
        generation += 1
        pollTask?.cancel()
        if active, !activeUserID.isEmpty {
            let generation = generation
            pollTask = Task { await foregroundCycle(generation: generation) }
        }
    }

    func setSnapshotDraft(_ draft: ShadowSnapshotDraft?) {
        let changed = latestDraft?.signature != draft?.signature
        latestDraft = draft
        guard changed, appActive, !activeUserID.isEmpty else { return }
        Task { await publishSnapshot(force: false) }
    }

    func syncNow(forceSnapshot: Bool = false) async {
        guard initialized, appActive, !activeUserID.isEmpty else { return }
        if await service.refreshState() != nil {
            await publishSnapshot(force: forceSnapshot)
        }
    }

    func resetLocalState() {
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        store.deactivate()
        lightStore.deactivate()
        service.clearSession()
        activeUserID = ""
    }

    private func activateAccount(_ userID: String) async {
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        activeUserID = userID
        guard !userID.isEmpty else {
            store.deactivate()
            lightStore.deactivate()
            service.clearSession()
            return
        }
        service.applyCachedView(store.activate(userID: userID))
        lightStore.activate(userID: userID)
        guard appActive else { return }
        let generation = generation
        pollTask = Task { await foregroundCycle(generation: generation) }
    }

    private func foregroundCycle(generation expected: Int) async {
        guard expected == generation, appActive, !activeUserID.isEmpty else { return }
        if await service.refreshState() != nil { await publishSnapshot(force: false) }
        while expected == generation, appActive, !activeUserID.isEmpty, !Task.isCancelled {
            let cursor = service.view?.cursor ?? 0
            let result = await service.sync(cursor: cursor, waitSeconds: 20)
            guard expected == generation, appActive, !Task.isCancelled else { return }
            if result?.changed == true {
                await publishSnapshot(force: false)
            } else if result == nil {
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func applyServerView(_ view: ShadowStateDTO) {
        guard !activeUserID.isEmpty else { return }
        store.applyServerView(view)
        if let light = view.pendingLight {
            _ = lightStore.enqueue(
                id: light.id,
                senderName: light.senderName,
                receivedAt: light.createdAt
            )
        }
    }

    private func publishSnapshot(force: Bool) async {
        guard !publishing,
              let view = service.view,
              let draft = latestDraft,
              let request = store.snapshotRequest(view: view, draft: draft, force: force)
        else { return }
        publishing = true
        defer { publishing = false }
        if await service.publishSnapshot(request) != nil {
            store.confirmSnapshot(request)
        }
    }
}

import Foundation
import os
import WatchConnectivity

@MainActor
final class WatchCompanionSyncService: NSObject, WCSessionDelegate {
    enum Status { case waiting, refreshing, received }

    static let shared = WatchCompanionSyncService()
    var onSnapshot: ((PiboCompanionSnapshot) -> Void)?
    var onStatus: ((Status) -> Void)?

    private let persistenceKey = "pibo.watch.companion.snapshot.v2"
    private var cache = PiboCompanionCache()
    private var requestID: UUID?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        let defaults = UserDefaults.standard
        let data = defaults.data(forKey: persistenceKey)
            ?? defaults.data(forKey: "pibo.watch.companion.snapshot.v1")
        if let value = PiboCompanionSnapshotCoding.decode(data) { cache.apply(value) }
    }

    func activate() -> PiboCompanionSnapshot? {
        guard WCSession.isSupported() else { return cache.snapshot }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .activated {
            receiveContext(session)
            requestLatest(session)
        } else {
            onStatus?(.refreshing)
            session.activate()
        }
        return cache.snapshot
    }

    private func receiveContext(_ session: WCSession) {
        if let data = session.receivedApplicationContext[PiboCompanionSnapshotCoding.applicationContextKey] as? Data {
            apply(data)
        }
    }

    private func requestLatest(_ session: WCSession) {
        guard session.activationState == .activated else { return }
        guard session.isReachable else { onStatus?(.waiting); return }
        guard requestID == nil else { return }
        let id = UUID()
        requestID = id
        onStatus?(.refreshing)
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.finishRequest(id)
        }
        session.sendMessage([PiboCompanionSnapshotCoding.requestKey: true], replyHandler: { [weak self] reply in
            let data = reply[PiboCompanionSnapshotCoding.applicationContextKey] as? Data
            Task { @MainActor in
                if let data { self?.apply(data) }
                self?.finishRequest(id)
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in self?.finishRequest(id) }
        })
    }

    private func finishRequest(_ id: UUID) {
        guard requestID == id else { return }
        requestID = nil
        timeoutTask?.cancel()
        onStatus?(.waiting)
    }

    private func apply(_ data: Data) {
        guard let value = PiboCompanionSnapshotCoding.decode(data), cache.apply(value),
              let accepted = cache.snapshot,
              let encoded = PiboCompanionSnapshotCoding.encode(accepted) else { return }
        UserDefaults.standard.set(encoded, forKey: persistenceKey)
        requestID = nil
        timeoutTask?.cancel()
        onSnapshot?(accepted)
        onStatus?(.received)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard activationState == .activated, error == nil else {
                self.onStatus?(.waiting)
                LPLog.watchCompanion.debug("watch companion activation deferred")
                return
            }
            self.receiveContext(session)
            self.requestLatest(session)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.requestLatest(session) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[PiboCompanionSnapshotCoding.applicationContextKey] as? Data else { return }
        Task { @MainActor [weak self] in self?.apply(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[PiboCompanionSnapshotCoding.applicationContextKey] as? Data else { return }
        Task { @MainActor [weak self] in self?.apply(data) }
    }
}

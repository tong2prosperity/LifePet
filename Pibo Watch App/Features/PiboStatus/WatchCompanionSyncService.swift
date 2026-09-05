import Foundation
import WatchConnectivity

@MainActor
final class WatchCompanionSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchCompanionSyncService()
    var onSnapshot: ((PiboCompanionSnapshot) -> Void)?

    private let persistenceKey = "pibo.watch.companion.snapshot.v1"

    func activate() -> PiboCompanionSnapshot? {
        guard WCSession.isSupported() else { return storedSnapshot() }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        if let data = session.receivedApplicationContext[PiboCompanionSnapshotCoding.applicationContextKey] as? Data {
            apply(data)
        }
        if session.isReachable {
            session.sendMessage([PiboCompanionSnapshotCoding.requestKey: true], replyHandler: { [weak self] reply in
                guard let data = reply[PiboCompanionSnapshotCoding.applicationContextKey] as? Data else { return }
                Task { @MainActor in self?.apply(data) }
            })
        }
        return storedSnapshot()
    }

    private func apply(_ data: Data) {
        guard let value = PiboCompanionSnapshotCoding.decode(data) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
        onSnapshot?(value)
    }

    private func storedSnapshot() -> PiboCompanionSnapshot? {
        PiboCompanionSnapshotCoding.decode(UserDefaults.standard.data(forKey: persistenceKey))
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[PiboCompanionSnapshotCoding.applicationContextKey] as? Data else { return }
        Task { @MainActor [weak self] in self?.apply(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[PiboCompanionSnapshotCoding.applicationContextKey] as? Data else { return }
        Task { @MainActor [weak self] in self?.apply(data) }
    }
}

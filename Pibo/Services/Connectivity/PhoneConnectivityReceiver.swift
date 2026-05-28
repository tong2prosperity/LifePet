import Foundation
import WatchConnectivity

final class PhoneConnectivityReceiver: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivityReceiver()

    nonisolated let messages: AsyncStream<ConnectivityMessage>
    nonisolated private let continuation: AsyncStream<ConnectivityMessage>.Continuation

    private override init() {
        let (stream, cont) = AsyncStream<ConnectivityMessage>.makeStream(bufferingPolicy: .bufferingNewest(256))
        self.messages = stream
        self.continuation = cont
        super.init()
        guard WCSession.isSupported() else {
            print("[Pibo] WCSession not supported")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    nonisolated private func dispatch(_ dict: [String: Any]) {
        do {
            let message = try ConnectivityCodec.decode(dict)
            print("[Pibo] received: \(Self.summarize(message))")
            continuation.yield(message)
        } catch {
            print("[Pibo] decode failed: \(error)")
        }
    }

    nonisolated private static func summarize(_ message: ConnectivityMessage) -> String {
        switch message {
        case .sessionStarted(let s): return "sessionStarted(\(s.id.uuidString.prefix(8)))"
        case .snapshot(let s): return "snapshot(\(s.samples.count) samples)"
        case .sessionEnded(let id, _): return "sessionEnded(\(id.uuidString.prefix(8)))"
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        print("[Pibo] WCSession activated: state=\(activationState.rawValue) err=\(String(describing: error))")
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("[Pibo] WCSession inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("[Pibo] WCSession deactivated, reactivating")
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        dispatch(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        dispatch(userInfo)
    }
}

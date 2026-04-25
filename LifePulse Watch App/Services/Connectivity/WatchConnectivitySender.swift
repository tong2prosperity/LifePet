import Foundation
import WatchConnectivity

final class WatchConnectivitySender: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivitySender()

    private override init() {
        super.init()
        guard WCSession.isSupported() else {
            print("[LifePulse watch] WCSession not supported")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    nonisolated func send(_ message: ConnectivityMessage) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        do {
            let payload = try ConnectivityCodec.encode(message)
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil) { error in
                    print("[LifePulse watch] sendMessage error: \(error)")
                }
                print("[LifePulse watch] sent via sendMessage: \(Self.summarize(message))")
            } else {
                session.transferUserInfo(payload)
                print("[LifePulse watch] queued via transferUserInfo: \(Self.summarize(message))")
            }
        } catch {
            print("[LifePulse watch] encode failed: \(error)")
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
        print("[LifePulse watch] WCSession activated: state=\(activationState.rawValue) err=\(String(describing: error))")
    }

    // Required when the compiler sees the iOS SDK's WCSessionDelegate.
    // Never invoked on watchOS; harmless there.
#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
#endif
}

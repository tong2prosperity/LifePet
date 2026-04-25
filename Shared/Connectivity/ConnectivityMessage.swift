import Foundation

nonisolated enum ConnectivityMessage: Codable, Sendable {
    case sessionStarted(VitalSession)
    case snapshot(VitalSnapshot)
    case sessionEnded(sessionID: UUID, endedAt: Date)
}

import Foundation

nonisolated struct GeneratedTrack: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let localURL: URL
    let createdAt: Date
    let durationSeconds: Double

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        localURL: URL,
        createdAt: Date = Date(),
        durationSeconds: Double
    ) {
        self.id = id
        self.sessionID = sessionID
        self.localURL = localURL
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
    }
}

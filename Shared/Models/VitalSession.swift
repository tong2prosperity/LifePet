import Foundation

nonisolated struct VitalSession: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    var isActive: Bool { endedAt == nil }
}

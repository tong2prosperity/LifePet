import Foundation

nonisolated struct VitalSnapshot: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let timestamp: Date
    let samples: [VitalSample]

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        timestamp: Date = Date(),
        samples: [VitalSample]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.samples = samples
    }

    func first(of kind: VitalKind) -> VitalSample? {
        samples.first { $0.kind == kind }
    }
}

import Foundation

nonisolated struct VitalSample: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let kind: VitalKind
    let value: Double
    let unit: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        kind: VitalKind,
        value: Double,
        unit: String,
        timestamp: Date
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
    }
}

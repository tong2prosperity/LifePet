import Foundation

nonisolated enum VitalKind: String, Codable, Sendable, CaseIterable {
    case heartRate
    case spo2
    case hrv
    case rrInterval
}

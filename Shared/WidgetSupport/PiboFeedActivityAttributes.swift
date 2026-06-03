#if canImport(ActivityKit)
import ActivityKit
import Foundation

nonisolated struct PiboFeedActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var title: String
        var message: String
        var vitalityGain: Int
        var stateTag: String
        var endedAt: Date
        var isComplete: Bool
    }

    var petName: String
    var workoutID: UUID
}
#endif

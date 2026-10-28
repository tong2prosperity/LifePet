import Foundation
import HealthKit

/// One actual HealthKit activity query, with its original civil-day window.
/// A missing quantity is unknown; a measured zero remains a real zero.
struct HealthActivityUpdate: Sendable {
    enum Metric: Sendable { case activeEnergy, exerciseMinutes, standMinutes, standHours }
    let metric: Metric
    let value: Double?
    let dayStart: Date
    let asOf: Date
    var goal: Double? = nil

    static func metric(for identifier: HKQuantityTypeIdentifier) -> Metric? {
        switch identifier {
        case .activeEnergyBurned: .activeEnergy
        case .appleExerciseTime: .exerciseMinutes
        case .appleStandTime: .standMinutes
        default: nil
        }
    }
}

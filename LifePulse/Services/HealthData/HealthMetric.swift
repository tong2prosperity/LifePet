import Foundation
import HealthKit

/// The metrics LifePet reads from HealthKit. Each metric maps to one of the
/// three PRD stats — see the table in `CLAUDE.md` for the formulas.
enum HealthMetric: String, CaseIterable, Sendable {
    case steps             // 体力
    case exerciseMinutes   // 体力
    case activeEnergy      // 体力
    case standMinutes      // 体力
    case heartRate         // 心情 (stability proxy)
    case hrv               // 心情 (SDNN)
    case restingHR         // 心情 baseline
    case sleep             // 精力
    case mindful           // 心情 supplement (+15)
    case workout           // auto-tick suggest cards

    /// The corresponding HK type. `nil` if it isn't representable as a single
    /// `HKObjectType` (none of ours fall into that bucket today, but future
    /// composite metrics might).
    var hkType: HKObjectType {
        switch self {
        case .steps:           return HKQuantityType(.stepCount)
        case .exerciseMinutes: return HKQuantityType(.appleExerciseTime)
        case .activeEnergy:    return HKQuantityType(.activeEnergyBurned)
        case .standMinutes:    return HKQuantityType(.appleStandTime)
        case .heartRate:       return HKQuantityType(.heartRate)
        case .hrv:             return HKQuantityType(.heartRateVariabilitySDNN)
        case .restingHR:       return HKQuantityType(.restingHeartRate)
        case .sleep:           return HKCategoryType(.sleepAnalysis)
        case .mindful:         return HKCategoryType(.mindfulSession)
        case .workout:         return HKWorkoutType.workoutType()
        }
    }
}

extension Set where Element == HealthMetric {
    /// All read-side HK types as an `HKObjectType` set, suitable for
    /// `HKHealthStore.requestAuthorization(toShare:read:)`.
    var hkReadTypes: Set<HKObjectType> {
        Set<HKObjectType>(map(\.hkType))
    }
}

import Foundation
import HealthKit

/// The metrics Pibo reads from HealthKit. Each metric maps to one of the
/// three PRD stats — see the table in `CLAUDE.md` for the formulas.
enum HealthMetric: String, CaseIterable, Sendable {
    case steps             // 体力
    case exerciseMinutes   // 体力
    case activeEnergy      // 体力
    case standMinutes      // 体力
    case heartRate         // 心情 (stability proxy)
    case hrv               // 心情 (SDNN)
    case heartbeatSeries   // 压力 — 逐拍心搏序列，自算 RMSSD (非 Apple SDNN)
    case restingHR         // 心情 baseline
    case oxygen            // 体征 血氧 (SpO2)
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
        case .heartbeatSeries: return HKSeriesType.heartbeat()
        case .restingHR:       return HKQuantityType(.restingHeartRate)
        case .oxygen:          return HKQuantityType(.oxygenSaturation)
        case .sleep:           return HKCategoryType(.sleepAnalysis)
        case .mindful:         return HKCategoryType(.mindfulSession)
        case .workout:         return HKWorkoutType.workoutType()
        }
    }

    /// Background-delivery cadence. `.immediate` wakes the app on *every* watch
    /// sync of this type — a real battery cost — so only genuinely time-sensitive
    /// metrics use it: `.workout` (drives the 发芽/能量收集 flow),
    /// `.heartbeatSeries` (a stress spike can push a notification while
    /// backgrounded), and `.sleep` (drives the once-per-wake-day morning
    /// notification). The system may still coalesce delivery; foreground
    /// reconciliation remains the correctness fallback.
    var backgroundDeliveryFrequency: HKUpdateFrequency {
        switch self {
        case .workout, .heartbeatSeries, .sleep: return .immediate
        default:                                 return .hourly
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

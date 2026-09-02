import Foundation
import PiboCore

/// Presentation-only projection for the compact Home status observer.
/// Core owns every score, band, reason, window and missing-value decision;
/// this type only chooses the honest UI state for the latest persisted result.
struct WellnessObserverPresentation: Equatable {
    enum Band: Equatable {
        case significantlyBelow
        case belowPersonalNormal
        case personalNormal
        case ample
    }

    enum Load: Equatable {
        case buildingBaseline
        case belowUsual
        case usual
        case aboveUsual
        case unavailable
    }

    enum Reason: Equatable {
        case missingCurrentSleep
        case buildingPersonalBaseline
        case sleepInsufficient
        case sleepSufficient
        case hrvBelowUsual
        case hrvUsual
        case hrvAboveUsual
        case heartRateElevated
        case heartRateUsual
        case heartRateLowerThanUsual
        case temperatureDeviation
        case recentLoadAboveUsual
        case recentLoadUsual
    }

    enum UnavailableKind: Equatable {
        case healthKitUnavailable
        case needsAuthorization
        case checking
        case noReadableData
        case temporarilyInterrupted
        case missingCurrentSleep
        case buildingPersonalBaseline(observed: Int, required: Int)
        case updating
        case insufficientData

        var offersHealthDetails: Bool {
            switch self {
            case .healthKitUnavailable, .needsAuthorization, .noReadableData,
                 .temporarilyInterrupted:
                true
            case .checking, .missingCurrentSleep, .buildingPersonalBaseline,
                 .updating, .insufficientData:
                false
            }
        }
    }

    struct Available: Equatable {
        let score: Double
        let band: Band
        let sleepSufficiency: Double?
        let load: Load
        let primaryReason: Reason?
        let secondaryReason: Reason?
        let calibrationDays: Int
        let generatedAt: Date
    }

    enum Content: Equatable {
        case available(Available)
        case unavailable(UnavailableKind)
    }

    let content: Content

    static func make(
        record: HealthDayRecord?,
        availability: HealthDataService.DataAvailability
    ) -> WellnessObserverPresentation {
        switch availability {
        case .unavailable:
            return .init(content: .unavailable(.healthKitUnavailable))
        case .needsAuthorization:
            return .init(content: .unavailable(.needsAuthorization))
        case .checking:
            return .init(content: .unavailable(.checking))
        case .noReadableData:
            return .init(content: .unavailable(.noReadableData))
        case .temporarilyInterrupted:
            return .init(content: .unavailable(.temporarilyInterrupted))
        case .available:
            break
        }

        guard let snapshot = record?.wellnessSnapshot else {
            return .init(content: .unavailable(.missingCurrentSleep))
        }
        guard snapshot.algorithmVersion == PiboCoreWellness.algorithmVersion else {
            return .init(content: .unavailable(.updating))
        }

        guard let score = snapshot.readinessScore?.value else {
            let reason = readinessReason(snapshot.readinessPrimaryReason)
            switch reason {
            case .missingCurrentSleep:
                return .init(content: .unavailable(.missingCurrentSleep))
            case .buildingPersonalBaseline:
                return .init(content: .unavailable(.buildingPersonalBaseline(
                    observed: max(0, snapshot.readinessCalibrationDays ?? 0),
                    required: max(1, snapshot.readinessRequiredCalibrationDays ?? 7)
                )))
            default:
                return .init(content: .unavailable(.insufficientData))
            }
        }

        guard let band = readinessBand(snapshot.readinessBand) else {
            return .init(content: .unavailable(.updating))
        }

        let primary = readinessReason(snapshot.readinessPrimaryReason)
        let candidateSecondary = readinessReason(snapshot.readinessSecondaryReason)
        let secondary = candidateSecondary == primary ? nil : candidateSecondary
        return .init(content: .available(Available(
            score: score,
            band: band,
            sleepSufficiency: snapshot.readinessSleepSufficiency,
            load: readinessLoad(snapshot.readinessLoadStatus),
            primaryReason: primary,
            secondaryReason: secondary,
            calibrationDays: max(0, snapshot.readinessCalibrationDays ?? 0),
            generatedAt: snapshot.generatedAt
        )))
    }

    private static func readinessBand(_ rawValue: Int32?) -> Band? {
        guard let rawValue,
              let value = PiboCoreWellnessReadinessBand(rawValue: rawValue)
        else { return nil }
        return switch value {
        case .unavailable: nil
        case .significantlyBelow: .significantlyBelow
        case .belowPersonalNormal: .belowPersonalNormal
        case .personalNormal: .personalNormal
        case .ample: .ample
        }
    }

    private static func readinessLoad(_ rawValue: Int32?) -> Load {
        guard let rawValue,
              let value = PiboCoreWellnessLoadStatus(rawValue: rawValue)
        else { return .unavailable }
        return switch value {
        case .unavailable: .unavailable
        case .buildingBaseline: .buildingBaseline
        case .belowUsual: .belowUsual
        case .usual: .usual
        case .aboveUsual: .aboveUsual
        }
    }

    private static func readinessReason(_ rawValue: Int32?) -> Reason? {
        guard let rawValue,
              let value = PiboCoreWellnessReadinessReason(rawValue: rawValue)
        else { return nil }
        return switch value {
        case .unavailable: nil
        case .missingCurrentSleep: .missingCurrentSleep
        case .buildingPersonalBaseline: .buildingPersonalBaseline
        case .sleepInsufficient: .sleepInsufficient
        case .sleepSufficient: .sleepSufficient
        case .hrvBelowUsual: .hrvBelowUsual
        case .hrvUsual: .hrvUsual
        case .hrvAboveUsual: .hrvAboveUsual
        case .heartRateElevated: .heartRateElevated
        case .heartRateUsual: .heartRateUsual
        case .heartRateLowerThanUsual: .heartRateLowerThanUsual
        case .temperatureDeviation: .temperatureDeviation
        case .recentLoadAboveUsual: .recentLoadAboveUsual
        case .recentLoadUsual: .recentLoadUsual
        }
    }
}

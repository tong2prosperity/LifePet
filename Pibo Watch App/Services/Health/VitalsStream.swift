import Foundation
import HealthKit

nonisolated final class VitalsStream: NSObject, HKLiveWorkoutBuilderDelegate {
    typealias Handler = @Sendable ([VitalSample]) -> Void

    nonisolated(unsafe) var onSamples: Handler?

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let now = Date()
        var samples: [VitalSample] = []

        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let stats = workoutBuilder.statistics(for: quantityType),
                  let quantity = stats.mostRecentQuantity() else { continue }

            switch quantityType.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                samples.append(VitalSample(
                    kind: .heartRate,
                    value: quantity.doubleValue(for: bpmUnit),
                    unit: "bpm",
                    timestamp: now
                ))
            case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
                samples.append(VitalSample(
                    kind: .spo2,
                    value: quantity.doubleValue(for: .percent()) * 100,
                    unit: "%",
                    timestamp: now
                ))
            default:
                continue
            }
        }

        guard !samples.isEmpty else { return }
        onSamples?(samples)
    }
}

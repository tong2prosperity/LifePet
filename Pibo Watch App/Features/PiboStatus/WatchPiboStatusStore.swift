import Combine
import Foundation
import HealthKit

@MainActor
final class WatchPiboStatusStore: ObservableObject {
    enum LoadState: Equatable { case loading, ready, unavailable }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var vectorState: PiboVectorState = .default
    @Published private(set) var title = "Pibo 正安静待着"
    @Published private(set) var detail = "今天也在这里"

    private let healthStore = HKHealthStore()

    func refresh() async {
        guard HKHealthStore.isHealthDataAvailable() else { applyFallback(); return }
        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.stepCount), HKObjectType.workoutType(), HKCategoryType(.sleepAnalysis),
        ]
        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            async let steps = todaySteps()
            async let workout = hasWorkoutToday()
            async let sleep = lastNightSleepHours()
            apply(steps: await steps, hasWorkout: await workout, sleepHours: await sleep)
        } catch { applyFallback() }
    }

    private func apply(steps: Int?, hasWorkout: Bool?, sleepHours: Double?) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let localHour = Double(components.hour ?? 12) + Double(components.minute ?? 0) / 60
        let presentation = Self.presentation(
            localHour: localHour,
            hasHealthData: steps != nil || hasWorkout != nil || sleepHours != nil,
            hasWorkout: hasWorkout == true,
            sleepHours: sleepHours
        )
        vectorState = presentation.state
        title = presentation.title
        detail = presentation.detail
        loadState = .ready
    }

    private func applyFallback() {
        vectorState = .default
        title = "Pibo 正安静待着"
        detail = "健康数据暂不可用"
        loadState = .unavailable
    }

    /// Presentation-only fallback while the pinned PiboCore XCFramework has no
    /// watchOS slice. This deliberately avoids reproducing the six-state domain
    /// machine; it selects only a final pose from direct, qualitative signals.
    private static func presentation(
        localHour: Double,
        hasHealthData: Bool,
        hasWorkout: Bool,
        sleepHours: Double?
    ) -> (state: PiboVectorState, title: String, detail: String) {
        if localHour < 6 {
            return (.sleep_1, "Pibo 睡着了", "动作放得很轻")
        }
        if localHour < 9 {
            if let sleepHours, sleepHours < 7 {
                return (.tired, "Pibo 还有点困", "今天先轻一点")
            }
            return (.awake, "Pibo 刚刚醒来", "正在慢慢清醒")
        }
        if hasWorkout {
            return (.muscle, "Pibo 很有精神", "身体里有充足的能量")
        }
        if !hasHealthData {
            return (.default, "Pibo 正安静待着", "健康数据暂不可用")
        }
        return (.boring, "Pibo 正安静待着", "今天也在这里")
    }

    private func todaySteps() async -> Int? {
        let type = HKQuantityType(.stepCount)
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                guard error == nil else { continuation.resume(returning: nil); return }
                let count = result?.sumQuantity()?.doubleValue(for: .count())
                continuation.resume(returning: count.map { Int($0.rounded()) })
            }
            healthStore.execute(query)
        }
    }

    private func hasWorkoutToday() async -> Bool? {
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                continuation.resume(returning: error == nil ? !(samples?.isEmpty ?? true) : nil)
            }
            healthStore.execute(query)
        }
    }

    private func lastNightSleepHours() async -> Double? {
        let type = HKCategoryType(.sleepAnalysis)
        let now = Date()
        guard let start = Calendar.current.date(byAdding: .hour, value: -18, to: now) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard error == nil, let samples = samples as? [HKCategorySample] else { continuation.resume(returning: nil); return }
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                let seconds = samples.filter { asleepValues.contains($0.value) }.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: samples.isEmpty ? nil : seconds / 3600)
            }
            healthStore.execute(query)
        }
    }
}

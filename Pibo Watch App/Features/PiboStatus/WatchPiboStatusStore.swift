import Combine
import Foundation
import HealthKit

@MainActor
final class WatchPiboStatusStore: ObservableObject {
    enum LoadState: Equatable { case loading, ready, unavailable }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var vectorState: PiboVectorState = .default
    @Published private(set) var petName = "Pibo"
    @Published private(set) var stateLabel = "等待手机同步"
    @Published private(set) var detail = "活动数据可由手表暂时补充"
    @Published private(set) var activeEnergy: Double?
    @Published private(set) var exerciseMinutes: Int?
    @Published private(set) var standHours: Int?
    @Published private(set) var moveProgress: Double?
    @Published private(set) var exerciseProgress: Double?
    @Published private(set) var standProgress: Double?
    @Published private(set) var scene: PiboFlatWorldScene = .rainGorge
    @Published private(set) var shadow: PiboCompanionShadowSnapshot?
    @Published private(set) var waitingForPhone = true

    private let healthStore = HKHealthStore()
    private let companion = WatchCompanionSyncService.shared

    init() {
        companion.onSnapshot = { [weak self] value in self?.applyPhoneSnapshot(value) }
    }

    func refresh() async {
        loadState = .loading
        if let value = companion.activate(), value.isAcceptable() {
            applyPhoneSnapshot(value)
            return
        }
        await applyDirectActivityFallback()
    }

    private func applyPhoneSnapshot(_ value: PiboCompanionSnapshot) {
        guard value.isAcceptable() else { return }
        petName = value.petName
        stateLabel = value.stateLabel
        detail = "来自 iPhone · \(value.generatedAt.formatted(date: .omitted, time: .shortened))"
        vectorState = Self.vectorState(for: value.publicStateID)
        activeEnergy = value.activeEnergy
        exerciseMinutes = value.exerciseMinutes
        standHours = value.standHours
        moveProgress = value.moveProgress
        exerciseProgress = value.exerciseProgress
        standProgress = value.standProgress
        scene = value.sceneID
        shadow = value.shadow.flatMap { $0.isAcceptable() ? $0 : nil }
        waitingForPhone = false
        loadState = .ready
    }

    /// Local HealthKit only fills direct activity facts. It never derives a
    /// semantic Pibo state or copies Core thresholds into the watch target.
    private func applyDirectActivityFallback() async {
        waitingForPhone = true
        vectorState = .default
        petName = "Pibo"
        stateLabel = "等待手机同步"
        detail = "Pibo 状态保持中性"
        scene = .rainGorge
        shadow = nil
        guard HKHealthStore.isHealthDataAvailable() else {
            loadState = .unavailable
            return
        }
        let types: Set<HKObjectType> = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.appleStandTime),
        ]
        do {
            try await healthStore.requestAuthorization(toShare: [], read: types)
            async let energy = todaySum(.activeEnergyBurned, unit: .kilocalorie())
            async let exercise = todaySum(.appleExerciseTime, unit: .minute())
            async let stand = todaySum(.appleStandTime, unit: .hour())
            let values = await (energy, exercise, stand)
            activeEnergy = values.0.flatMap { $0 > 0 ? $0 : nil }
            exerciseMinutes = values.1.flatMap { $0 > 0 ? Int($0.rounded()) : nil }
            standHours = values.2.flatMap { $0 > 0 ? Int($0.rounded()) : nil }
            moveProgress = nil
            exerciseProgress = nil
            standProgress = nil
            loadState = .ready
        } catch {
            loadState = .unavailable
        }
    }

    private func todaySum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let type = HKQuantityType(identifier)
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                guard error == nil else { continuation.resume(returning: nil); return }
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    static func vectorState(for publicStateID: String) -> PiboVectorState {
        switch publicStateID {
        case "sleeping": .sleep_1
        case "waking": .awake
        case "energetic": .muscle
        case "tired": .tired
        default: .default
        }
    }

    static func stateLabel(for publicStateID: String) -> String {
        switch publicStateID {
        case "sleeping": "正在睡觉"
        case "waking": "刚刚醒来"
        case "energetic": "很有精神"
        case "tired": "正在休息"
        default: "状态平稳"
        }
    }

    static func relativeUpdate(_ date: Date, now: Date = .now) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "刚刚更新" }
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours) 小时前" : "\(hours / 24) 天前"
    }
}

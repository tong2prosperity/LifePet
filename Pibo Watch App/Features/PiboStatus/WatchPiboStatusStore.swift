import Combine
import Foundation
import HealthKit

@MainActor
final class WatchPiboStatusStore: ObservableObject {
    @Published private(set) var snapshot: PiboCompanionSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isReadingActivity = false
    @Published private(set) var activityMessage: String?
    @Published private var localActivity: Activity?

    struct Activity {
        let date: Date
        let activeEnergy: Double?
        let exerciseMinutes: Int?
        let standMinutes: Int?
    }

    private let healthStore = HKHealthStore()
    private let companion = WatchCompanionSyncService.shared

    init() {
        companion.onSnapshot = { [weak self] value in self?.snapshot = value }
        companion.onStatus = { [weak self] status in self?.isRefreshing = status == .refreshing }
    }

    var petName: String { snapshot?.petName ?? "Pibo" }
    var stateLabel: String {
        guard let snapshot else { return "等待第一次连接" }
        if let stateDate = snapshot.stateGeneratedAt, stateDate < snapshot.generatedAt {
            return "上次：\(snapshot.stateLabel)"
        }
        return snapshot.stateLabel
    }
    var stateUpdatedAt: Date? { snapshot?.stateGeneratedAt ?? snapshot?.generatedAt }
    var scene: PiboFlatWorldScene { snapshot?.sceneID ?? .rainGorge }
    var growth: PiboCompanionGrowth? { snapshot?.growth }
    var capabilities: [PiboCompanionCapability] { snapshot?.capabilities ?? [] }
    var vectorState: PiboVectorState {
        Self.vectorState(animationID: snapshot?.animationStateID, publicStateID: snapshot?.publicStateID)
    }

    var shadowConnection: PiboCompanionShadowConnection? {
        if let connection = snapshot?.shadowConnection {
            return connection.status == .none || connection.status == .hidden ? nil : connection
        }
        guard let shadow = snapshot?.shadow, shadow.isAcceptable() else { return nil }
        return PiboCompanionShadowConnection(
            status: .active, accountID: "legacy", relationshipID: "legacy",
            displayName: shadow.displayName, snapshot: shadow
        )
    }

    func refresh() {
#if DEBUG
        if let preview = WatchCompanionPreview.snapshotIfRequested() {
            snapshot = preview
            isRefreshing = false
            return
        }
#endif
        if let value = companion.activate() { snapshot = value }
    }

    func syncDescription(now: Date = .now) -> String {
        guard let snapshot else { return "先在 iPhone 打开 Pibo，连接你的健康数据。" }
        let date = snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened)
        return "最近收到：\(date)。暂时未更新时，保留这只 Pibo 和已有成长。"
    }

    func activity(now: Date = .now) -> Activity? {
        if let snapshot, snapshot.hasCurrentActivity(now: now),
           snapshot.activeEnergy != nil || snapshot.exerciseMinutes != nil
            || snapshot.standMinutes != nil || snapshot.standHours != nil {
            return Activity(
                date: snapshot.dayStart,
                activeEnergy: snapshot.activeEnergy,
                exerciseMinutes: snapshot.exerciseMinutes,
                standMinutes: snapshot.standMinutes ?? snapshot.standHours.map { $0 * 60 }
            )
        }
        guard let localActivity, Calendar.current.isDate(localActivity.date, inSameDayAs: now) else { return nil }
        return localActivity
    }

    /// Explicit read-only fallback for today's facts. No authorization prompt on
    /// pet entry, no workouts, and no local derivation of semantic state or bo.
    func readWatchActivity() async {
        guard !isReadingActivity else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            activityMessage = "这台设备暂时无法读取健康数据。"
            return
        }
        isReadingActivity = true
        defer { isReadingActivity = false }
        let start = Calendar.current.startOfDay(for: .now)
        let end = Date()
        do {
            let types: Set<HKObjectType> = [
                HKQuantityType(.activeEnergyBurned), HKQuantityType(.appleExerciseTime), HKQuantityType(.appleStandTime),
            ]
            try await healthStore.requestAuthorization(toShare: [], read: types)
            async let energy = todaySum(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
            async let exercise = todaySum(.appleExerciseTime, unit: .minute(), start: start, end: end)
            async let stand = todaySum(.appleStandTime, unit: .minute(), start: start, end: end)
            let values = await (energy, exercise, stand)
            localActivity = Activity(
                date: start, activeEnergy: values.0,
                exerciseMinutes: values.1.map { Int($0.rounded()) },
                standMinutes: values.2.map { Int($0.rounded()) }
            )
            activityMessage = values.0 == nil && values.1 == nil && values.2 == nil
                ? "还没有可读取的活动记录。可以稍后重试，或在健康设置中检查读取权限。"
                : "活动数字来自手表；Pibo 的状态与成长继续由 iPhone 同步。"
        } catch {
            activityMessage = "暂时无法读取活动数据，请稍后重试。"
        }
    }

    private func todaySum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(identifier),
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .cumulativeSum
            ) { _, result, error in
                guard error == nil else { continuation.resume(returning: nil); return }
                let value = result?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
            }
            healthStore.execute(query)
        }
    }

    /// Asset decoding only: the phone/Core has already selected the semantic ID.
    static func vectorState(animationID: String?, publicStateID: String?) -> PiboVectorState {
        switch animationID {
        case "pibo-state-sleeping-hammock-idle-b": return .sleep_2
        case "pibo-state-sleeping-hammock-idle-a", "pibo-state-sleeping-ground-idle-a": return .sleep_1
        case "pibo-state-waking-hammock-idle", "pibo-state-waking-ground-idle",
             "pibo-state-waking-ground-behavior-recovering": return .awake
        case "pibo-state-tired-forest-idle": return .tired
        case "pibo-state-energetic-forest-idle", "pibo-event-activity-milestone-celebrate": return .muscle
        case "pibo-state-stable-forest-idle": return .default
        default:
            // Compatibility with older phone art identifiers.
            switch publicStateID {
            case "sleeping": return .sleep_1
            case "waking": return .awake
            case "energetic": return .muscle
            case "tired": return .tired
            default: return .default
            }
        }
    }

    static func stateLabel(for publicStateID: String) -> String {
        switch publicStateID {
        case "sleeping": "正在睡觉"
        case "waking": "刚刚醒来"
        case "energetic": "很有精神"
        case "tired": "正在休息"
        case "dataUnknown": "等待健康数据"
        default: "状态平稳"
        }
    }
}

import Foundation
import PiboCore

// The one-line conclusion of today's readout, shared by the badge's status bar
// (decision 062), the readout panel and the footprints diary, so all three always say
// the same thing. The band and the reasons are Core's answers; this only words them,
// and never invents a reading.
//
// Ported from HarmonyPibo `models/WellnessReadout.ets`. HarmonyOS switches on its own
// `HealthAuthState`; iOS's equivalent is `HealthDataService.DataAvailability`, which
// carries the same distinctions (unavailable / needs authorization / checking /
// interrupted) plus "authorized but nothing readable".

enum WellnessReadout {
    /// Today's snapshot, only when it was scored by the current Core algorithm.
    static func snapshot(of record: HealthDayRecord?) -> DailyWellnessSnapshot? {
        guard let snapshot = record?.wellnessSnapshot,
              snapshot.algorithmVersion == PiboCoreWellness.algorithmVersion
        else { return nil }
        return snapshot
    }

    /// Why there is no reading yet, as a title.
    static func unavailableTitle(
        _ snapshot: DailyWellnessSnapshot?,
        availability: HealthDataService.DataAvailability
    ) -> String {
        switch availability {
        case .temporarilyInterrupted:
            return "健康数据暂时中断"
        case .needsAuthorization:
            return "还没有健康数据权限"
        case .unavailable:
            return "当前无法连接健康服务"
        case .checking:
            return "正在检查健康数据"
        case .noReadableData:
            return "暂时读不到健康数据"
        case .available:
            break
        }
        if snapshot?.readinessPrimaryReason == PiboCoreWellnessReadinessReason.missingCurrentSleep.rawValue {
            return "今天的睡眠记录还没到"
        }
        return "个人基线正在建立"
    }

    /// Today's conclusion from Core's readiness band, or why there is none.
    static func conclusion(
        _ snapshot: DailyWellnessSnapshot?,
        availability: HealthDataService.DataAvailability
    ) -> String {
        guard let raw = snapshot?.readinessBand,
              let band = PiboCoreWellnessReadinessBand(rawValue: raw)
        else {
            return unavailableTitle(snapshot, availability: availability)
        }
        switch band {
        case .significantlyBelow: return "今天先放轻一点。"
        case .belowPersonalNormal: return "今天适合轻量活动。"
        case .personalNormal: return "今天按平常节奏就好。"
        case .ample: return "今天的状态很充足。"
        case .unavailable:
            return unavailableTitle(snapshot, availability: availability)
        }
    }

    /// The line under the unavailable title: what happens next.
    static func unavailableDetail(
        _ snapshot: DailyWellnessSnapshot?,
        availability: HealthDataService.DataAvailability
    ) -> String {
        switch availability {
        case .temporarilyInterrupted:
            return "恢复后会自动更新。"
        case .needsAuthorization, .unavailable, .checking, .noReadableData:
            return "连接后才能计算准备度。"
        case .available:
            break
        }
        if snapshot?.readinessPrimaryReason == PiboCoreWellnessReadinessReason.missingCurrentSleep.rawValue {
            return "收到完整记录后会自动计算。"
        }
        let observed = snapshot?.readinessCalibrationDays ?? 0
        let required = snapshot?.readinessRequiredCalibrationDays ?? 7
        return "已记录 \(observed) / \(required) 晚"
    }

    static func bandLabel(_ band: Int32?) -> String {
        guard let band, let value = PiboCoreWellnessReadinessBand(rawValue: band) else {
            return "正在校准"
        }
        switch value {
        case .significantlyBelow: return "明显偏低"
        case .belowPersonalNormal: return "低于个人常态"
        case .personalNormal: return "个人常态"
        case .ample: return "状态充足"
        case .unavailable: return "正在校准"
        }
    }

    static func sleepSufficiencyLabel(_ snapshot: DailyWellnessSnapshot?) -> String {
        guard let value = snapshot?.readinessSleepSufficiency else { return "数据不足" }
        return "\(Int(value.rounded()))%"
    }

    static func loadLabel(_ snapshot: DailyWellnessSnapshot?) -> String {
        guard let raw = snapshot?.readinessLoadStatus,
              let value = PiboCoreWellnessLoadStatus(rawValue: raw)
        else { return "数据不足" }
        switch value {
        case .buildingBaseline: return "正在校准"
        case .belowUsual: return "低于平时"
        case .usual: return "与平时相当"
        case .aboveUsual: return "高于平时"
        case .unavailable: return "数据不足"
        }
    }

    static func reasonLabel(_ reason: Int32?) -> String {
        guard let reason, let value = PiboCoreWellnessReadinessReason(rawValue: reason) else {
            return ""
        }
        switch value {
        case .missingCurrentSleep: return "今天还没有完整的睡眠记录。"
        case .buildingPersonalBaseline: return "个人基线还在建立。"
        case .sleepInsufficient: return "昨晚睡得比需要的少。"
        case .sleepSufficient: return "昨晚睡眠基本够。"
        case .hrvBelowUsual: return "夜间 HRV 低于个人常态。"
        case .hrvUsual: return "夜间 HRV 接近个人常态。"
        case .hrvAboveUsual: return "夜间 HRV 高于个人常态。"
        case .heartRateElevated: return "夜间心率高于个人常态。"
        case .heartRateUsual: return "夜间心率接近个人常态。"
        case .heartRateLowerThanUsual: return "夜间心率低于个人常态。"
        case .temperatureDeviation: return "腕温和个人常态有偏差。"
        case .recentLoadAboveUsual: return "近期身体负荷高于平时。"
        case .recentLoadUsual: return "近期身体负荷与平时相当。"
        case .unavailable: return ""
        }
    }

    /// "基于 N 晚 · H:MM 更新", or that today's data is still on its way.
    static func updatedLabel(_ snapshot: DailyWellnessSnapshot?) -> String {
        guard let generatedAt = snapshot?.generatedAt else { return "等待今天的数据" }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: generatedAt)
        let minute = calendar.component(.minute, from: generatedAt)
        let stamp = String(format: "%d:%02d", hour, minute)
        return "基于 \(snapshot?.readinessCalibrationDays ?? 0) 晚 · \(stamp) 更新"
    }

    /// Today's readiness score, only when Core produced one and health access is live.
    static func readyScore(
        _ snapshot: DailyWellnessSnapshot?,
        availability: HealthDataService.DataAvailability
    ) -> Double? {
        guard availability.hasReliableData else { return nil }
        return snapshot?.readinessScore?.value
    }
}

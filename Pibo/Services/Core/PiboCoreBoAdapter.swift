import Foundation
import PiboCore

/// `HealthDayRecord` → `pibo-core` 的 `bo` 计分输入。
///
/// 这一层只做「翻译」，一条阈值、一个权重都不在 Swift 这边定义 —— `bo` 的计分规则
/// 是 Core 的独占领地（`src/bo.rs`），HarmonyOS 那侧走同一份规则。
///
/// 几条不显然但会影响分数的映射约定：
///
/// - **`mvpaMinutes` 只取 `exerciseMinutes`，绝不叠加 `workoutMinutes`。**
///   Apple 的 `appleExerciseTime` 本身就把运动时段算进去了，两者相加会让做过一次
///   workout 的日子凭空多算一遍中高强度时间。
/// - **睡眠质量指标「测不到就说测不到」。** Core 在一个质量指标都没有时把 quality
///   定为中性的 1.0，而测得的 quality 落在 `[0.80, 1.08]`。手机独占用户的一夜往往
///   是一整块 `asleep`（没有分期、没有 awake 段），此时 `sleepEnd - sleepStart` 几乎
///   等于 `sleepTotal`，算出来的睡眠效率≈100%，会把 quality 顶到接近上限 —— 那是
///   测量假象不是好睡眠。所以只有真的测到了清醒时间才交出 `inBedSeconds`，
///   否则交 `nil` 拿中性分。
/// - **`recoveryLevel` 本轮一律 `nil`。** HRV 那边确实有个人基线 z-score
///   (`PiboCoreDerivedStressAdapter`)，但它的归一化口径和 Core 的 recovery 曲线不是
///   一回事，直接喂进去等于偷偷改了记分板。接它需要单独一轮验证。
enum PiboCoreBoAdapter {

    /// 一天的健康数据翻译成 Core 的计分输入。参数是标量而不是模型对象，好让计分
    /// 映射能脱离 SwiftData 单测（其余 adapter 也是这个风格）。
    ///
    /// - Parameters:
    ///   - awakeSeconds: 这一夜测到的清醒时长。`0` 表示没测到，不表示「睡得很实」。
    ///   - awakeSegmentCount: `sleepSegments` 里的 awake 段数；没有分期数据时传 `nil`。
    ///     有分期但一次没醒，`0` 是真实测量值，要传 `0` 而不是 `nil`。
    ///   - hrv / restingHR: 只用来判定数据来源。这两个指标手机单独拿不到，
    ///     出现即说明当天有手表在写数据。
    static func metrics(
        sleepTotal: TimeInterval,
        sleepDeep: TimeInterval,
        sleepREM: TimeInterval,
        awakeSeconds: TimeInterval,
        awakeSegmentCount: Int?,
        steps: Int,
        exerciseMinutes: Int,
        hrv: Double,
        restingHR: Double
    ) -> PiboCoreBoDailyMetrics {
        PiboCoreBoDailyMetrics(
            sleep: PiboCoreBoSleepMetrics(
                tstSeconds: max(0, sleepTotal),
                inBedSeconds: inBedSeconds(sleepTotal: sleepTotal, awakeSeconds: awakeSeconds),
                deepSeconds: measured(sleepDeep),
                remSeconds: measured(sleepREM),
                // HealthKit 不直接给入睡潜伏期，缺失而不是 0 —— Core 明确区分
                // 「0 秒入睡」和「没测」，传 0 会白送一个满分指标。
                latencySeconds: nil,
                awakenings: awakeSegmentCount
            ),
            steps: Double(max(0, steps)),
            mvpaMinutes: Double(max(0, exerciseMinutes)),
            recoveryLevel: nil,
            source: source(hrv: hrv, restingHR: restingHR)
        )
    }

    /// 计分口径的睡眠机会时长 = 实际睡着 + 测到的清醒。
    ///
    /// 只在真的测到清醒时间时才返回值。理由见类型注释：没测到清醒时段的一夜交出
    /// 效率≈100%，是在奖励一个测量假象。
    private static func inBedSeconds(
        sleepTotal: TimeInterval,
        awakeSeconds: TimeInterval
    ) -> TimeInterval? {
        guard sleepTotal > 0, awakeSeconds > 0 else { return nil }
        return sleepTotal + awakeSeconds
    }

    /// Core 把非正数当作未测量；这里把这个约定显式化成 `nil`，免得依赖 FFI 那层的
    /// 隐式行为。
    private static func measured(_ seconds: TimeInterval) -> TimeInterval? {
        seconds > 0 ? seconds : nil
    }

    /// 数据来源系数：手表 1.0 / 手机 0.8（Core 的默认配置）。
    ///
    /// 判据是「当天有没有只有手表写得出来的指标」。SDNN 与静息心率都需要腕上连续
    /// 采样，iPhone 单独产不出来。故意不返回 `.unknown` —— 它的系数是 1.0，等于把
    /// 手机数据当手表数据算。
    private static func source(hrv: Double, restingHR: Double) -> PiboCoreBoDataSource {
        (hrv > 0 || restingHR > 0) ? .watch : .phone
    }
}

// MARK: - 模型入口

extension PiboCoreBoAdapter {

    /// `HealthDayValues`（HK 抓取的纯值传输体）→ 计分输入。
    static func metrics(for day: HealthDayValues) -> PiboCoreBoDailyMetrics {
        metrics(
            sleepTotal: day.sleepTotal,
            sleepDeep: day.sleepDeep,
            sleepREM: day.sleepREM,
            awakeSeconds: day.sleepAwake,
            awakeSegmentCount: awakeSegmentCount(day.sleepSegments),
            steps: day.steps,
            exerciseMinutes: day.exerciseMinutes,
            hrv: day.hrv,
            restingHR: day.restingHR
        )
    }

    /// 持久化的日记录 → 计分输入。
    static func metrics(for record: HealthDayRecord) -> PiboCoreBoDailyMetrics {
        metrics(
            sleepTotal: record.sleepTotal,
            sleepDeep: record.sleepDeep,
            sleepREM: record.sleepREM,
            awakeSeconds: record.sleepAwake,
            awakeSegmentCount: awakeSegmentCount(record.sleepSegments),
            steps: record.steps,
            exerciseMinutes: record.exerciseMinutes,
            hrv: record.hrv,
            restingHR: record.restingHR
        )
    }

    /// 没有分期数据 → `nil`（未测量）；有分期但没醒过 → `0`（真实测量值）。
    private static func awakeSegmentCount(_ segments: [SleepSegmentValue]) -> Int? {
        guard !segments.isEmpty else { return nil }
        return segments.lazy.filter { $0.stage == .awake }.count
    }
}

import Foundation
import Observation
import PiboCore
import os

/// 账本的完整可持久化状态。整体编码成一份 JSON，字段增删不会像散装 key 那样出现
/// 「一半新一半旧」的中间态。
struct BoLedgerSnapshot: Codable, Equatable, Sendable {
    /// 当前这枚毛的进度，落在 `[0, energyPerBo)`。
    var energyPool: Double = 0
    /// 已成熟、等着用户拔的毛。按设计恒为 0 或 1。
    var ripeCount: Int = 0
    /// 已拔下、可用于兑换的 `bo`。
    var balance: Int = 0
    /// 累计消费，只用于展示与排查。
    var spentTotal: Int = 0
    /// `"yyyy-MM-dd"` → 这一天已经入过账的能量。幂等的来源。
    var grantedEnergyByDay: [String: Double] = [:]
    /// 合作起始日（当天 0 点）。这天之前的健康记录不计入 `bo`。
    var startedOn: Date
    /// 写入时的 Core 计分版本，用于排查跨版本的分数漂移。
    var scoringVersion: UInt32
}

/// 本地优先的 `bo` 账本。
///
/// **规则源是 `pibo-core`**（`PiboCoreBoEconomy`），这里只负责「按什么顺序喂给 Core、
/// 把结果存在哪」。任何阈值、权重、曲线都不在这个文件里。
///
/// 设计上的几条硬约束，改之前先读：
///
/// - **本地优先。** 健康计分全在端上完成，不依赖登录，也不依赖 `pibo-server`
///   （决定 031）。服务端将来只做登录后的合并与校验。
/// - **重算必须幂等。** HealthKit 一天里会反复刷新同一天的记录，所以每天记一个
///   「已入账多少」的书签，重算只补差额。全量重扫历史是安全操作。
/// - **毛熟了就冻结。** `ripeCount >= 1` 时不再入账，但当天的书签照常前移 ——
///   这就是「不拔就不长新毛」。书签前移是关键：否则攒三天不拔、一拔连爆三枚，
///   「不拔」就没有任何成本，规则等于不存在。
/// - **一步最多铸一枚。** 入账前把额度砍到刚好填满当前这枚，
///   免得一个大运动日直接吐出两枚。
/// - **只增不减地对待用户已得。** 版本漂移、数据回滚都不回收已经拔下的 `bo`
///   （决定 027 的精神：低积累可以延后，但不能惩罚、不能剥夺）。
@MainActor
@Observable
final class BoLedgerStore {

    private(set) var state: BoLedgerSnapshot

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistenceKey: String
    @ObservationIgnored private weak var progressFeedback: BoProgressFeedbackStore?

    /// - Parameter startedOn: 期望的合作起始日。**会被夹到「不早于账本创建当天」** ——
    ///   账本永不追溯。
    ///
    ///   这条不是洁癖，是修一个真实的破坏性场景：老用户升级上来时
    ///   `PetIdentityStore.birthDate` 可能是几十天前，首次重算会把这几十天的健康记录
    ///   全扫一遍 —— 第一天就把池子填满铸出一枚，随后「毛没拔就不再入账」的冻结规则
    ///   把剩下所有天的书签一路前移并作废。用户看到的是「几十天的数据只换来一枚」，
    ///   而且书签已经推完，不可恢复。
    ///
    ///   起始日只在账本第一次创建时确定并固化，之后 identity 被重置或 demo 回拨生日
    ///   都不会改变它。
    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = PiboPersistenceKeys.Defaults.boLedger,
        startedOn: Date = Date(),
        progressFeedback: BoProgressFeedbackStore? = nil
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        self.progressFeedback = progressFeedback

        let version = PiboCoreBoEconomy.scoringVersion
        if let data = defaults.data(forKey: persistenceKey),
           let decoded = try? JSONDecoder().decode(BoLedgerSnapshot.self, from: data) {
            self.state = decoded
            if decoded.scoringVersion != version {
                // 故意什么都不做，只记一笔。重扫历史等于白送一堆 `bo`，清空书签
                // 等于事后追缴 —— 两种都比「带着一点分数漂移继续走」更糟。
                LPLog.bo.notice(
                    "scoring version drift \(decoded.scoringVersion, privacy: .public)→\(version, privacy: .public), ledger kept as-is"
                )
                self.state.scoringVersion = version
                persist()
            }
        } else {
            let calendar = Calendar.current
            let resolved = max(
                calendar.startOfDay(for: startedOn),
                calendar.startOfDay(for: Date())
            )
            self.state = BoLedgerSnapshot(startedOn: resolved, scoringVersion: version)
            persist()
            LPLog.bo.notice("ledger created startedOn=\(Self.dayKey(resolved), privacy: .public)")
        }
    }

    // MARK: 展示用派生量

    /// 可兑换余额。
    var balance: Int { state.balance }

    /// 是否有一枚熟了、等着拔。
    var hasRipeBo: Bool { state.ripeCount > 0 }

    /// 当前这枚毛的成熟进度 `[0, 1]`。毛已经熟了但没拔时恒为 1。
    var growthProgress: Double {
        if state.ripeCount > 0 { return 1 }
        let perBo = PiboCoreBoEconomy.energyPerBo
        guard perBo > 0 else { return 0 }
        return min(1, max(0, state.energyPool / perBo))
    }

    // MARK: 入账

    /// 用持久化的健康历史重算账本。安全可重入 —— 每天只补差额。
    func recompute(history: HealthHistoryStore, now: Date = Date()) {
        let records = history.records(from: scanCutoff(now: now), to: now)
        recompute(days: records.map { (day: $0.date, metrics: PiboCoreBoAdapter.metrics(for: $0)) })
    }

    /// 纯计分入口：一组「某天 + 该天的 Core 指标」。
    ///
    /// 调用方不需要自己排序或过滤起始日，这里会做；但**处理顺序必须是从旧到新**，
    /// 因为冻结规则让结果依赖顺序。
    func recompute(days: [(day: Date, metrics: PiboCoreBoDailyMetrics)], now: Date = Date()) {
        let perBo = PiboCoreBoEconomy.energyPerBo
        guard perBo > 0 else {
            LPLog.bo.error("energyPerBo is not positive — skipping recompute")
            return
        }

        let cutoff = scanCutoff(now: now)
        let poolBefore = state.energyPool
        var minted = 0
        var changed = false

        let ordered = days
            .filter { $0.day >= cutoff }
            .sorted { $0.day < $1.day }

        for entry in ordered {
            let key = Self.dayKey(entry.day)
            let target = PiboCoreBoEconomy.scoreDay(entry.metrics).energy
            // 每日封顶已经在 Core 的 `score_day` 里做过了（返回 min(raw, cap)）。
            // 不要再调 `applyDailyCap` —— 那是给增量式喂数据用的，会二次封顶。
            guard target.isFinite, target > 0 else { continue }

            let alreadyGranted = state.grantedEnergyByDay[key] ?? 0
            let delta = target - alreadyGranted
            guard delta > 0 else { continue }

            // 书签无论如何都前移到 target：入了账是「给过了」，冻结期是「作废了」。
            state.grantedEnergyByDay[key] = target
            changed = true

            guard state.ripeCount == 0 else {
                LPLog.bo.debug("day=\(key, privacy: .public) frozen (\(delta, privacy: .public) energy forfeited — bo unplucked)")
                continue
            }

            // 砍到刚好填满当前这枚，保证一步只铸一枚。
            let grantable = min(delta, perBo - state.energyPool)
            guard grantable > 0 else { continue }

            let result = PiboCoreBoEconomy.applyEnergy(
                energyPool: state.energyPool,
                grantedEnergy: grantable
            )
            state.energyPool = result.newEnergyPool
            if result.mintedCount > 0 {
                state.ripeCount += result.mintedCount
                minted += result.mintedCount
            }
        }

        guard changed else { return }
        prunePastBookmarks(now: now)
        persist()

        // 里程碑提示复用已有的队列（25/50/75/90%）。按整轮聚合调一次，
        // 否则一次 30 天回填会连炸 30 下。
        progressFeedback?.recordLedgerUpdate(
            previousEnergyPool: poolBefore,
            newEnergyPool: state.energyPool,
            mintedCount: minted
        )
        if minted > 0 {
            LPLog.bo.notice("minted=\(minted, privacy: .public) ripe=\(self.state.ripeCount, privacy: .public)")
        }
    }

    // MARK: 用户动作

    /// 拔下一枚成熟的毛。没有成熟的毛时返回 `false`，不改任何状态。
    @discardableResult
    func pluck() -> Bool {
        guard state.ripeCount > 0 else { return false }
        state.ripeCount -= 1
        state.balance += 1
        persist()
        LPLog.bo.notice("plucked → balance=\(self.state.balance, privacy: .public)")
        return true
    }

    /// 花掉 `cost` 枚 `bo`。余额不足时返回 `false` 且不扣。
    @discardableResult
    func spend(_ cost: Int) -> Bool {
        guard cost > 0, state.balance >= cost else { return false }
        state.balance -= cost
        state.spentTotal += cost
        persist()
        LPLog.bo.notice("spent=\(cost, privacy: .public) → balance=\(self.state.balance, privacy: .public)")
        return true
    }

    /// 清空账本，重新以 `startedOn` 起算。接在「重置」链路上。
    func reset(startedOn: Date = Date()) {
        state = BoLedgerSnapshot(
            startedOn: Calendar.current.startOfDay(for: startedOn),
            scoringVersion: PiboCoreBoEconomy.scoringVersion
        )
        persist()
        LPLog.bo.notice("ledger reset")
    }

    #if DEBUG
    /// 免真实健康数据地把账本摆到某个状态，用于模拟器验证。
    func debugSet(balance: Int? = nil, ripe: Int? = nil, progress: Double? = nil) {
        if let balance { state.balance = max(0, balance) }
        if let ripe { state.ripeCount = max(0, ripe) }
        if let progress {
            state.energyPool = PiboCoreBoEconomy.energyPerBo * min(1, max(0, progress))
        }
        persist()
    }
    #endif

    // MARK: 内部

    /// 重算要考虑的最早一天。
    ///
    /// **扫描窗口和书签保留期必须是同一个值。** 这两者一旦不一致就会出事：书签被修剪
    /// 掉、而那一天仍在扫描范围内，账本就查不到「这天给过了」，于是每次重算都重新发一遍。
    /// 用一个来源统一它们，从构造上排除这种漂移。
    ///
    /// 400 天 > 一年，远超 HealthKit 自己 35 天的回填窗口 —— 要让某一天掉出窗口，得
    /// 一年多不打开 App，那时「毛没拔就不长新的」的冻结规则早就先起作用了。
    private static let scanWindowDays = 400

    private func scanCutoff(now: Date) -> Date {
        let calendar = Calendar.current
        let earliest = calendar.date(
            byAdding: .day, value: -Self.scanWindowDays, to: calendar.startOfDay(for: now)
        ) ?? state.startedOn
        return max(state.startedOn, earliest)
    }

    /// 丢掉窗口之外的书签。窗口内的一条都不能丢 —— 见 `scanCutoff` 的注释。
    private func prunePastBookmarks(now: Date) {
        let cutoff = Self.dayKey(scanCutoff(now: now))
        let pruned = state.grantedEnergyByDay.filter { $0.key >= cutoff }
        guard pruned.count != state.grantedEnergyByDay.count else { return }
        state.grantedEnergyByDay = pruned
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: persistenceKey)
    }

    /// 固定 gregorian / POSIX，免得用户切日历或地区之后同一天算成两天。
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}

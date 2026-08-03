import Foundation
import PiboCore
import Testing
@testable import Pibo

/// 账本的规则测试。计分本身归 `pibo-core` 管（那边有 golden parity），这里钉的是
/// App 侧决定的四件事：幂等、冻结、单步只铸一枚、已得不可回收。
@Suite(.serialized)
@MainActor
struct BoLedgerTests {

    // MARK: 夹具

    private func makeLedger(
        startedOn: Date,
        feedback: BoProgressFeedbackStore? = nil
    ) throws -> (BoLedgerStore, UserDefaults, String) {
        let suite = "BoLedgerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = BoLedgerStore(
            defaults: defaults,
            persistenceKey: "test.ledger",
            startedOn: startedOn,
            progressFeedback: feedback
        )
        return (store, defaults, suite)
    }

    /// 一个足够好的一天：能量必然大于 0，具体数值由 Core 决定，测试不假设它。
    /// 注意封顶 110 > 每枚 75，所以**一个满勤日足以当场熟一枚** —— 断言不要写成
    /// 「跑一天池子里应该还剩点什么」。
    private func goodDay(steps: Int = 12_000, sleepHours: Double = 8) -> PiboCoreBoDailyMetrics {
        PiboCoreBoAdapter.metrics(
            sleepTotal: sleepHours * 3600,
            sleepDeep: 1.5 * 3600,
            sleepREM: 1.6 * 3600,
            awakeSeconds: 20 * 60,
            awakeSegmentCount: 2,
            steps: steps,
            exerciseMinutes: 45,
            hrv: 42,
            restingHR: 58
        )
    }

    /// 一个普通的一天，能量明显不足以一次熟一枚 —— 用来观察逐步累积的过程。
    private func modestDay() -> PiboCoreBoDailyMetrics {
        PiboCoreBoAdapter.metrics(
            sleepTotal: 5.5 * 3600,
            sleepDeep: 0.6 * 3600,
            sleepREM: 0.7 * 3600,
            awakeSeconds: 35 * 60,
            awakeSegmentCount: 4,
            steps: 3_000,
            exerciseMinutes: 0,
            hrv: 0,
            restingHR: 0
        )
    }

    private func day(_ offsetDays: Int, from anchor: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: offsetDays, to: anchor) ?? anchor
    }

    // MARK: 幂等

    @Test func recomputingTheSameDayTwiceGrantsOnce() throws {
        let start = Calendar.current.startOfDay(for: Date())
        let (ledger, defaults, suite) = try makeLedger(startedOn: start)
        defer { defaults.removePersistentDomain(forName: suite) }

        ledger.recompute(days: [(day: start, metrics: modestDay())])
        let after = ledger.state

        ledger.recompute(days: [(day: start, metrics: modestDay())])
        // 第二遍必须完全无副作用 —— 池子、成熟数、余额、书签一个都不能动。
        #expect(ledger.state == after)
    }

    @Test func aDayThatGrowsLaterGrantsOnlyTheDifference() throws {
        let start = Calendar.current.startOfDay(for: Date())
        let (ledger, defaults, suite) = try makeLedger(startedOn: start)
        defer { defaults.removePersistentDomain(forName: suite) }

        ledger.recompute(days: [(day: start, metrics: goodDay(steps: 3_000, sleepHours: 5))])
        let partial = ledger.state.energyPool

        // 同一天后来走得更多 —— 只补差额，不重复入账。
        ledger.recompute(days: [(day: start, metrics: goodDay(steps: 14_000, sleepHours: 5))])
        let full = ledger.state.energyPool
        #expect(full > partial)

        let expected = PiboCoreBoEconomy
            .scoreDay(goodDay(steps: 14_000, sleepHours: 5)).energy
        #expect(abs(full - expected) < 0.001)
    }

    // MARK: 冻结（不拔就不长新毛）

    @Test func noEnergyIsGrantedWhileABoIsRipeAndTheBookmarkStillAdvances() throws {
        let start = Calendar.current.startOfDay(for: Date())
        let (ledger, defaults, suite) = try makeLedger(startedOn: start)
        defer { defaults.removePersistentDomain(forName: suite) }

        // 每日封顶 110 > 每枚 75，所以一个满勤日就能熟一枚。
        ledger.recompute(days: [(day: start, metrics: goodDay())])
        #expect(ledger.hasRipeBo)

        let poolWhenRipe = ledger.state.energyPool

        // 熟了之后继续过好日子 —— 池子不动。
        let frozenDay = day(10, from: start)
        ledger.recompute(days: [(day: frozenDay, metrics: goodDay())])
        #expect(ledger.state.energyPool == poolWhenRipe)
        #expect(ledger.state.ripeCount == 1)

        // 关键：书签仍然前移了。拔完之后那一天不会被重新兑现，
        // 否则「攒着不拔」就没有成本。
        let key = BoLedgerStore.dayKey(frozenDay)
        #expect((ledger.state.grantedEnergyByDay[key] ?? 0) > 0)

        #expect(ledger.pluck())
        ledger.recompute(days: [(day: frozenDay, metrics: goodDay())])
        #expect(ledger.state.energyPool == poolWhenRipe)
        #expect(ledger.balance == 1)
    }

    @Test func pluckingResumesGrowthOnFreshDays() throws {
        let start = Calendar.current.startOfDay(for: Date())
        let (ledger, defaults, suite) = try makeLedger(startedOn: start)
        defer { defaults.removePersistentDomain(forName: suite) }

        ledger.recompute(days: [(day: start, metrics: goodDay())])
        #expect(ledger.hasRipeBo)
        #expect(ledger.pluck())

        let poolAfterPluck = ledger.state.energyPool
        ledger.recompute(days: [(day: day(20, from: start), metrics: modestDay())])
        // 拔完之后，新的一天重新开始长 —— 不看具体数值，只要求确实动了。
        #expect(ledger.state.energyPool > poolAfterPluck || ledger.hasRipeBo)
    }

    // MARK: 单步只铸一枚

    @Test func aSingleHugeDayMintsAtMostOneBo() throws {
        let start = Calendar.current.startOfDay(for: Date())
        let (ledger, defaults, suite) = try makeLedger(startedOn: start)
        defer { defaults.removePersistentDomain(forName: suite) }

        // 池子先顶到差一点点满，再来一整天封顶能量。
        let perBo = PiboCoreBoEconomy.energyPerBo
        ledger.debugSet(progress: (perBo - 1) / perBo)
        #expect(ledger.state.energyPool > perBo - 1.001)

        ledger.recompute(days: [(day: start, metrics: goodDay(steps: 30_000, sleepHours: 8))])
        #expect(ledger.state.ripeCount == 1)
        #expect(ledger.state.energyPool < perBo)
    }

    // MARK: 起始日与消费

    @Test func recordsBeforeTheStartDateAreIgnored() throws {
        let start = Calendar.current.startOfDay(for: Date())
        let (ledger, defaults, suite) = try makeLedger(startedOn: start)
        defer { defaults.removePersistentDomain(forName: suite) }

        ledger.recompute(days: [(day: day(-5, from: start), metrics: goodDay())])
        #expect(ledger.state.energyPool == 0)
        #expect(ledger.state.grantedEnergyByDay.isEmpty)
    }

    /// 账本永不追溯：即使传进来一个很早的起始日，也夹到创建当天。
    ///
    /// 这一条挡的是升级路径上的破坏性场景 —— 老用户的「相识第 N 天」可能在几十天前，
    /// 追溯扫描会在第一天就铸出一枚，然后冻结规则把余下所有天的书签一路推完并作废，
    /// 用户看到的是「几十天只换来一枚」且不可恢复。
    @Test func theLedgerNeverStartsRetroactively() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let (ledger, defaults, suite) = try makeLedger(startedOn: day(-54, from: today))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ledger.state.startedOn == today)

        // 54 天的历史一股脑喂进来，只有今天这一天该被计入。
        var history: [(day: Date, metrics: PiboCoreBoDailyMetrics)] = []
        for offset in -54...0 {
            history.append((day: day(offset, from: today), metrics: goodDay()))
        }
        ledger.recompute(days: history)
        #expect(ledger.state.grantedEnergyByDay.count == 1)
        #expect(ledger.state.grantedEnergyByDay[BoLedgerStore.dayKey(today)] != nil)
    }

    @Test func spendingFailsWithoutEnoughBalanceAndNeverDeducts() throws {
        let start = Calendar.current.startOfDay(for: Date())
        let (ledger, defaults, suite) = try makeLedger(startedOn: start)
        defer { defaults.removePersistentDomain(forName: suite) }

        ledger.debugSet(balance: 3)
        #expect(ledger.spend(8) == false)
        #expect(ledger.balance == 3)
        #expect(ledger.state.spentTotal == 0)

        #expect(ledger.spend(3))
        #expect(ledger.balance == 0)
        #expect(ledger.state.spentTotal == 3)
    }

    @Test func pluckingWithoutARipeBoChangesNothing() throws {
        let start = Calendar.current.startOfDay(for: Date())
        let (ledger, defaults, suite) = try makeLedger(startedOn: start)
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ledger.pluck() == false)
        #expect(ledger.balance == 0)
    }

    /// 扫描窗口和书签保留期必须一致。
    ///
    /// 两者不一致时的故障是：书签被修掉、而那一天仍在扫描范围内，于是账本查不到
    /// 「这天给过了」，**每次重算都重新发一遍** —— 一个会反复触发的凭空发钱。
    @Test func daysOutsideTheScanWindowAreNeverRegranted() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let (ledger, defaults, suite) = try makeLedger(startedOn: today)
        defer { defaults.removePersistentDomain(forName: suite) }

        ledger.recompute(days: [(day: today, metrics: modestDay())])
        let afterFirst = ledger.state.energyPool
        #expect(afterFirst > 0)

        // 500 天后再算同一天：它已经掉出扫描窗口，不该再产生任何入账。
        let later = day(500, from: today)
        ledger.recompute(days: [(day: today, metrics: modestDay())], now: later)
        #expect(ledger.state.energyPool == afterFirst)
        #expect(!ledger.hasRipeBo)

        // 再来一次也一样 —— 这条不成立的话就是每次重算发一遍。
        ledger.recompute(days: [(day: today, metrics: modestDay())], now: later)
        #expect(ledger.state.energyPool == afterFirst)
    }

    // MARK: 持久化

    @Test func stateSurvivesARelaunchAndStartDateStaysFrozen() throws {
        let start = Calendar.current.startOfDay(for: Date())
        let (ledger, defaults, suite) = try makeLedger(startedOn: start)
        defer { defaults.removePersistentDomain(forName: suite) }

        ledger.recompute(days: [(day: start, metrics: goodDay())])
        ledger.debugSet(balance: 5)
        let pool = ledger.state.energyPool

        // 第二次构造传了一个更早的起始日 —— 不该被采纳，否则 demo 回拨生日
        // 会让历史被追溯补发。
        let restored = BoLedgerStore(
            defaults: defaults,
            persistenceKey: "test.ledger",
            startedOn: day(-30, from: start)
        )
        #expect(restored.balance == 5)
        #expect(abs(restored.state.energyPool - pool) < 0.001)
        #expect(restored.state.startedOn == start)
    }

    // MARK: 与里程碑提示的接线

    @Test func recomputeFeedsTheProgressFeedbackQueueOnce() throws {
        let start = Calendar.current.startOfDay(for: Date())
        let feedbackSuite = "BoLedgerFeedback.\(UUID().uuidString)"
        let feedbackDefaults = try #require(UserDefaults(suiteName: feedbackSuite))
        defer { feedbackDefaults.removePersistentDomain(forName: feedbackSuite) }
        let feedback = BoProgressFeedbackStore(defaults: feedbackDefaults)

        let (ledger, defaults, suite) = try makeLedger(startedOn: start, feedback: feedback)
        defer { defaults.removePersistentDomain(forName: suite) }

        // 逐天累积，总会跨过 25/50/75/90 里的某一档。不假设具体是哪天跨的 ——
        // 那是 Core 的曲线说了算。
        var sawMilestone = false
        for offset in 0..<8 {
            ledger.recompute(days: [(day: day(offset, from: start), metrics: modestDay())])
            if feedback.pending != nil { sawMilestone = true }
            if ledger.hasRipeBo { break }
        }
        #expect(sawMilestone)

        // 铸成之后，那条「正在形成」的提示应该被作废 —— 毛已经熟了，
        // 再提示「87% 了」是错的。
        ledger.recompute(days: [(day: day(9, from: start), metrics: goodDay())])
        if ledger.hasRipeBo {
            #expect(feedback.pending == nil)
        }
    }

    #if DEBUG
    @Test func debugWorkoutAdvancesTheLedgerWithCoreScoring() throws {
        let start = Calendar.current.startOfDay(for: Date())
        let (ledger, defaults, suite) = try makeLedger(startedOn: start)
        defer { defaults.removePersistentDomain(forName: suite) }

        let metrics = PiboCoreBoAdapter.metrics(
            sleepTotal: 0,
            sleepDeep: 0,
            sleepREM: 0,
            awakeSeconds: 0,
            awakeSegmentCount: nil,
            steps: 0,
            exerciseMinutes: 24,
            hrv: 0,
            restingHR: 0
        )
        let scoredEnergy = PiboCoreBoEconomy.scoreDay(metrics).energy
        let grantable = min(scoredEnergy, PiboCoreBoEconomy.energyPerBo)
        let expected = PiboCoreBoEconomy.applyEnergy(
            energyPool: 0,
            grantedEnergy: grantable
        )

        ledger.debugApplyWorkout(durationMinutes: 24)

        #expect(scoredEnergy > 0)
        #expect(abs(ledger.state.energyPool - expected.newEnergyPool) < 0.001)
        #expect(ledger.state.ripeCount == expected.mintedCount)
    }
    #endif
}

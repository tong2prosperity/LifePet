import Foundation
import Observation
import os

/// 物件身上被用户亲手点亮的那些灯。
///
/// 和 `OrnamentUnlockStore` 分开的理由和它自己那条一样，只是方向相反：解锁是既成
/// 事实、只增不减；点亮是**每天作废一次**的临时状态。混在一份存储里，任何一次
/// 「今天的灯该灭了」都会有机会顺手抹掉用户已经换到的物件。
///
/// 语义（决定 013 / 014）：
/// - 只能点亮，**不能点灭**。给用户一个「关掉 Pibo 的灯」的操作没有故事价值。
/// - 点亮**不产生任何收益** —— 不给 `bo`、不给能量、不解锁。决定 013 写死了这一条，
///   而「点一下灯」正是最容易被顺手挂上奖励的那种交互。别挂。
/// - 一盏灯亮到**下一次天亮**为止。半夜两点点的灯几小时后就灭（属于前一个点灯日），
///   下午两点点的灯要到第二天早上才灭。两句话是同一条规则。
@MainActor
@Observable
final class OrnamentLightStore {

    /// 物件 → 已点亮的灯下标。下标的含义由 `PiboOrnament.Placement.lights` 的顺序
    /// 决定，所以那个数组只能追加不能重排。
    private(set) var lit: [PiboOrnament.ID: Set<Int>] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    /// 当前这批灯属于哪个点灯日。`nil` = 一盏没点。
    @ObservationIgnored private var litDay: Date?

    private struct Payload: Codable {
        var day: Date
        var lit: [String: [Int]]
    }

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) {
        self.defaults = defaults
        self.calendar = calendar

        if let data = defaults.data(forKey: PiboPersistenceKeys.Defaults.boOrnamentLights),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            litDay = payload.day
            lit = payload.lit.reduce(into: [:]) { result, entry in
                guard let id = PiboOrnament.ID(rawValue: entry.key), !entry.value.isEmpty else { return }
                result[id] = Set(entry.value)
            }
        }
        // 进程刚起来就先对一次日子。冷启动往往正是跨过了一个天亮 —— 昨晚点的灯
        // 不能因为「没人在场看着它熄」就一直亮到明天。
        refresh(now: now)
    }

    func isLit(_ id: PiboOrnament.ID, index: Int) -> Bool {
        lit[id]?.contains(index) ?? false
    }

    /// 点亮一盏。已经亮着就什么都不做 —— 重复点不该重放动画，也不该写一次存储。
    /// 返回是否真的发生了变化，调用方据此决定要不要给触觉反馈。
    @discardableResult
    func light(_ id: PiboOrnament.ID, index: Int, now: Date = Date()) -> Bool {
        refresh(now: now)
        guard id == .lantern,
              let placement = PiboOrnament.ornament(id)?.placement,
              placement.lights.indices.contains(index)
        else { return false }
        guard !isLit(id, index: index) else { return false }
        lit[id, default: []].insert(index)
        litDay = Self.lightingDay(at: now, calendar: calendar)
        persist()
        LPLog.bo.notice(
            "ornament light on=\(id.rawValue, privacy: .public) index=\(index, privacy: .public)"
        )
        return true
    }

    /// 跨过天亮就把灯全部熄掉。前台恢复、环境时钟走动时都该调一次 —— 它自己判断
    /// 要不要动，重复调用是廉价的。
    func refresh(now: Date = Date()) {
        guard let litDay else { return }
        let current = Self.lightingDay(at: now, calendar: calendar)
        guard current != litDay else { return }
        guard !lit.isEmpty else {
            self.litDay = nil
            persist()
            return
        }
        lit.removeAll()
        self.litDay = nil
        persist()
        LPLog.bo.notice("ornament lights expired at daybreak")
    }

    func reset() {
        guard litDay != nil || !lit.isEmpty else { return }
        lit.removeAll()
        litDay = nil
        persist()
    }

    /// 「点灯日」以**天亮**为界，不是以午夜为界。
    ///
    /// 日出的钟点属于 Core 的时段规则（`pibo_resolve_day_phase`），不在 Swift 里
    /// 另写一个常量 —— 那正是 CLAUDE.md 点名不要复制的东西。这里只用一个不依赖
    /// 具体钟点的事实：**中午之前 Core 仍判为 `.night` 的时刻，一定是前一夜的
    /// 尾巴**（`.morning` 的参考钟点是 6.5，`.day` 是 12）。所以边界跟着 Core 走，
    /// Core 改了日出时间这里不用动。
    nonisolated static func lightingDay(at date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(components.hour ?? 12) + Double(components.minute ?? 0) / 60
        let isBeforeDaybreak = hour < 12 && PiboDayPhase.resolve(hour: hour) == .night
        guard isBeforeDaybreak else { return startOfDay }
        return calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
    }

    private func persist() {
        let key = PiboPersistenceKeys.Defaults.boOrnamentLights
        guard let litDay, !lit.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        let payload = Payload(
            day: litDay,
            lit: lit.reduce(into: [:]) { result, entry in
                result[entry.key.rawValue] = entry.value.sorted()
            }
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
    }

    #if DEBUG
    /// 截图验证用：没法在模拟器里合成点击，所以逐灯状态要能从启动参数进来。
    /// `-PiboLanternLit=0,2` 点亮第 0 和第 2 个铃铛。
    func applyDebugLaunchArguments(_ arguments: [String], now: Date = Date()) {
        guard let raw = arguments.first(where: { $0.hasPrefix("-PiboLanternLit=") })?
            .split(separator: "=", maxSplits: 1).last else { return }
        let indices = raw.split(separator: ",").compactMap { Int($0) }
        for index in indices { light(.lantern, index: index, now: now) }
    }
    #endif
}

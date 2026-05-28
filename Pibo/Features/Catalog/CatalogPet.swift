import Foundation

/// Static demo dataset for the 图鉴 tab. Mirrors the four pets in
/// `原型-02-图鉴.html` so the screen has a body even before a real death-log
/// store exists. When the lifecycle bookkeeping ships, replace `CatalogPet.demo`
/// with a backing store fed by `PetStateStore`'s daily snapshots.
struct CatalogPet: Identifiable, Equatable, Hashable {
    let id: String                // "bean", "blob", "noct", "hush"
    let name: String              // "BEAN"
    let sprite: PetSprite
    let isAlive: Bool
    let deathType: DeathType?     // nil for alive
    let dates: String             // "4/19 → 今日"
    let days: Int                 // for alive: days lived so far; for dead: == totalDays
    let totalDays: Int            // full lifespan for dead, current days for alive
    let stats: Stats              // current stats (alive) or lifetime average (dead)
    let series: Series            // per-day stat values, length == totalDays
    let moments: [Moment]
    let bio: String
    let memorialTitle: String?    // nil for alive
    let memorialDuration: String? // "0:45"
    let isRare: Bool              // explicit per the prototype — not derived from days

    struct Stats: Equatable, Hashable {
        let vitality: Int
        let energy: Int
        let mood: Int
    }

    struct Series: Equatable, Hashable {
        let vitality: [Int]
        let energy: [Int]
        let mood: [Int]
    }

    struct Moment: Identifiable, Equatable, Hashable {
        let day: Int          // D-day, 1-indexed (also serves as Identifiable id within a pet)
        let title: String
        let value: String?    // optional metric ("HRV +28") rendered to the right
        let isDeath: Bool

        var id: Int { day }
    }

    /// Maps to PRD §6 death triggers. Sorted by light-handed copy → severe.
    enum DeathType: Equatable, Hashable {
        case natural   // 圆满: 寿终正寝 / 长寿奖励
        case chronic   // 慢性死: 10 天零运动
        case acute     // 急性死: 心情 < 30 连续 7 天
        case starve    // 饿死: 基础能量 7 天不补
        case illness   // 急病死: 任一状态 = 0 超 48h

        /// Tag copy + day-count format for the past-grid sticker.
        var tagPrefix: String {
            switch self {
            case .natural: return "圆满"
            case .chronic, .starve: return "短命"
            case .acute, .illness: return "短命"
            }
        }
    }
}

// MARK: - Tag chip

extension CatalogPet {
    /// Visual chips shown on the detail hero. Tag identity drives chip color.
    enum Tag: Equatable, Hashable {
        case rare        // coral fill
        case dead        // ink fill ("已升天")
        case plain(String) // paper + ink border

        var label: String {
            switch self {
            case .rare:        return "RARE"
            case .dead:        return "已升天"
            case .plain(let s): return s
            }
        }
    }

    var tags: [Tag] {
        var out: [Tag] = []
        if isAlive {
            out.append(.plain("LIVE"))
            out.append(.plain("养育中"))
        } else {
            if isRare { out.append(.rare) }
            switch deathType {
            case .natural:
                out.append(.plain("圆满"))
            case .chronic, .starve, .acute, .illness:
                out.append(.plain("短命"))
            case .none:
                break
            }
            out.append(.dead)
        }
        return out
    }

    /// Short tag used on past-grid stickers ("圆满 · 21 天").
    var pastGridTag: String {
        guard let dt = deathType else { return "" }
        return "\(dt.tagPrefix) · \(totalDays) 天"
    }

    /// Color bucket for the past-grid sticker tint.
    enum DeathBucket { case natural, chronic, acute }

    var deathBucket: DeathBucket {
        switch deathType {
        case .natural:   return .natural
        case .acute, .illness: return .acute
        case .chronic, .starve, .none: return .chronic
        }
    }
}

// MARK: - Demo dataset

extension CatalogPet {
    /// Fixed demo set matching `原型-02-图鉴.html`. BEAN's `series` aligns with
    /// the 7-day arc the home screen tells; the other three are historical.
    static let demo: [CatalogPet] = [bean, blob, noct, hush]

    static let bean = CatalogPet(
        id: "bean",
        name: "BEAN",
        sprite: .bean,
        isAlive: true,
        deathType: nil,
        dates: "4/19 → 今日",
        days: 7,
        totalDays: 7,
        stats: .init(vitality: 88, energy: 74, mood: 82),
        series: .init(
            vitality: [45, 58, 70, 75, 82, 85, 88],
            energy:   [65, 70, 68, 60, 74, 70, 74],
            mood:     [70, 65, 75, 80, 78, 80, 82]
        ),
        moments: [
            .init(day: 1, title: "破壳了，深呼吸 30 秒孵的", value: nil, isDeath: false),
            .init(day: 3, title: "首次达到 EXCITED 状态", value: "体力 82", isDeath: false),
            .init(day: 5, title: "心情达今日峰值", value: "HRV +28", isDeath: false),
            .init(day: 7, title: "今天，它还在陪着你", value: "状态良好", isDeath: false),
        ],
        bio: "它是四月中旬来的那只。你刚跑完步的时候它跳得最高，你工作开会的时候它就安静地守着。它还年轻，还在学你的节奏。",
        memorialTitle: nil,
        memorialDuration: nil,
        isRare: false
    )

    static let blob = CatalogPet(
        id: "blob",
        name: "BLOB",
        sprite: .blob,
        isAlive: false,
        deathType: .natural,
        dates: "3/29 → 4/18",
        days: 21,
        totalDays: 21,
        stats: .init(vitality: 71, energy: 65, mood: 74),
        series: .init(
            vitality: [45, 52, 68, 75, 82, 88, 85, 78, 82, 90, 88, 75, 60, 45, 42, 50, 65, 72, 78, 75, 68],
            energy:   [60, 55, 62, 70, 75, 80, 78, 72, 68, 70, 65, 58, 50, 45, 55, 65, 70, 72, 75, 70, 65],
            mood:     [55, 62, 70, 75, 80, 85, 88, 82, 78, 82, 85, 75, 65, 40, 42, 58, 72, 80, 85, 82, 75]
        ),
        moments: [
            .init(day: 3,  title: "首次 EXCITED", value: "体力 75", isDeath: false),
            .init(day: 7,  title: "三状态全 >80", value: "24h 持续", isDeath: false),
            .init(day: 10, title: "全生命期最巅峰", value: "综合 95", isDeath: false),
            .init(day: 14, title: "SICK 突变", value: "心情 40 ↓", isDeath: false),
            .init(day: 18, title: "你开始冥想 → 好起来", value: "心情 85", isDeath: false),
            .init(day: 21, title: "圆满升天", value: nil, isDeath: true),
        ],
        bio: "你送走了它。它最喜欢你早晨跑步那段——那是它最活跃的节奏。4/11 你压力很大的那天，它生病了；后来好起来，就在你第一次冥想的第二天。它活成了你那段时间的样子。",
        memorialTitle: "《纪念曲 · 圆满》",
        memorialDuration: "0:15",
        isRare: true
    )

    static let noct = CatalogPet(
        id: "noct",
        name: "NOCT",
        sprite: .noct,
        isAlive: false,
        deathType: .chronic,
        dates: "3/15 → 3/28",
        days: 14,
        totalDays: 14,
        stats: .init(vitality: 20, energy: 20, mood: 33),
        series: .init(
            vitality: [50, 45, 38, 30, 25, 22, 18, 15, 12, 8, 5, 3, 2, 0],
            energy:   [40, 35, 30, 28, 25, 22, 20, 18, 15, 12, 10, 8, 5, 3],
            mood:     [55, 50, 45, 40, 38, 35, 32, 30, 28, 25, 22, 20, 18, 15]
        ),
        moments: [
            .init(day: 1,  title: "破壳",                  value: "状态 50",     isDeath: false),
            .init(day: 4,  title: "警告 · 4 天零运动",      value: "体力 30 ↓",   isDeath: false),
            .init(day: 8,  title: "体力跌破 15",            value: "TIRED 常态", isDeath: false),
            .init(day: 11, title: "饱食度 0",              value: "持续危险",   isDeath: false),
            .init(day: 14, title: "慢性死 · 10 天零运动",   value: "体力 0",     isDeath: true),
        ],
        bio: "NOCT 只活了 14 天。它从没见过早晨的太阳——你总在凌晨才睡，醒来直接坐到电脑前。它等了很久，你始终没动。慢慢地，它懒得再动。被你熬死的第 3 只。",
        memorialTitle: "《纪念曲 · 沉寂》",
        memorialDuration: "0:15",
        isRare: false
    )

    static let hush = CatalogPet(
        id: "hush",
        name: "HUSH",
        sprite: .hush,
        isAlive: false,
        deathType: .natural,
        dates: "2/15 → 3/7",
        days: 21,
        totalDays: 21,
        stats: .init(vitality: 61, energy: 79, mood: 71),
        series: .init(
            vitality: [60, 62, 58, 60, 65, 62, 60, 58, 62, 65, 60, 62, 65, 60, 58, 62, 65, 62, 60, 58, 62],
            energy:   [75, 78, 80, 75, 78, 80, 82, 80, 78, 80, 82, 78, 75, 78, 80, 82, 80, 78, 82, 80, 78],
            mood:     [68, 70, 72, 70, 75, 72, 70, 68, 70, 72, 75, 72, 70, 68, 72, 75, 72, 70, 72, 70, 68]
        ),
        moments: [
            .init(day: 1,  title: "稳定开端",              value: "状态 68",   isDeath: false),
            .init(day: 8,  title: "连续 5 天冥想 · 心情峰值", value: "心情 75", isDeath: false),
            .init(day: 15, title: "最长连续睡眠",           value: "8h 12m",   isDeath: false),
            .init(day: 21, title: "从未 SICK · 平静升天",   value: nil,        isDeath: true),
        ],
        bio: "HUSH 是最平静的那只——没有大起大落，也从未病过。它活出了稳定的样子：早睡、冥想、温和地运动。你那段时间正在休长假，它就顺着你的节奏慢慢过完了 21 天。",
        memorialTitle: "《纪念曲 · 静水》",
        memorialDuration: "0:15",
        isRare: false
    )
}

// MARK: - Live overlay

extension CatalogPet {
    /// For the alive pet (BEAN), replace `name / days / totalDays / stats` with
    /// current values from `PetStateStore`; everything else (sprite, dates,
    /// series, moments, bio) keeps its authored value. Series + moments need a
    /// per-day snapshot log we don't have yet, so they stay static for now.
    /// No-op for dead pets — those are read-only history.
    func liveOverlay(from store: PetStateStore) -> CatalogPet {
        guard isAlive else { return self }
        func stat(_ kind: StatKind) -> Int {
            store.stats.first(where: { $0.kind == kind })?.value ?? 0
        }
        return CatalogPet(
            id: id,
            name: store.petName,
            sprite: sprite,
            isAlive: true,
            deathType: nil,
            dates: dates,
            days: store.dayCount,
            totalDays: store.dayCount,
            stats: .init(
                vitality: stat(.vitality),
                energy:   stat(.energy),
                mood:     stat(.mood)
            ),
            series: series,
            moments: moments,
            bio: bio,
            memorialTitle: nil,
            memorialDuration: nil,
            isRare: isRare
        )
    }
}

// MARK: - Catalog summary

/// Aggregate counts shown in the grid header + footer + stat chips.
struct CatalogSummary {
    let pets: [CatalogPet]

    var aliveCount: Int       { pets.filter(\.isAlive).count }
    var naturalCount: Int     { pets.filter { !$0.isAlive && $0.deathType == .natural }.count }
    var earlyCount: Int       { pets.filter { !$0.isAlive && $0.deathType != .natural }.count }
    var totalCount: Int       { pets.count }
    var totalDays: Int        { pets.reduce(0) { $0 + $1.totalDays } }
}

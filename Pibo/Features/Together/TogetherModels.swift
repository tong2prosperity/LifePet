import Foundation

// MARK: - Friend (双人空间)

/// One pairing the user maintains — their friend / family / partner, plus the
/// other person's pet. Mirrors `SPACES[*]` in `原型-03-一起.html`.
///
/// All values here are mock — there's no real syncing partner, no shared
/// HealthKit data, no message backend. The "你" side reads from the user's
/// `PetStateStore` only for the LCD pet sprite + name; the rest of the "you"
/// numbers in the compare card stay mock so the demo lines up consistently.
struct Friend: Identifiable, Hashable {
    let id: String
    /// What the user calls them — "鱼" / "妈妈" / "阿杰".
    let displayName: String
    /// Their pet's catalog name — "NOVA" / "BUTTON" / "ZIP".
    let petName: String
    let sprite: PetSprite
    /// Relationship label rendered as the small coral pill — "异地恋" / "家人" / "挚友".
    let relation: String
    /// Days the pair has been linked. Drives the big "245 天 · 一起" header.
    let daysTogether: Int
    /// Short status copy under each pet on the twin stage.
    let myStatus: String
    let otherStatus: String
    /// 5-row health-compare table, one column per side.
    let myHealth: FriendHealth
    let otherHealth: FriendHealth
    /// Pre-loaded thread. The detail view copies this into local `@State` so
    /// the user can append new messages without mutating the source mock.
    let messages: [TogetherMessage]
}

/// 5 metrics the prototype's health-compare card surfaces. All preformatted
/// strings — number formatting decisions live in the mock, not the view.
struct FriendHealth: Hashable {
    let steps: String        // "8,432"
    let stepsShort: String   // "8.4k" — used in the head-pill above the pet
    let sleep: String        // "6h 18m"
    let sleepShort: String   // "6h18眠" — head-pill flavor
    let hr: String           // "72"
    let cal: String          // "425"
    let rest: String         // "1h 30m"
}

/// One bubble in the twin-space message thread. Sender enum is local to keep
/// the model file self-contained; the detail view maps it to bubble alignment.
struct TogetherMessage: Identifiable, Hashable {
    enum Sender: Hashable { case me, them }
    let id: UUID
    let who: Sender
    let text: String
    let time: String

    init(id: UUID = UUID(), who: Sender, text: String, time: String) {
        self.id = id
        self.who = who
        self.text = text
        self.time = time
    }
}

// MARK: - Plaza (广场)

/// Snapshot of the community plaza — single goal banner + 4 community stats +
/// a pet grid. Realtime numbers in the prototype are simulated; we expose the
/// fields here as plain values, the view animates a tiny tick on a timer.
struct PlazaSnapshot {
    let goalTitle: String
    var goalCurrent: Int
    let goalTotal: Int
    var onlineCount: Int
    let myContribSteps: String
    let myRank: String
    let exerciseCount: String
    let members: [PlazaMember]

    var goalPercent: Double {
        guard goalTotal > 0 else { return 0 }
        return min(1.0, Double(goalCurrent) / Double(goalTotal))
    }
}

/// One pet in the plaza grid. `isMe` flips the cell to coral-tinted "YOU"
/// styling; everyone else renders as a neutral cell.
struct PlazaMember: Identifiable, Hashable {
    let id: UUID
    let name: String
    let sprite: PetSprite
    let isMe: Bool

    init(id: UUID = UUID(), name: String, sprite: PetSprite, isMe: Bool = false) {
        self.id = id
        self.name = name
        self.sprite = sprite
        self.isMe = isMe
    }
}

// MARK: - Mock data

enum TogetherMock {
    /// 3-friend roster matching `SPACES.{nova,mom,aj}` in the prototype. Names,
    /// pets, statuses, messages, and health numbers are intentionally identical
    /// so demo screenshots line up with the HTML reference.
    static let friends: [Friend] = [
        Friend(
            id: "nova",
            displayName: "鱼",
            petName: "NOVA",
            sprite: .blob,
            relation: "异地恋",
            daysTogether: 245,
            myStatus: "运动中",
            otherStatus: "刚睡下",
            myHealth: FriendHealth(
                steps: "8,432", stepsShort: "8.4k步",
                sleep: "6h 18m", sleepShort: "6h18眠",
                hr: "72", cal: "425", rest: "1h 30m"
            ),
            otherHealth: FriendHealth(
                steps: "3,240", stepsShort: "3.2k步",
                sleep: "7h 42m", sleepShort: "7h42眠",
                hr: "68", cal: "312", rest: "2h 18m"
            ),
            messages: [
                .init(who: .them, text: "早安~ 今天慢跑加油 🏃", time: "昨日 22:10"),
                .init(who: .me,   text: "收到！晚上想你",         time: "昨日 22:14"),
                .init(who: .them, text: "我刚到家，洗漱睡了",     time: "昨日 22:30"),
                .init(who: .me,   text: "今天跑了 5km 啦~",        time: "今早 08:20"),
                .init(who: .them, text: "太棒了 ✨",              time: "5 分钟前"),
            ]
        ),
        Friend(
            id: "mom",
            displayName: "妈妈",
            petName: "BUTTON",
            sprite: .noct,
            relation: "家人",
            daysTogether: 89,
            myStatus: "在跑步",
            otherStatus: "在散步",
            myHealth: FriendHealth(
                steps: "8,432", stepsShort: "8.4k步",
                sleep: "6h 18m", sleepShort: "6h18眠",
                hr: "72", cal: "425", rest: "1h 30m"
            ),
            otherHealth: FriendHealth(
                steps: "5,120", stepsShort: "5.1k步",
                sleep: "8h 02m", sleepShort: "8h02眠",
                hr: "64", cal: "210", rest: "3h 12m"
            ),
            messages: [
                .init(who: .them, text: "早起去公园走走啦",      time: "07:00"),
                .init(who: .them, text: "记得吃早饭 🥣",         time: "07:32"),
                .init(who: .me,   text: "吃过啦！中午回家吃饭吗", time: "08:15"),
                .init(who: .them, text: "中午不用啦，你忙",      time: "09:14"),
            ]
        ),
        Friend(
            id: "aj",
            displayName: "阿杰",
            petName: "ZIP",
            sprite: .hush,
            relation: "挚友",
            daysTogether: 34,
            myStatus: "在跑步",
            otherStatus: "健身房",
            myHealth: FriendHealth(
                steps: "8,432", stepsShort: "8.4k步",
                sleep: "6h 18m", sleepShort: "6h18眠",
                hr: "72", cal: "425", rest: "1h 30m"
            ),
            otherHealth: FriendHealth(
                steps: "12,420", stepsShort: "12k步",
                sleep: "6h 30m", sleepShort: "6h30眠",
                hr: "58", cal: "720", rest: "45m"
            ),
            messages: [
                .init(who: .me,   text: "今晚一起练腿？",   time: "昨日 18:00"),
                .init(who: .them, text: "来！20 点见 💪",   time: "昨日 18:05"),
                .init(who: .them, text: "完成！明天继续",   time: "昨日 23:00"),
            ]
        ),
    ]

    /// Single plaza snapshot — community goal + 12 mock members + me. The
    /// view inserts the user's PetStateStore name into the "me" cell at render
    /// time, so this list does not include a "me" entry.
    static let plaza = PlazaSnapshot(
        goalTitle: "全社区累计步行 1,000,000 步",
        goalCurrent: 624_318,
        goalTotal: 1_000_000,
        onlineCount: 248,
        myContribSteps: "3,240",
        myRank: "#84",
        exerciseCount: "1,024",
        members: [
            PlazaMember(name: "姈姈", sprite: .noct),
            PlazaMember(name: "阿杰", sprite: .hush),
            PlazaMember(name: "小丽", sprite: .blob),
            PlazaMember(name: "老王", sprite: .bean),
            PlazaMember(name: "泡泡", sprite: .blob),
            PlazaMember(name: "KAI",  sprite: .hush),
            PlazaMember(name: "兔妹", sprite: .noct),
            PlazaMember(name: "阿仔", sprite: .blob),
            PlazaMember(name: "小满", sprite: .bean),
            PlazaMember(name: "橘子", sprite: .blob),
            PlazaMember(name: "小七", sprite: .noct),
            PlazaMember(name: "欢欢", sprite: .hush),
        ]
    )
}

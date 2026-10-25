import Foundation
import PiboCore

/// Words for Core's semantic answers. Which level unlocks what is Core's; this
/// file only says it in Chinese. Ported from HarmonyOS
/// `entry/src/main/ets/services/growth/GrowthPresentation.ets`.
enum GrowthPresentation {
    // Core's appearance masks. `pibo-core` owns these bits; the Swift bindings
    // do not export them yet, so the values are kept here (1/2/4/8) until they do.
    private static let accessoryScarf: UInt32 = 1
    private static let accessoryAcornHat: UInt32 = 2
    private static let accessoryBackpack: UInt32 = 4
    private static let accessoryNightGlow: UInt32 = 8
    private static let trickStretch: UInt32 = 1
    private static let trickCountStones: UInt32 = 2
    private static let trickHum: UInt32 = 4
    private static let trickRoll: UInt32 = 8

    private static let leafStageText = ["", "叶子长长了", "长出了第二片叶子", "叶子上冒出一个花苞", "开花了"]
    private static let accessoryText: [(bit: UInt32, text: String)] = [
        (accessoryScarf, "戴上了小围巾"),
        (accessoryAcornHat, "戴上了橡果帽"),
        (accessoryBackpack, "背上了小背包"),
        (accessoryNightGlow, "夜里叶子会发光")
    ]
    private static let trickText: [(bit: UInt32, text: String)] = [
        (trickStretch, "学会了伸懒腰"),
        (trickCountStones, "学会了数石头"),
        (trickHum, "学会了哼歌"),
        (trickRoll, "学会了打滚")
    ]
    private static let decorNames = ["蘑菇凳", "名牌", "石头堆", "花圃", "风车", "月亮灯", "小池塘", "秋千", "篝火", "帐篷",
                                     "小船", "风筝", "望远镜"]
    private static let decorNotes = [
        "软软的。Pibo 坐不上去，但很喜欢。",
        "写着你们认识的第几天。",
        "Pibo 每讲一段石头的事，就多一颗。",
        "今天每走一千步，开一朵花。",
        "你今天动得越多，它转得越快。",
        "昨晚睡得好，它就亮。",
        "住着一只不太理人的青蛙。",
        "Pibo 精神好的时候会盯着它看。",
        "黄昏和夜里会点着。",
        "露营气氛组。",
        "拴在小溪边。Pibo 白天会坐上去看鱼。",
        "插在山坡上。晴天有风，Pibo 就去放。",
        "架在山顶。天一黑，Pibo 就去看星星。"
    ]
    /// Which scene each piece stands in, for the sheet's headings (decision 065).
    private static let decorSceneTitles = ["空地", "小溪", "山坡"]

    static func decorSceneTitle(_ scene: Int) -> String {
        decorSceneTitles.indices.contains(scene) ? decorSceneTitles[scene] : ""
    }

    static func decorName(_ id: PiboCoreDecorID) -> String {
        let index = Int(id.rawValue)
        return decorNames.indices.contains(index) ? decorNames[index] : ""
    }

    static func decorNote(_ id: PiboCoreDecorID) -> String {
        let index = Int(id.rawValue)
        return decorNotes.indices.contains(index) ? decorNotes[index] : ""
    }

    /// What changed between two appearance answers, in display order.
    static func appearanceChanges(
        before: PiboCoreGrowthAppearance,
        after: PiboCoreGrowthAppearance
    ) -> [String] {
        var changes: [String] = []
        if after.bodyStage > before.bodyStage {
            changes.append(after.bodyStage >= 2 ? "长成大 Pibo 了" : "长大了一圈")
        }
        if after.leafStage > before.leafStage {
            changes.append(leafStageText.indices.contains(after.leafStage) ? leafStageText[after.leafStage] : "")
        }
        for entry in accessoryText where after.accessoryMask & entry.bit != 0 && before.accessoryMask & entry.bit == 0 {
            changes.append(entry.text)
        }
        for entry in trickText where after.trickMask & entry.bit != 0 && before.trickMask & entry.bit == 0 {
            changes.append(entry.text)
        }
        return changes.filter { !$0.isEmpty }
    }

    /// Everything a level brings: appearance changes and newly purchasable decorations.
    static func levelUnlocks(_ level: Int) -> [String] {
        var changes = appearanceChanges(
            before: PiboCoreGrowth.appearance(level: max(1, level - 1)),
            after: PiboCoreGrowth.appearance(level: level)
        )
        for id in PiboCoreDecor.unlocked(atLevel: level) {
            changes.append("可以放\(decorName(id))了")
        }
        return changes
    }

    struct NextUnlock {
        let level: Int
        let changes: [String]
    }

    /// The nearest level above `level` that brings something visible.
    static func nextUnlock(_ level: Int, maxLevel: Int = 30) -> NextUnlock? {
        guard level + 1 <= maxLevel else { return nil }
        for next in (level + 1)...maxLevel {
            let changes = levelUnlocks(next)
            if !changes.isEmpty { return NextUnlock(level: next, changes: changes) }
        }
        return nil
    }

    static func toneName(_ tone: PiboCoreGrowthTone) -> String {
        switch tone {
        case .oldFriend: return "老朋友"
        case .tease: return "熟了"
        default: return "刚认识"
        }
    }

    static func wishTitle(_ slot: WishSlot) -> String {
        switch slot.kind {
        case .steps: return "今天走到 \(Int(slot.target.rounded())) 步"
        case .activeMinutes: return "活动满 \(Int(slot.target.rounded())) 分钟"
        case .pats: return "拍拍我 \(Int(slot.target.rounded())) 次"
        case .mealPhoto: return "给我看看你吃了什么"
        case .answerPrompt: return "回答我一个问题"
        case .sleepEnough:
            return slot.night == .lastNight
                ? "昨晚睡够 \(hours(slot.target)) 小时"
                : "今晚睡够 \(hours(slot.target)) 小时"
        default: return ""
        }
    }

    static func wishProgressText(_ slot: WishSlot) -> String {
        if slot.done { return "完成啦" }
        switch slot.kind {
        case .steps: return "\(Int(slot.value.rounded())) / \(Int(slot.target.rounded()))"
        case .activeMinutes: return "\(Int(slot.value.rounded())) / \(Int(slot.target.rounded())) 分钟"
        case .pats: return "\(Int(slot.value.rounded())) / \(Int(slot.target.rounded()))"
        case .answerPrompt: return "Pibo 正在琢磨一件事，去拍拍它"
        case .sleepEnough:
            return slot.night == .tonight ? "明早看结果" : "\(hours(slot.value)) 小时"
        default: return "还没有"
        }
    }

    static func sourceName(_ source: Int) -> String {
        source == 0 ? "睡眠" : (source == 1 ? "步数" : "活动")
    }

    /// Whole or half hours, as the wish titles spell them.
    private static func hours(_ minutes: Double) -> String {
        let value = (minutes / 30).rounded() / 2
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}

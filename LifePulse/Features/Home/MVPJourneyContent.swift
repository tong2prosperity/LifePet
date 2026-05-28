import SwiftUI

struct StarlightSummary: Identifiable, Equatable {
    let id: StatKind
    let title: String
    let subtitle: String
    let value: Int
    let source: String
    let symbol: String

    var progress: Double { Double(value) / 100 }

    var level: StarlightLevel {
        StarlightLevel(value: value)
    }
}

enum StarlightLevel: Equatable {
    case bright
    case steady
    case faint
    case ember

    init(value: Int) {
        switch value {
        case 80...: self = .bright
        case 55...: self = .steady
        case 30...: self = .faint
        default: self = .ember
        }
    }

    var label: String {
        switch self {
        case .bright: return "星光充盈"
        case .steady: return "星光稳定"
        case .faint: return "星光微弱"
        case .ember: return "将要沉睡"
        }
    }

    var detail: String {
        switch self {
        case .bright: return "Pibo 今天醒得很久。"
        case .steady: return "契约正在稳定发光。"
        case .faint: return "再补一点光就好。"
        case .ember: return "它开始缩回星壳。"
        }
    }

    var accent: Color {
        switch self {
        case .bright: return LP.Colors.coral
        case .steady: return LP.Colors.sage
        case .faint: return Color(hex: 0xB8862F)
        case .ember: return LP.Colors.muted
        }
    }

    var fill: Color {
        switch self {
        case .bright: return LP.Colors.coralSoft
        case .steady: return LP.Colors.sageSoft
        case .faint: return Color(hex: 0xFFF3D6)
        case .ember: return LP.Colors.paperWarm
        }
    }
}

struct PiboSpeech: Equatable {
    let text: String
    let tone: LPSpeechBubble.Tone
}

struct JourneyRitual: Equatable {
    let title: String
    let subtitle: String
    let current: Int
    let target: Int
    let isReady: Bool

    var progress: Double {
        min(1, max(0, Double(current) / Double(target)))
    }
}

struct MemoryFragment: Identifiable, Equatable {
    let id: String
    let title: String
    let unlockLabel: String
    let body: String
}

struct JourneyAccessory: Identifiable, Equatable {
    let id: String
    let name: String
    let unlockLabel: String
    let meaning: String
    let isUnlocked: Bool
}

extension PetState {
    var journeyLabel: String {
        switch self {
        case .excited, .blissful: return "明亮"
        case .normal: return "平稳"
        case .tired: return "困倦"
        case .sleeping: return "浅眠"
        case .sick: return "深眠预警"
        }
    }

    var speechTone: LPSpeechBubble.Tone {
        switch self {
        case .sick, .sleeping, .tired: return .urgent
        case .normal, .excited, .blissful: return .calm
        }
    }
}

extension PetStateStore {
    var journeyDay: Int {
        min(max(dayCount, 1), 7)
    }

    var piboSpeech: PiboSpeech {
        let day = journeyDay
        if shouldShowWorldAnomaly {
            return PiboSpeech(text: worldAnomalyLine(day: day), tone: .calm)
        }

        switch state {
        case .excited, .blissful:
            return PiboSpeech(text: brightLine(day: day), tone: .calm)
        case .normal:
            return PiboSpeech(text: steadyLine(day: day), tone: .calm)
        case .tired:
            return PiboSpeech(text: tiredLine(day: day), tone: .urgent)
        case .sleeping:
            return PiboSpeech(text: sleepingLine(day: day), tone: .urgent)
        case .sick:
            return PiboSpeech(text: "壳里很安静。我还听得见你，别一下子做太多。", tone: .urgent)
        }
    }

    var starlightSummaries: [StarlightSummary] {
        [
            StarlightSummary(
                id: .vitality,
                title: "活力星光",
                subtitle: "运动让 Pibo 更清醒",
                value: statValueForJourney(.vitality),
                source: "步数 · 运动分钟",
                symbol: "figure.walk"
            ),
            StarlightSummary(
                id: .energy,
                title: "静息星光",
                subtitle: "睡眠让 Pibo 稳定醒来",
                value: statValueForJourney(.energy),
                source: "睡眠 · 深睡 · REM",
                symbol: "moon.zzz.fill"
            ),
        ]
    }

    var journeyRitual: JourneyRitual {
        let current = min(dayCount, 7)
        let remaining = max(0, 7 - current)
        if current >= 7 {
            return JourneyRitual(
                title: "第一次星光仪式",
                subtitle: "契约已经稳定一周。Pibo 找回了一件来自旧世界的东西。",
                current: 7,
                target: 7,
                isReady: true
            )
        }
        return JourneyRitual(
            title: "第一次星光仪式",
            subtitle: "还差 \(remaining) 天。继续给 Pibo 留下一点活力星光和静息星光。",
            current: current,
            target: 7,
            isReady: false
        )
    }

    var memoryFragments: [MemoryFragment] {
        var fragments: [MemoryFragment] = []
        if dayCount >= 3 {
            fragments.append(
                MemoryFragment(
                    id: "star-shell",
                    title: "无名星壳",
                    unlockLabel: "Day 3 解锁",
                    body: "很久以前，Pibo 们在没有太阳的地方等待光。它们不记得自己从哪里来，只记得契约会在黑暗里发亮。"
                )
            )
        }
        if dayCount >= 7 {
            fragments.append(
                MemoryFragment(
                    id: "broken-bell",
                    title: "破损铃铛",
                    unlockLabel: "第一次星光仪式",
                    body: "铃声不是为了命令谁回来。它只是告诉迷路的人，仍然有人在等。"
                )
            )
        }
        return fragments
    }

    var journeyAccessories: [JourneyAccessory] {
        [
            JourneyAccessory(
                id: "broken-bell",
                name: "破损铃铛",
                unlockLabel: dayCount >= 7 ? "已显形" : "Day 7 显形",
                meaning: "曾经用于召回迷路的 Pibo。",
                isUnlocked: dayCount >= 7
            ),
            JourneyAccessory(
                id: "stardust-cloak",
                name: "星尘披风",
                unlockLabel: dayCount >= 6 ? "星光中出现轮廓" : "未显形",
                meaning: "用来穿过长夜的旧布。",
                isUnlocked: dayCount >= 7
            ),
        ]
    }

    var journeyNudge: String {
        if dayCount < 3 {
            return "先认识规则：运动给活力星光，睡眠给静息星光。"
        }
        if dayCount < 7 {
            return "碎片正在稳定。Pibo 偶尔会说出不属于这里的话。"
        }
        return "第一周已经完成。接下来可以扩展饰品、归巢和更多记忆碎片。"
    }

    private var shouldShowWorldAnomaly: Bool {
        guard dayCount >= 3 else { return false }
        let cadence = dayCount >= 7 ? 4 : 10
        return (speechCursor + dayCount) % cadence == cadence - 1
    }

    private func statValueForJourney(_ kind: StatKind) -> Int {
        stats.first(where: { $0.kind == kind })?.value ?? 0
    }

    private func brightLine(day: Int) -> String {
        let lines = [
            "你今天走了很多路，我身上一直亮着。",
            "星光很暖。我想多醒一会儿。",
            "昨晚的静息星光很稳，我醒来的时候没有害怕。",
        ]
        return lines[(speechCursor + day) % lines.count]
    }

    private func steadyLine(day: Int) -> String {
        let lines = [
            "今天刚刚好。我能清醒地陪你一阵。",
            "星光不多不少，像一盏小灯。",
            "我把今天记下来了。契约还在发光。",
        ]
        return lines[(speechCursor + day) % lines.count]
    }

    private func tiredLine(day: Int) -> String {
        let lines = [
            "我有点困，但还能听见你。",
            "今天的星光很轻。我可能会慢一点回应。",
            "你不用一下子做很多，让光回来一点就好。",
        ]
        return lines[(speechCursor + day) % lines.count]
    }

    private func sleepingLine(day: Int) -> String {
        let lines = [
            "我睡了一会儿。醒来的时候，壳里很安静。",
            "如果你今天走一小段路，我应该能睁开眼。",
            "沉睡不是结束。我只是离声音远了一点。",
        ]
        return lines[(speechCursor + day) % lines.count]
    }

    private func worldAnomalyLine(day: Int) -> String {
        let lines = [
            "门后的星声，又近了一点。",
            "我梦见了很多星壳，它们都没有名字。",
            "归巢不是死亡。可我还不想回去。",
            "有些光不是照亮路的，是用来记住人的。",
        ]
        return lines[(speechCursor + day) % lines.count]
    }
}

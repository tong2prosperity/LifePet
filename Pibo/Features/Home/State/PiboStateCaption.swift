import PiboCore
import SwiftUI

/// Platform wording for a Core decision (2026-09-28, mirrors HarmonyOS
/// `PiboStateCaption`). Core owns the state and its cause; this only names
/// them, in words and never numbers, so a glance at Home answers "how is Pibo
/// today, and why?" without a pat.
struct PiboStateCaption: Equatable {
    enum Tone: Equatable {
        case calm, bright, weary, dawn, night, mist

        var color: Color {
            switch self {
            case .bright: Color(hex: 0xFFD27A)
            case .weary: Color(hex: 0xB7C4F0)
            case .dawn: Color(hex: 0xFFC39A)
            case .night: Color(hex: 0xCBD6FF)
            case .mist: Color(hex: 0xD5DBDD)
            case .calm: Color(hex: 0xB9E3A8)
            }
        }
    }

    struct Input: Equatable {
        var state: PiboActivityState
        var cause: PiboCoreStateCause
        /// Waking only: the day's result last night's sleep already decided.
        var pendingCause: PiboCoreStateCause?
        var dataUnknownReason: PiboCorePatDataUnknownReason
        /// Without real records the sleep window is Core's default, not "yours".
        var hasRealHealthData: Bool
    }

    let title: String
    let detail: String
    let tone: Tone

    /// 「Pibo 有点累，昨晚没睡够」, for VoiceOver.
    var sentence: String {
        AppLocalization.format("Pibo %@，%@", title, detail)
    }

    static func resolve(_ input: Input) -> PiboStateCaption {
        switch input.state {
        case .energetic:
            let detail = switch input.cause {
            case .recentWorkout: "刚跟着你动了一会儿"
            case .activityMilestone: "今天跟着你走了很远"
            case .goodSleep: "昨晚睡得不错"
            default: "今天很轻快"
            }
            return caption("精神很好", detail, .bright)
        case .tired:
            return caption("有点累", input.cause == .insufficientSleep ? "昨晚没睡够" : "想慢一点", .weary)
        case .waking:
            let detail = switch input.pendingCause {
            case .goodSleep?: "昨晚睡得不错"
            case .insufficientSleep?: "昨晚睡得有点少"
            default: "还在醒神"
            }
            return caption("刚醒", detail, .dawn)
        case .sleeping:
            return caption("睡着了", input.hasRealHealthData ? "到了你平常睡觉的时间" : "到了睡觉的时间", .night)
        case .dataUnknown:
            let detail = switch input.dataUnknownReason {
            case .authorization: "还没连接健康记录"
            case .unavailable: "健康服务暂时不可用"
            case .interruptedNoTrustedState: "记录同步断了一下"
            default: "在等第一批记录"
            }
            return caption("看不清你的日常", detail, .mist)
        case .stable:
            return caption("安稳", input.cause == .goodSleep ? "昨晚睡得不错" : "和平常差不多", .calm)
        }
    }

    private static func caption(_ title: String, _ detail: String, _ tone: Tone) -> PiboStateCaption {
        PiboStateCaption(title: AppLocalization.text(title), detail: AppLocalization.text(detail), tone: tone)
    }
}

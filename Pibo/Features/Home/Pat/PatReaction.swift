import Foundation

// MARK: - 拍一拍 reaction model (Figma 76:6758)
//
// A pat resolves to *one* of: silence-with-a-cold-shoulder (扭过头背对用户),
// or a spoken line — and the line carries a **mood** that picks the bubble
// treatment: 正常 (round outlined bubble) / 生气 (black bubble, Pibo also
// turns away) / 呓语 (drifting murmur). Two render styles exist in the mockup
// (对话框 vs 仿漫画); the 对话框 set ships first — see `PiboSpeechBubbleView`.

/// Which bubble treatment a spoken line gets (Figma: 生气-黑色 / 正常-圆形描边 /
/// 呓语-弹幕飘过).
enum PiboSpeechMood: Equatable {
    case normal
    case angry
    case murmur
}

/// One spoken line + its presentation.
struct PiboSpeechLine: Equatable {
    let text: String
    var mood: PiboSpeechMood = .normal
    /// True when the line is a 故事线 clue (拍出来的线索) — rendered with the
    /// accent treatment so it reads as "this one matters".
    var isStoryClue: Bool = false
}

/// The store's answer to a pat. `turnsAway` and `line` compose: 不理睬 is a
/// turn-away with no line; 生气 turns away *and* grumbles.
struct PatResponse: Equatable {
    var line: PiboSpeechLine? = nil
    var turnsAway: Bool = false

    /// 不理睬 — back to the user, no text (spec §3.2).
    static let ignored = PatResponse(turnsAway: true)
}

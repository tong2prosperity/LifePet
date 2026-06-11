import SwiftUI

/// Pibo's spoken line, styled by mood — the 对话框 set from Figma 76:6758:
///
/// - `.normal` — white round bubble with a hairline outline (圆形描边).
/// - `.angry`  — black bubble, white text (生气-黑色); the stage turns Pibo away.
/// - `.murmur` — soft low-contrast drift (呓语). The 仿漫画 弹幕飘过 treatment
///   (pills drifting across the screen) is a follow-up — TODO(design): comic
///   style variants once the bubble system is locked.
///
/// 故事线 clues (`isStoryClue`) get an accent ring + a ✦ so they read as
/// "this one matters" without breaking the garble.
struct PiboSpeechBubbleView: View {
    let line: PiboSpeechLine

    var body: some View {
        Text(displayText)
            .lpText(LP.Typography.b2Medium)
            .foregroundStyle(textColor)
            .multilineTextAlignment(.center)
            .padding(.horizontal, LP.Spacing.l)
            .padding(.vertical, LP.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(bubbleFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .lpShadow(LP.Shadow.elevation2)
            .opacity(line.mood == .murmur ? 0.92 : 1)
    }

    private var displayText: String {
        line.isStoryClue ? "✦ \(line.text)" : line.text
    }

    private var cornerRadius: CGFloat {
        // 正常/呓语 read round and soft; 生气 squares off a touch (仿漫画的锋利感).
        line.mood == .angry ? LP.Radius.l : LP.Radius.xxl
    }

    private var bubbleFill: Color {
        switch line.mood {
        case .normal: return LP.Fill.bgContainer.opacity(0.96)
        case .angry:  return LP.Neutral.grey900
        case .murmur: return LP.Fill.bgContainer.opacity(0.78)
        }
    }

    private var textColor: Color {
        switch line.mood {
        case .normal: return LP.Content.primary
        case .angry:  return Color.white
        case .murmur: return LP.Content.tertiary
        }
    }

    private var borderColor: Color {
        if line.isStoryClue { return LP.Fill.foundationAccent.opacity(0.55) }
        switch line.mood {
        case .normal: return LP.Separator.primary
        case .angry:  return .clear
        case .murmur: return LP.Separator.primary.opacity(0.6)
        }
    }

    private var borderWidth: CGFloat {
        line.isStoryClue ? 1.5 : LP.BorderWidth.hair
    }
}

#Preview {
    VStack(spacing: 20) {
        PiboSpeechBubbleView(line: PiboSpeechLine(text: "...云...在飘..."))
        PiboSpeechBubbleView(line: PiboSpeechLine(text: "人...很烦...", mood: .angry))
        PiboSpeechBubbleView(line: PiboSpeechLine(text: "...zzz...一个bobo...", mood: .murmur))
        PiboSpeechBubbleView(line: PiboSpeechLine(text: "...黑的洞...是门啵...", isStoryClue: true))
    }
    .padding()
    .background(Color(hex: 0xF4F8F9))
}

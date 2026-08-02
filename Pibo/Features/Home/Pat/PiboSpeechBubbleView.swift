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
///
/// A `.system` line (`PiboSpeechSource.system`) is not Pibo talking at all — it
/// is the app saying why Pibo won't answer. It takes an **info-cyan** border
/// instead of the speech set's hairline black / accent green, because the whole
/// point is that a glance tells the two apart: none of Pibo's own moods are
/// cyan, so the color alone carries "this is not a voice".
struct PiboSpeechBubbleView: View {
    let line: PiboSpeechLine
    var onDetail: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: line.data == nil ? .center : .leading, spacing: LP.Spacing.m) {
            if let data = line.data {
                dataText(data)
                    .lpText(LP.Typography.b3Regular)
            }

            Group {
                if line.source == .system {
                    systemContent
                } else {
                    Text(displayText)
                        .lpText(LP.Typography.b3Regular)
                        .foregroundStyle(textColor)
                        .multilineTextAlignment(line.data == nil ? .center : .leading)
                }
            }

            if line.data != nil, let onDetail {
                Button(action: onDetail) {
                    Label(AppLocalization.text("查看今日详情"), systemImage: "list.bullet")
                        .lpText(LP.Typography.b4Medium)
                        .foregroundStyle(LP.Colorful.teal500)
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppLocalization.text("打开足迹"))
            }
        }
        .padding(.horizontal, LP.Spacing.xxl)
        .padding(.vertical, LP.Spacing.m)
        .frame(maxWidth: line.data == nil ? nil : 280, alignment: .leading)
        .background { bubbleBackground }
        .overlay { bubbleBorder }
        .lpShadow(usesDesignedPatBubble ? LP.Shadow.Spec(layers: []) : LP.Shadow.elevation2)
        .opacity(line.mood == .murmur ? 0.92 : 1)
    }

    private func dataText(_ data: PiboSpeechData) -> Text {
        Text(data.prefix)
            .foregroundColor(LP.Content.primary)
        + Text(data.value)
            .foregroundColor(LP.Colorful.teal500)
            .fontWeight(.medium)
        + Text(data.suffix)
            .foregroundColor(LP.Content.primary)
    }

    /// 请勿打扰 reads as a status, not a sentence — the moon icon says "asleep"
    /// before the text is even read.
    private var systemContent: some View {
        HStack(spacing: LP.Spacing.s) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LP.Fill.foundationInfo)
            Text(line.text)
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(LP.Content.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    private var displayText: String {
        line.isStoryClue ? "✦ \(line.text)" : line.text
    }

    private var usesDesignedPatBubble: Bool {
        line.source == .pibo && line.mood == .normal && !line.isStoryClue
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if usesDesignedPatBubble {
            UnevenRoundedRectangle(
                topLeadingRadius: LP.Radius.l,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: LP.Radius.l,
                topTrailingRadius: LP.Radius.l,
                style: .continuous
            )
            .fill(LP.Fill.bgPop)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(bubbleFill)
        }
    }

    @ViewBuilder
    private var bubbleBorder: some View {
        if !usesDesignedPatBubble {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
    }

    private var cornerRadius: CGFloat {
        // 正常/呓语 read round and soft; 生气 squares off a touch (仿漫画的锋利感).
        line.mood == .angry ? LP.Radius.l : LP.Radius.xxl
    }

    private var bubbleFill: Color {
        guard line.source == .pibo else { return LP.Fill.bgPop.opacity(0.96) }
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
        guard line.source == .pibo else { return LP.Fill.foundationInfo }
        if line.isStoryClue { return LP.Fill.foundationAccent.opacity(0.55) }
        switch line.mood {
        case .normal: return LP.Separator.primary
        case .angry:  return .clear
        case .murmur: return LP.Separator.primary.opacity(0.6)
        }
    }

    private var borderWidth: CGFloat {
        if line.source == .system { return 2 }
        return line.isStoryClue ? 1.5 : LP.BorderWidth.hair
    }
}

#Preview {
    VStack(spacing: 20) {
        PiboSpeechBubbleView(line: PiboSpeechLine(text: "...云...在飘..."))
        PiboSpeechBubbleView(line: PiboSpeechLine(text: "人...很烦...", mood: .angry))
        PiboSpeechBubbleView(line: PiboSpeechLine(text: "...zzz...一个bobo...", mood: .murmur))
        PiboSpeechBubbleView(line: PiboSpeechLine(text: "...黑的洞...是门啵...", isStoryClue: true))
        PiboSpeechBubbleView(line: .system("Pibo 设置了请勿打扰"))
    }
    .padding()
    .background(Color(hex: 0xF4F8F9))
}

import SwiftUI
import UIKit

/// Pibo's forest dialogue surface (2026-09-09 visual pass, shared with
/// HarmonyOS `PiboSpeechBubble`): paper-white 18 pt card, soft shadow, no
/// outline, and a short curved tail toward Pibo. Content, continuation and
/// lifetime stay Core-owned — there is deliberately no "tap again to continue"
/// hint; a body double tap still advances the line.
///
/// A `.system` line is not Pibo talking — it keeps an info-cyan edge so a
/// glance tells the two apart. `.angry` is a compatibility presentation only.
struct PiboSpeechBubbleView: View {
    let line: PiboSpeechLine
    var maxAvailableWidth: CGFloat = 353
    var onDetail: (() -> Void)? = nil
    /// Decision 054 preset replies; nil hides them.
    var onChoice: ((String) -> Void)? = nil
    var onCustomReply: (() -> Void)? = nil

    static var transition: AnyTransition {
        if UIAccessibility.isReduceMotionEnabled {
            return .opacity.animation(.easeOut(duration: 0.12))
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 4)).animation(.easeOut(duration: 0.18)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }

    var body: some View {
        VStack(spacing: -1) {
            card
            if line.source != .system {
                BubbleTail()
                    .fill(fill)
                    .frame(width: 18, height: 10)
                    .accessibilityHidden(true)
            }
        }
        .opacity(line.mood == .murmur ? 0.96 : 1)
    }

    private var card: some View {
        VStack(alignment: hasData ? .leading : .center, spacing: hasData ? 12 : 0) {
            if let data = line.data {
                dataText(data)
                    .font(.system(size: 16))
                    .lineSpacing(8)
            }

            if line.source == .system {
                systemContent
            } else {
                Text(displayText)
                    .font(.system(size: 16, weight: line.isStoryClue ? .medium : .regular))
                    .lineSpacing(8)
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(bodyAlignment)
                    .frame(maxWidth: .infinity, alignment: bodyAlignment == .center ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let interaction = line.interaction, let onChoice {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(interaction.choices) { choice in
                            Button { onChoice(choice.id) } label: {
                                Text(choice.label)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(LP.Content.primary)
                                    .padding(.horizontal, 14)
                                    .frame(minWidth: 72, minHeight: 44)
                                    .overlay(Capsule().strokeBorder(LP.Fill.foundationAccent, lineWidth: 1))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(AppLocalization.text("回答 Pibo"))
                        }
                    }
                    if interaction.allowsCustom, let onCustomReply {
                        Button(action: onCustomReply) {
                            Text(AppLocalization.text("我想说…"))
                                .font(.system(size: 14))
                                .foregroundStyle(LP.Fill.foundationAccent)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(AppLocalization.text("写一句自己的回复，只保存在这台手机上"))
                    }
                }
                .padding(.top, 10)
                .frame(maxWidth: .infinity)
            }

            if hasData, let onDetail {
                Button(action: onDetail) {
                    Label(AppLocalization.text("查看今日详情"), systemImage: "list.bullet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LP.Fill.foundationAccent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppLocalization.text("打开足迹"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: min(maxAvailableWidth, hasData ? 280 : 260))
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill)
        )
        .overlay {
            if line.source == .system {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LP.Fill.foundationInfo, lineWidth: 2)
            }
        }
        .shadow(color: Color(red: 0x17 / 255, green: 0x1D / 255, blue: 0x22 / 255).opacity(0.08), radius: 5, x: 0, y: 3)
    }

    private var hasData: Bool { line.data != nil }

    /// Short Chinese dialogue stays centred; longer passages keep a reading edge.
    private var bodyAlignment: TextAlignment {
        hasData || line.text.count > 14 ? .leading : .center
    }

    private func dataText(_ data: PiboSpeechData) -> Text {
        Text(data.prefix)
            .foregroundColor(LP.Content.primary)
        + Text(data.value)
            .foregroundColor(LP.Fill.foundationAccent)
            .fontWeight(.medium)
        + Text(data.suffix)
            .foregroundColor(LP.Content.primary)
    }

    private var systemContent: some View {
        HStack(spacing: LP.Spacing.s) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LP.Fill.foundationInfo)
            Text(line.text)
                .font(.system(size: 16))
                .foregroundStyle(LP.Content.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    private var displayText: String {
        line.isStoryClue ? "✦ \(line.text)" : line.text
    }

    private var fill: Color {
        line.mood == .angry ? Color(red: 0x17 / 255, green: 0x1D / 255, blue: 0x22 / 255) : LP.Fill.bgContainer
    }

    private var textColor: Color {
        switch line.mood {
        case .normal: LP.Content.primary
        case .angry: LP.Content.invertPrimary
        case .murmur: LP.Content.secondary
        }
    }
}

/// Short curved tail pointing down toward Pibo; never covers the bo.
private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 18, sy = rect.height / 10
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 18 * sx, y: 0))
        path.addQuadCurve(to: CGPoint(x: 7 * sx, y: 10 * sy), control: CGPoint(x: 12 * sx, y: 3 * sy))
        path.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: 8 * sx, y: 4 * sy))
        path.closeSubpath()
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

#Preview {
    VStack(spacing: 20) {
        PiboSpeechBubbleView(line: PiboSpeechLine(text: "...云...在飘..."))
        PiboSpeechBubbleView(line: PiboSpeechLine(text: "今天走了好多路，我的脚底板有点痒痒的。", hasNext: true))
        PiboSpeechBubbleView(line: PiboSpeechLine(text: "...zzz...一个bobo...", mood: .murmur))
        PiboSpeechBubbleView(line: .system("Pibo 设置了请勿打扰"))
    }
    .padding()
    .background(Color(hex: 0xF4F8F9))
}

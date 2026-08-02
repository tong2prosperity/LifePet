import SwiftUI

/// 首页左上角的 `bo` 存量。
///
/// 这是整个闭环里唯一一处「我攒了什么」的常驻可视化 —— 在它出现之前，首页没有任何
/// 一个数字告诉用户累积的结果。所以它要同时答三个问题：**我有多少**（余额）、
/// **下一枚还有多远**（进度条）、**现在能不能收**（可拔取）。
///
/// 点它进兑换面板。
struct BoCounterView: View {
    let balance: Int
    let growthProgress: Double
    let hasRipeBo: Bool
    let action: () -> Void

    @State private var ripePulse = false

    private var accessibilityText: String {
        hasRipeBo
            ? AppLocalization.text("有一枚 bo 熟了，可以收下")
            : AppLocalization.format("已有 %d 枚 bo", balance)
    }

    var body: some View {
        Button {
            LPHaptics.tap()
            action()
        } label: {
            HStack(spacing: LP.Spacing.xs) {
                PiboBoGlyph()
                    .frame(width: 16, height: 22)
                    .scaleEffect(ripePulse ? 1.14 : 1)

                if hasRipeBo {
                    Text(AppLocalization.text("可拔取"))
                        .lpText(LP.Typography.b4Medium)
                        .foregroundStyle(LP.Fill.foundationAccent)
                } else {
                    Text("\(balance)")
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.primary)
                        .contentTransition(.numericText())
                    growthTrack
                }
            }
            .padding(.leading, LP.Spacing.s)
            .padding(.trailing, LP.Spacing.m)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(LP.Fill.bgContainer.opacity(0.90))
            )
            .overlay(
                Capsule().strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair)
            )
            .lpShadow(LP.Shadow.elevation1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(AppLocalization.text("打开兑换道具"))
        .onAppear { syncPulse() }
        .onChange(of: hasRipeBo) { _, _ in syncPulse() }
    }

    /// 离下一枚还有多远。刻意做得很轻 —— 它是余额旁边的一条注脚，不是主角。
    private var growthTrack: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(LP.Content.quarternary.opacity(0.35))
            Capsule()
                .fill(LP.Fill.foundationAccent)
                .frame(width: max(2, 24 * min(1, max(0, growthProgress))))
        }
        .frame(width: 24, height: 3)
        .animation(.easeOut(duration: 0.4), value: growthProgress)
    }

    /// 只有「熟了没收」时才呼吸。常态下让它安静 —— 一个一直在动的角标会变成噪音，
    /// 到真需要提醒时反而没人看。
    private func syncPulse() {
        guard hasRipeBo else {
            withAnimation(.easeOut(duration: 0.2)) { ripePulse = false }
            return
        }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            ripePulse = true
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        BoCounterView(balance: 0, growthProgress: 0.12, hasRipeBo: false) {}
        BoCounterView(balance: 7, growthProgress: 0.68, hasRipeBo: false) {}
        BoCounterView(balance: 7, growthProgress: 1, hasRipeBo: true) {}
    }
    .padding(40)
    .background(Color(hex: 0x9FBFA8))
}

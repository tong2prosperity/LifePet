import SwiftUI

/// Three stat cards — 体力 / 精力 / 心情 — stacked vertically. Each card has
/// a "stamp" silhouette: 1.5pt ink stroke + a 2pt offset-shadow rectangle
/// peeking from behind, mirroring the `box-shadow: 2px 2px 0` the prototype
/// uses for every card on this screen.
struct StatsTriadView: View {
    let stats: [Stat]

    var body: some View {
        VStack(spacing: LP.Spacing.s3) {
            ForEach(stats) { stat in
                StatRow(stat: stat)
            }
        }
    }
}

private struct StatRow: View {
    let stat: Stat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(stat.kind.label)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .frame(width: 60, alignment: .leading)
                ProgressTrack(progress: Double(stat.value) / 100, accent: stat.kind == .mood)
                    .frame(height: 12)
                ValueReadout(value: stat.value)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("来自手表 · \(stat.kind.sourceCopy)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(LP.Colors.muted)
                Text("↑ 补充 · ").font(.system(size: 9, design: .monospaced)).foregroundStyle(LP.Colors.muted)
                + Text(stat.kind.supplementCopy)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(LP.Colors.coral)
            }
            .padding(.leading, 2)
        }
        .lpStampedCard()
    }
}

// MARK: - Bar + readout

private struct ProgressTrack: View {
    let progress: Double
    let accent: Bool

    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
            let clamped = min(1, max(0, progress))
            ZStack(alignment: .leading) {
                shape.fill(Color(hex: 0xF0EADB))
                shape
                    .fill(accent ? LP.Colors.coral : LP.Colors.ink)
                    .frame(width: max(0, geo.size.width * clamped))
                    .animation(.easeOut(duration: 0.6), value: clamped)
                shape.strokeBorder(LP.Colors.ink, lineWidth: 1.5)
            }
        }
    }
}

/// 数值读数 + `numBump` 动画 —— 对应原型 CSS keyframe:
/// ```
/// 0%, 100% { transform: scale(1);   color: ink;   }
/// 40%      { transform: scale(1.3); color: green; }
/// ```
/// 把数字 + 颜色弹一下，作为"刚刚被喂养 / 数据落地"的微反馈。`/100` 后缀不
/// 跟着弹，这样视觉重量集中在主数字上。`.onChange(of: value)` 只在变更时
/// 触发，首次渲染不弹。
private struct ValueReadout: View {
    let value: Int

    @State private var bumpScale: CGFloat = 1.0
    @State private var bumpColor: Color = LP.Colors.ink

    private static let bumpGreen = Color(hex: 0x3EB24E)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(value)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(bumpColor)
                .scaleEffect(bumpScale)
            Text("/100")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(LP.Colors.faint)
        }
        .frame(width: 42, alignment: .trailing)
        .onChange(of: value) { _, _ in
            withAnimation(.easeOut(duration: 0.2)) {
                bumpScale = 1.3
                bumpColor = Self.bumpGreen
            }
            Task {
                try? await Task.sleep(for: .seconds(0.2))
                withAnimation(.easeIn(duration: 0.3)) {
                    bumpScale = 1.0
                    bumpColor = LP.Colors.ink
                }
            }
        }
    }
}

#Preview {
    StatsTriadView(stats: [
        Stat(kind: .vitality, value: 88),
        Stat(kind: .energy,   value: 74),
        Stat(kind: .mood,     value: 82),
    ])
    .padding(LP.Spacing.s4)
    .lpPaper(.app)
}

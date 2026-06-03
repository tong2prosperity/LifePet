import SwiftUI

struct StarlightStatusView: View {
    let summaries: [StarlightSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s2) {
            HStack(spacing: LP.Spacing.s2) {
                Text(lp: "今日星光")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(LP.Colors.ink)
                Text(lp: "运动 + 睡眠")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(LP.Colors.muted)
                LPDashedRule(dash: [4, 3])
            }

            VStack(spacing: LP.Spacing.s2) {
                ForEach(summaries) { summary in
                    StarlightCard(summary: summary)
                }
            }
        }
    }
}

private struct StarlightCard: View {
    let summary: StarlightSummary

    var body: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s2) {
            HStack(alignment: .top, spacing: LP.Spacing.s3) {
                Image(systemName: summary.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(summary.level.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(summary.level.fill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(LP.Colors.ink, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.s2) {
                        Text(AppLocalization.text(summary.title))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(LP.Colors.ink)
                        Text(AppLocalization.text(summary.level.label))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(summary.level.accent)
                    }
                    Text(AppLocalization.text(summary.subtitle))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(LP.Colors.muted)
                    Text(AppLocalization.text(summary.source))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(LP.Colors.faint)
                }

                Spacer(minLength: LP.Spacing.s2)

                Text("\(summary.value)")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(summary.level.accent)
                    .frame(width: 42, alignment: .trailing)
            }

            ProgressTrack(progress: summary.progress, accent: summary.level.accent)
                .frame(height: 10)

            Text(AppLocalization.text(summary.level.detail))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(LP.Colors.ink2)
        }
        .lpStampedCard(fill: summary.level.fill)
    }
}

private struct ProgressTrack: View {
    let progress: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
            let clamped = min(1, max(0, progress))
            ZStack(alignment: .leading) {
                shape.fill(LP.Colors.paperCard.opacity(0.75))
                shape
                    .fill(accent)
                    .frame(width: max(0, geo.size.width * clamped))
                    .animation(.easeOut(duration: 0.55), value: clamped)
                shape.strokeBorder(LP.Colors.ink, lineWidth: 1)
            }
        }
    }
}

#Preview {
    StarlightStatusView(summaries: [
        StarlightSummary(id: .vitality, title: "活力星光", subtitle: "运动让 Pibo 更清醒", value: 82, source: "步数 · 运动分钟", symbol: "figure.walk"),
        StarlightSummary(id: .energy, title: "静息星光", subtitle: "睡眠让 Pibo 稳定醒来", value: 46, source: "睡眠 · 深睡 · REM", symbol: "moon.zzz.fill"),
    ])
    .padding(LP.Spacing.s4)
    .lpPaper(.app)
}

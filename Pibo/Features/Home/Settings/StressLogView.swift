import SwiftUI

/// 压力测量记录 — a plain, honest list of every stress computation Pibo has run
/// (RMSSD → tier), newest first, flagging the ones that fired a notification.
/// Reachable from 设置 →「压力测量记录」. Its whole job is to answer "到底有没有
/// 在算" — so it always shows the raw readings, notification or not.
struct StressLogView: View {
    @Environment(\.dismiss) private var dismiss

    /// Snapshotted on appear so the list is stable while open (App-Group reads).
    @State private var entries: [StressReading] = []

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: LP.Spacing.s) {
                            summary
                            ForEach(entries) { row($0) }
                        }
                        .padding(LP.Spacing.l)
                    }
                }
            }
            .background(LP.Fill.bgSurface)
            .navigationTitle(AppLocalization.text("压力测量记录"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.text("完成")) { dismiss() }
                }
            }
        }
        .onAppear { entries = StressLogStore.entries }
    }

    private var summary: some View {
        let notifiedCount = entries.filter(\.notified).count
        return HStack(spacing: LP.Spacing.xs) {
            Text(AppLocalization.format("共 %d 次测量", entries.count))
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.secondary)
            Text("·")
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.quarternary)
            Image(systemName: "bell.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LP.Fill.foundationAccent)
            Text(AppLocalization.format("%d 次通知", notifiedCount))
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Fill.foundationAccent)
            Spacer(minLength: 0)
        }
        .padding(.bottom, LP.Spacing.xs)
    }

    private func row(_ r: StressReading) -> some View {
        HStack(spacing: LP.Spacing.m) {
            // Tier tag.
            Text(AppLocalization.text(r.level.displayName))
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(r.level.tint)
                .padding(.horizontal, LP.Spacing.s)
                .padding(.vertical, 4)
                .background(Capsule().fill(r.level.bg))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.xs) {
                    Text(String(format: "%.0f", r.rmssd))
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Content.primary)
                    Text("RMSSD · ms")
                        .lpText(LP.Typography.c2Regular)
                        .foregroundStyle(LP.Content.quarternary)
                    if r.synthetic {
                        Text(AppLocalization.text("模拟"))
                            .lpText(LP.Typography.c2Regular)
                            .foregroundStyle(LP.Content.quarternary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(LP.Fill.bgSurfaceSecondary))
                    }
                }
                Text(timestamp(r.date))
                    .lpText(LP.Typography.c2Regular)
                    .foregroundStyle(LP.Content.tertiary)

                Text(baselineDetail(r))
                    .lpText(LP.Typography.c2Regular)
                    .foregroundStyle(LP.Content.quarternary)
            }

            Spacer(minLength: 0)

            // Whether it pushed.
            if r.notified {
                Label(AppLocalization.text("已通知"), systemImage: "bell.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LP.Fill.foundationAccent)
                    .accessibilityLabel(AppLocalization.text("已通知"))
            }
        }
        .padding(.horizontal, LP.Spacing.m)
        .padding(.vertical, LP.Spacing.s + 2)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
    }

    private var emptyState: some View {
        VStack(spacing: LP.Spacing.m) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(LP.Content.quarternary)
            Text(AppLocalization.text("还没有测到心搏序列"))
                .lpText(LP.Typography.b2Medium)
                .foregroundStyle(LP.Content.secondary)
            Text(AppLocalization.text("戴上 Apple Watch 过一会儿，Pibo 会自动测；测过就会出现在这里。"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(LP.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shows how this reading was judged — personal z-score vs. cold-start
    /// thresholds — so the individualized computation is verifiable.
    private func baselineDetail(_ r: StressReading) -> String {
        if let z = r.z {
            let base = r.baseline.map { String(format: "基线 %.0f ms · ", $0) } ?? ""
            let days = r.dayCount.map { "已学 \($0) 天 · " } ?? ""
            return base + days + String(format: "z %+.1f", z)
        }
        if let days = r.dayCount, days > 0 {
            return "个人化中 · 已学 \(days) 天 · 暂用通用阈值"
        }
        return "个人化中 · 暂用通用阈值"
    }

    private func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.current.locale
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: date)
    }
}

#Preview {
    StressLogView()
}

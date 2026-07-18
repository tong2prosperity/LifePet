import Charts
import SwiftUI

/// 睡眠周报 — the full "recent nights" surface on the history page (the morning
/// card carries a compact version). Averages + routine regularity + a per-night
/// bar chart + neutral guidance, all from `SleepWeeklyReport`. Shown today-only,
/// since it always summarizes the last 7 nights regardless of the selected day.
struct HistorySleepWeeklyCard: View {
    let report: SleepWeeklyReport

    var body: some View {
        HistoryCard(title: "睡眠周报", background: { LP.Fill.bgContainer }) {
            VStack(alignment: .leading, spacing: LP.Spacing.l) {
                statsRow
                nightlyChart
                if !report.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                        ForEach(report.suggestions, id: \.self) { tip in
                            HStack(alignment: .top, spacing: LP.Spacing.xs) {
                                Circle()
                                    .fill(LP.Colorful.purple300)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 6)
                                Text(AppLocalization.text(tip))
                                    .lpText(LP.Typography.c1Regular)
                                    .foregroundStyle(LP.Content.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, LP.Spacing.xl)
            .padding(.bottom, LP.Spacing.l)
        }
    }

    private var statsRow: some View {
        HStack(spacing: LP.Spacing.s) {
            stat("平均时长", value: report.averageDuration.map(Self.durationText))
            stat("平均就寝", value: report.averageBedtimeMinutes.map(SleepWeeklyReport.timeText))
            stat("平均起床", value: report.averageWakeMinutes.map(SleepWeeklyReport.timeText))
        }
    }

    @ViewBuilder
    private var nightlyChart: some View {
        if report.trend.contains(where: \.hasData) {
            Chart(report.trend) { point in
                BarMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("小时", point.sleep)
                )
                .foregroundStyle(point.hasData ? LP.Colorful.purple700 : LP.Neutral.grey250)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 10))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: 132)
        } else {
            Text(AppLocalization.text("最近还没有睡眠记录，先坚持记录几晚。"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, LP.Spacing.l)
        }
    }

    private func stat(_ label: String, value: String?, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xs) {
            Text(AppLocalization.text(label))
                .lpText(LP.Typography.c2Regular)
                .foregroundStyle(LP.Content.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.xs) {
                Text(value ?? "—")
                    .lpText(LP.Typography.uiH5)
                    .foregroundStyle(value == nil ? LP.Content.quarternary : LP.Content.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit, value != nil {
                    Text(unit)
                        .lpText(LP.Typography.c2Medium)
                        .foregroundStyle(LP.Content.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LP.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .strokeBorder(LP.Border.tertiary, lineWidth: 1)
        )
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return AppLocalization.format("%d 分钟", minutes) }
        if minutes == 0 { return AppLocalization.format("%d 小时", hours) }
        return AppLocalization.format("%d 小时 %d 分", hours, minutes)
    }
}

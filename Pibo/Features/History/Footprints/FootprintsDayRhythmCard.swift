import Charts
import SwiftUI

struct FootprintsDayRhythmCard: View {
    let day: FootprintsDaySnapshot
    @Binding var selectedHour: Int?

    private struct HourPoint: Identifiable {
        let hour: Int
        let steps: Int
        var id: Int { hour }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.l) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                    Text(AppLocalization.text("一天的脉络"))
                        .lpText(LP.Typography.uiH5)
                        .foregroundStyle(LP.Content.primary)
                    Text(AppLocalization.text("睡眠在上，脚步在下；拖动查看时刻"))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                }
                Spacer(minLength: LP.Spacing.s)
                selectedValue
            }

            SleepClockBand(segments: day.sleepSegments, start: day.sleepStart, end: day.sleepEnd)
                .frame(height: 30)

            Chart {
                ForEach(hourPoints) { point in
                    BarMark(
                        x: .value("小时", point.hour),
                        y: .value("步数", point.steps)
                    )
                    .foregroundStyle(barColor(for: point.hour))
                    .cornerRadius(2)
                }

                if let selectedHour {
                    RuleMark(x: .value("选中小时", selectedHour))
                        .foregroundStyle(LP.Content.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXScale(domain: -0.5...23.5)
            .chartYScale(domain: 0...chartMaximum)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisGridLine().foregroundStyle(LP.Separator.secondary)
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(hour == 23 ? "24" : "\(hour)")
                                .lpText(LP.Typography.c2Regular)
                                .foregroundStyle(LP.Content.quarternary)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartXSelection(value: $selectedHour)
            .frame(height: 124)
            .accessibilityLabel(AppLocalization.text("每小时脚步图"))
            .accessibilityHint(AppLocalization.text("左右拖动选择小时"))

            HStack(spacing: LP.Spacing.l) {
                legend(LP.Colorful.purple500, "睡眠阶段")
                legend(LP.Colorful.green500, "每小时脚步")
                Spacer(minLength: 0)
            }
        }
        .padding(LP.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .strokeBorder(LP.Border.tertiary, lineWidth: 1)
        )
    }

    private var hourPoints: [HourPoint] {
        (0..<24).map { hour in
            HourPoint(hour: hour, steps: hour < day.hourlySteps.count ? day.hourlySteps[hour] : 0)
        }
    }

    private var peakHour: Int? {
        hourPoints.filter { $0.steps > 0 }.max(by: { $0.steps < $1.steps })?.hour
    }

    private var resolvedHour: Int? { selectedHour ?? peakHour }

    private var selectedValue: some View {
        VStack(alignment: .trailing, spacing: LP.Spacing.xs) {
            Text(resolvedHour.map { String(format: "%02d:00", $0) } ?? "—")
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.tertiary)
            Text(resolvedHour.map { "\(hourPoints[$0].steps) 步" } ?? "暂无脚步")
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.primary)
                .contentTransition(.numericText())
        }
    }

    private var chartMaximum: Double {
        max(10, Double(hourPoints.map(\.steps).max() ?? 0) * 1.15)
    }

    private func barColor(for hour: Int) -> Color {
        if day.isToday, hour > Calendar.current.component(.hour, from: .now) {
            return LP.Colorful.green200.opacity(0.38)
        }
        return hour == resolvedHour ? LP.Colorful.green600 : LP.Colorful.green400
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: LP.Spacing.xs) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.c2Regular)
                .foregroundStyle(LP.Content.tertiary)
        }
    }
}

private struct SleepClockBand: View {
    let segments: [SleepSegmentValue]
    let start: Date?
    let end: Date?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(LP.Neutral.grey200)
                ForEach(Array(displayRanges.enumerated()), id: \.offset) { _, range in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color(for: range.stage))
                        .frame(width: max(3, geometry.size.width * (range.end - range.start) / 24))
                        .offset(x: geometry.size.width * range.start / 24)
                }
            }
            .clipShape(Capsule())
        }
        .accessibilityLabel(AppLocalization.text("睡眠时段"))
    }

    private struct ClockRange {
        let start: Double
        let end: Double
        let stage: SleepStage
    }

    private var displayRanges: [ClockRange] {
        let source: [SleepSegmentValue]
        if !segments.isEmpty {
            source = segments
        } else if let start, let end, end > start {
            source = [SleepSegmentValue(start: start, end: end, stage: .core)]
        } else {
            source = []
        }

        return source.flatMap { segment -> [ClockRange] in
            let startHour = fractionalHour(segment.start)
            let endHour = fractionalHour(segment.end)
            if endHour > startHour {
                return [ClockRange(start: startHour, end: endHour, stage: segment.stage)]
            }
            return [
                ClockRange(start: startHour, end: 24, stage: segment.stage),
                ClockRange(start: 0, end: endHour, stage: segment.stage),
            ]
        }
    }

    private func fractionalHour(_ date: Date) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
    }

    private func color(for stage: SleepStage) -> Color {
        switch stage {
        case .awake: LP.Colorful.yellow300
        case .rem: LP.Colorful.purple300
        case .core: LP.Colorful.blue400
        case .deep: LP.Colorful.purple700
        }
    }
}

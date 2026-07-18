import Charts
import SwiftUI

struct FootprintsTrendView: View {
    let points: [FootprintsTrendPoint]
    let appearance: PiboAppearance
    @Binding var range: FootprintsTrendRange
    @Binding var metric: FootprintsMetric
    @Binding var selectedDate: Date?
    let onOpenMetric: (FootprintsMetric) -> Void

    private var validPoints: [FootprintsTrendPoint] {
        points.filter { metric.hasValue($0.value(for: metric)) }
    }

    private var baseline: Double? {
        footprintsMedian(validPoints.map { $0.value(for: metric) })
    }

    private var selectedPoint: FootprintsTrendPoint? {
        guard let selectedDate else { return validPoints.last }
        return validPoints.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(spacing: LP.Spacing.xxl) {
            trendHero

            VStack(spacing: LP.Spacing.m) {
                HStack {
                    FootprintsSectionHeader(
                        "你的近期变化",
                        caption: "不是标准答案，只和自己的记录比较"
                    )
                    FootprintsScopeControl(
                        choices: FootprintsTrendRange.allCases.map { ($0, $0.title) },
                        selection: $range
                    )
                    .frame(width: 132)
                }

                metricPicker
                trendChart
            }

            metricSummaryGrid
            learningCard
                .id("learning")
        }
        .onChange(of: metric) { _, _ in selectedDate = nil }
        .onChange(of: range) { _, _ in selectedDate = nil }
    }

    private var trendHero: some View {
        HStack(spacing: LP.Spacing.l) {
            VStack(alignment: .leading, spacing: LP.Spacing.s) {
                Text("PIBO 看见的趋势")
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(LP.Content.accent)
                Text(trendFact)
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(trendEvidence)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: -10) {
                Text(AppLocalization.text(piboTrendLine))
                    .lpText(LP.Typography.c2Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LP.Spacing.s)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                            .fill(LP.Fill.bgPop)
                    )
                    .frame(width: 104)
                PiboPortraitView(appearance: appearance)
                    .frame(width: 98, height: 116)
            }
        }
        .padding(LP.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [LP.Colorful.green100, LP.Colorful.blue100.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .strokeBorder(LP.Border.tertiary, lineWidth: 1)
        )
    }

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: LP.Spacing.s) {
                ForEach(FootprintsMetric.allCases) { item in
                    Button {
                        guard metric != item else { return }
                        LPHaptics.tap()
                        withAnimation(.easeOut(duration: 0.2)) { metric = item }
                    } label: {
                        HStack(spacing: LP.Spacing.xs) {
                            Image(systemName: item.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(AppLocalization.text(item.title))
                                .lpText(LP.Typography.b4Medium)
                        }
                        .foregroundStyle(metric == item
                            ? LP.Fill.foundationOnAccent
                            : LP.Content.secondary)
                        .padding(.horizontal, LP.Spacing.m)
                        .padding(.vertical, LP.Spacing.s)
                        .background(
                            Capsule().fill(metric == item
                                ? item.tint
                                : LP.Fill.bgContainer)
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                metric == item ? Color.clear : LP.Border.tertiary,
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(metric == item ? .isSelected : [])
                }
            }
        }
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                if let point = selectedPoint {
                    Text(metric.formatted(point.value(for: metric)))
                        .lpText(LP.Typography.uiH3)
                        .foregroundStyle(LP.Content.primary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(metric.unit)
                        .lpText(LP.Typography.b4Medium)
                        .foregroundStyle(LP.Content.tertiary)
                    Text(Self.shortDate.string(from: point.date))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                        .padding(.leading, LP.Spacing.xs)
                } else {
                    Text("暂无可用数据")
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.tertiary)
                }
                Spacer(minLength: 0)
                if let baseline {
                    Text("个人中位数 \(metric.formatted(baseline)) \(metric.unit)")
                        .lpText(LP.Typography.c2Regular)
                        .foregroundStyle(LP.Content.tertiary)
                }
            }

            Chart {
                ForEach(validPoints) { point in
                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value(metric.title, point.value(for: metric))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [metric.tint.opacity(0.24), metric.tint.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("日期", point.date),
                        y: .value(metric.title, point.value(for: metric))
                    )
                    .foregroundStyle(metric.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    if range == .sevenDays || point.date == selectedPoint?.date {
                        PointMark(
                            x: .value("日期", point.date),
                            y: .value(metric.title, point.value(for: metric))
                        )
                        .foregroundStyle(metric.tint)
                        .symbolSize(point.date == selectedPoint?.date ? 64 : 24)
                    }
                }

                if let baseline {
                    RuleMark(y: .value("个人中位数", baseline))
                        .foregroundStyle(LP.Content.quarternary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                if let selectedPoint {
                    RuleMark(x: .value("选中日期", selectedPoint.date))
                        .foregroundStyle(LP.Content.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: range == .sevenDays ? 7 : 5)) { value in
                    AxisGridLine().foregroundStyle(LP.Separator.secondary)
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .foregroundStyle(LP.Content.quarternary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(LP.Separator.secondary)
                    AxisValueLabel().foregroundStyle(LP.Content.quarternary)
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 220)
            .accessibilityLabel(AppLocalization.text("\(metric.title)趋势图"))
            .accessibilityHint(AppLocalization.text("左右拖动查看每天的数据"))
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

    private var metricSummaryGrid: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            FootprintsSectionHeader(
                "个人常态",
                caption: "采用当前时间范围内的有效日中位数"
            )
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: LP.Spacing.s), GridItem(.flexible())],
                spacing: LP.Spacing.s
            ) {
                ForEach(FootprintsMetric.allCases) { item in
                    let values = points.map { $0.value(for: item) }.filter(item.hasValue)
                    Button {
                        LPHaptics.tap()
                        onOpenMetric(item)
                    } label: {
                        VStack(alignment: .leading, spacing: LP.Spacing.s) {
                            HStack {
                                Image(systemName: item.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(item.tint)
                                Text(AppLocalization.text(item.title))
                                    .lpText(LP.Typography.c1Medium)
                                    .foregroundStyle(LP.Content.tertiary)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(LP.Content.quarternary)
                            }
                            HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.xs) {
                                Text(footprintsMedian(values).map(item.formatted) ?? "—")
                                    .lpText(LP.Typography.uiH5)
                                    .foregroundStyle(LP.Content.primary)
                                Text(item.unit)
                                    .lpText(LP.Typography.c2Regular)
                                    .foregroundStyle(LP.Content.tertiary)
                            }
                            Text("\(values.count) 个有效日")
                                .lpText(LP.Typography.c2Regular)
                                .foregroundStyle(LP.Content.quarternary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(LP.Spacing.m)
                        .background(
                            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                                .fill(LP.Fill.bgContainer)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                                .strokeBorder(LP.Border.tertiary, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var learningCard: some View {
        let validDayCount = points.filter(\.hasData).count
        let target = 14
        let progress = min(1, Double(validDayCount) / Double(max(target, 1)))
        return VStack(alignment: .leading, spacing: LP.Spacing.m) {
            HStack {
                VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                    Text(AppLocalization.text(validDayCount >= 14 ? "已经能看见个人常态" : "Pibo 还在了解你"))
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Content.primary)
                    Text("\(validDayCount)/\(target) 个有效日")
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: validDayCount >= 14 ? "checkmark.seal.fill" : "ellipsis")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(LP.Fill.foundationAccent)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(LP.Neutral.grey250)
                    Capsule()
                        .fill(LP.Fill.foundationAccent)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 7)

            Text(AppLocalization.text(
                validDayCount >= 14
                    ? "现在可以比较趋势；还没有生活标签，因此不会编造行为与身体数据的关联。"
                    : "积累足够数据前，只展示事实，不判断好坏，也不生成关联结论。"
            ))
            .lpText(LP.Typography.b4Regular)
            .foregroundStyle(LP.Content.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LP.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .fill(LP.Colorful.green100.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .strokeBorder(LP.Colorful.green200, lineWidth: 1)
        )
    }

    private var trendFact: String {
        guard validPoints.count >= 4 else {
            return "还没有足够的数据判断变化"
        }
        let split = max(1, validPoints.count / 2)
        let earlier = footprintsMedian(validPoints.prefix(split).map { $0.value(for: metric) }) ?? 0
        let later = footprintsMedian(validPoints.suffix(from: split).map { $0.value(for: metric) }) ?? 0
        let delta = later - earlier
        guard abs(delta) > max(0.1, earlier * 0.04) else {
            return "近期的\(metric.title)和前半段很接近"
        }
        let direction = delta > 0 ? "高" : "低"
        return "近期的\(metric.title)比前半段\(direction)了 \(metric.formatted(abs(delta))) \(metric.unit)"
    }

    private var trendEvidence: String {
        "基于 \(validPoints.count) 个有效日 · 中位数比较 · 非医学结论"
    }

    private var piboTrendLine: String {
        if validPoints.count < 4 { return "再等等……还没看清。" }
        if selectedDate != nil { return "这一天，我记得。" }
        return "线不是命令……只是路。"
    }

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

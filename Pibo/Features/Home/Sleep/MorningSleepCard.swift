import Charts
import SwiftUI

/// Once-per-wake-day sheet shown over the home world, tuned for a calm just-woke
/// moment: one hero (how long you slept), the sleep-cloud visualization as the
/// single signature graphic, then quietly de-noised facts. No scores, no
/// per-tile decoration — durations, proportions, and clock times only.
struct MorningSleepCard: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: MorningSleepPresentation
    let appearance: PiboAppearance
    /// Built by the host (which owns store + history) so this view stays free of
    /// heavyweight @Environment and `#Preview` can pass a fixture directly.
    let weekly: SleepWeeklyReport

    @State private var bodyRecordsExpanded = true
    @State private var weeklyExpanded = false

    private var summary: MorningSleepSummary { presentation.summary }

    // A restrained nocturnal palette. Stage colors are the only hues that carry
    // meaning; everything else stays neutral ink.
    private static let deepTint = LP.Colorful.purple700
    private static let coreTint = LP.Colorful.blue400
    private static let remTint = LP.Colorful.purple300
    private static let awakeTint = LP.Neutral.grey400

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LP.Spacing.xl) {
                header
                hero
                piboNote

                HistorySleepCard(
                    totalSeconds: summary.total,
                    deepSeconds: summary.deep,
                    remSeconds: summary.rem,
                    start: summary.start,
                    end: summary.end,
                    segments: summary.segments,
                    showsDuration: false,
                    stageSummary: stageSummary
                )

                structureSection
                signalsSection
                weeklySection
                dataNote
            }
            .padding(.horizontal, LP.Spacing.l)
            .padding(.top, LP.Spacing.l)
            .padding(.bottom, LP.Spacing.xxl6)
        }
        .background(LP.Fill.bgSurface.ignoresSafeArea())
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(LP.Fill.bgSurface)
    }

    // MARK: Header + hero

    private var header: some View {
        HStack(alignment: .center, spacing: LP.Spacing.m) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Self.deepTint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(LP.Colorful.purple100))

            VStack(alignment: .leading, spacing: 1) {
                Text(titleText)
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(LP.Content.primary)
                Text(headerMetadata)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            Button {
                LPHaptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LP.Content.tertiary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LP.Fill.bgContainer))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.text("关闭"))
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(durationText(summary.total))
                .lpText(LP.Typography.uiH2)
                .foregroundStyle(LP.Content.primary)
                .monospacedDigit()
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            HStack(alignment: .center, spacing: LP.Spacing.s) {
                Text(AppLocalization.text("个人常态"))
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(Self.deepTint)
                    .padding(.horizontal, LP.Spacing.s)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                            .fill(LP.Colorful.purple100)
                    )
                Text(comparisonText)
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(LP.Content.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, LP.Spacing.xs)
    }

    /// A quiet personal sign-off — the portrait sits on the surface with no box,
    /// so Pibo reads as a note in the margin rather than a widget.
    private var piboNote: some View {
        HStack(alignment: .center, spacing: LP.Spacing.s) {
            PiboPortraitView(appearance: appearance)
                .frame(width: 30, height: 36)
            Text(piboLine)
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var stageSlices: [StageSlice] {
        [
            StageSlice(label: "深睡", seconds: summary.deep, tint: Self.deepTint),
            StageSlice(label: "浅睡", seconds: summary.core, tint: Self.coreTint),
            StageSlice(label: "眼动", seconds: summary.rem, tint: Self.remTint),
            StageSlice(label: "清醒", seconds: summary.awake, tint: Self.awakeTint),
        ]
    }

    private var stageSummary: [SleepStageSummaryValue] {
        guard summary.hasDetailedStages, summary.total > 0 else { return [] }
        let denom = max(1, summary.deep + summary.core + summary.rem + summary.awake)
        return stageSlices.filter { $0.seconds > 0 }.map { slice in
            SleepStageSummaryValue(
                label: slice.label,
                seconds: slice.seconds,
                percent: Int((slice.seconds / denom * 100).rounded()),
                tint: slice.tint
            )
        }
    }

    // MARK: Structure + body-signal facts

    private var structureSection: some View {
        factPanel(
            title: "睡眠结构",
            fill: LP.Fill.sleepStructure,
            border: LP.Border.sleepStructure,
            titleTint: Self.deepTint
        ) {
            HStack(alignment: .top, spacing: LP.Spacing.s) {
                statCell(
                    "夜醒",
                    value: summary.awakeningCount.map(String.init),
                    unit: "次"
                )
                factDivider(LP.Border.sleepStructure)
                statCell(
                    "入睡",
                    value: summary.sleepLatency.map { "\(Int(($0 / 60).rounded()))" },
                    unit: "分",
                    caption: summary.sleepLatency != nil ? AppLocalization.text("估") : nil
                )
                factDivider(LP.Border.sleepStructure)
                statCell(
                    "睡着占记录",
                    value: summary.continuity.map { "\(Int(($0 * 100).rounded()))" },
                    unit: "%"
                )
            }
        }
    }

    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.l) {
            Button {
                LPHaptics.tap()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    bodyRecordsExpanded.toggle()
                }
            } label: {
                HStack(spacing: LP.Spacing.s) {
                    Circle()
                        .fill(LP.Colorful.blue600)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(AppLocalization.text("夜间身体记录"))
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.secondary)
                    Spacer(minLength: 0)
                    disclosureLabel(expanded: bodyRecordsExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.text("夜间身体记录"))
            .accessibilityValue(bodyRecordsExpanded
                ? AppLocalization.text("已展开")
                : AppLocalization.text("已收起"))

            if bodyRecordsExpanded {
                HStack(alignment: .top, spacing: LP.Spacing.xs) {
                    bodyFact(
                        "HRV",
                        symbol: "waveform.path.ecg",
                        tint: Self.deepTint,
                        iconFill: LP.Colorful.purple100,
                        value: summary.overnightHRV.map { "\(Int($0.rounded()))" },
                        unit: "ms"
                    )
                    factDivider(LP.Border.sleepBody)
                    bodyFact(
                        "平均心率",
                        symbol: "heart",
                        tint: LP.Colorful.blue500,
                        iconFill: LP.Colorful.blue100,
                        value: summary.sleepHeartRateAverage.map { "\(Int($0.rounded()))" },
                        unit: "bpm"
                    )
                    factDivider(LP.Border.sleepBody)
                    bodyFact(
                        "最低心率",
                        symbol: "heart.fill",
                        tint: LP.Colorful.purple500,
                        iconFill: LP.Colorful.purple100,
                        value: summary.sleepHeartRateMin.map { "\(Int($0.rounded()))" },
                        unit: "bpm"
                    )
                    factDivider(LP.Border.sleepBody)
                    bodyFact(
                        "腕温",
                        symbol: "thermometer",
                        tint: Self.deepTint,
                        iconFill: LP.Colorful.purple100,
                        value: summary.sleepingWristTemperature.map { String(format: "%.1f", $0) },
                        unit: "℃"
                    )
                }
                .transition(.opacity)
            }
        }
        .padding(LP.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .fill(LP.Fill.sleepBody)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .strokeBorder(LP.Border.sleepBody, lineWidth: 1)
        )
    }

    // MARK: Recent nights

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                LPHaptics.tap()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    weeklyExpanded.toggle()
                }
            } label: {
                HStack(spacing: LP.Spacing.m) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Self.deepTint)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(LP.Colorful.purple100))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLocalization.format(
                            "最近趋势 · 已记录 %d/7 晚",
                            weekly.nightsWithData
                        ))
                            .lpText(LP.Typography.b4Medium)
                            .foregroundStyle(LP.Content.secondary)
                        Text(weeklySummaryText)
                            .lpText(LP.Typography.c1Regular)
                            .foregroundStyle(LP.Content.tertiary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: weeklyExpanded ? "chevron.up" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LP.Content.tertiary)
                        .frame(width: 44, height: 44)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.text("最近趋势"))
            .accessibilityValue(weeklyExpanded ? AppLocalization.text("已展开") : AppLocalization.text("已收起"))

            if weeklyExpanded {
                Divider()
                    .overlay(LP.Separator.secondary)
                    .padding(.vertical, LP.Spacing.l)
                statGrid {
                    statCell("平均时长", value: weekly.averageDuration.map(compactDuration))
                    statCell("平均就寝", value: weekly.averageBedtimeMinutes.map(SleepWeeklyReport.timeText))
                    statCell("平均起床", value: weekly.averageWakeMinutes.map(SleepWeeklyReport.timeText))
                }
                SleepSparkline(points: weekly.trend, tint: Self.deepTint)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                if let tip = weekly.suggestions.first {
                    Text(AppLocalization.text(tip))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(LP.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .strokeBorder(LP.Border.tertiary, lineWidth: 1)
        )
    }

    private var dataNote: some View {
        Text(AppLocalization.text("数据来自 HealthKit。— 表示这一晚没有可用记录；不代表设备异常，也不用于医疗判断。"))
            .lpText(LP.Typography.c2Regular)
            .foregroundStyle(LP.Content.quarternary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, LP.Spacing.xs)
    }

    // MARK: Reusable chrome

    private func factPanel<Content: View>(
        title: String,
        fill: Color,
        border: Color,
        titleTint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.l) {
            HStack(spacing: LP.Spacing.s) {
                Circle()
                    .fill(titleTint)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(AppLocalization.text(title))
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.secondary)
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(LP.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        )
    }

    private func disclosureLabel(expanded: Bool) -> some View {
        HStack(spacing: LP.Spacing.xs) {
            Text(AppLocalization.text(expanded ? "收起" : "展开"))
                .lpText(LP.Typography.c1Regular)
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(LP.Content.tertiary)
        .frame(minHeight: 44)
    }

    private func factDivider(_ color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 1, height: 58)
            .accessibilityHidden(true)
    }

    private func statGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: 3),
            alignment: .leading,
            spacing: LP.Spacing.l
        ) {
            content()
        }
    }

    /// Borderless fact cell: quiet label over the value. No capsule, no frame —
    /// the panel groups them; whitespace does the separating.
    private func statCell(_ label: String, value: String?, unit: String? = nil, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(AppLocalization.text(label))
                .lpText(LP.Typography.c2Regular)
                .foregroundStyle(LP.Content.tertiary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value ?? "—")
                    .lpText(LP.Typography.uiH5)
                    .foregroundStyle(value == nil ? LP.Content.quarternary : LP.Content.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit, value != nil {
                    Text(unit)
                        .lpText(LP.Typography.c2Medium)
                        .foregroundStyle(LP.Content.quarternary)
                }
            }
            if let caption {
                Text(caption)
                    .lpText(LP.Typography.c2Regular)
                    .foregroundStyle(LP.Content.quarternary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func bodyFact(
        _ label: String,
        symbol: String,
        tint: Color,
        iconFill: Color,
        value: String?,
        unit: String
    ) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(iconFill))
                .accessibilityHidden(true)
            Text(AppLocalization.text(label))
                .lpText(LP.Typography.c2Regular)
                .foregroundStyle(LP.Content.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value ?? "—")
                    .lpText(LP.Typography.uiH5)
                    .foregroundStyle(value == nil ? LP.Content.quarternary : LP.Content.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if value != nil {
                    Text(unit)
                        .lpText(LP.Typography.c2Regular)
                        .foregroundStyle(LP.Content.quarternary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private struct StageSlice: Identifiable {
        var id: String { label }
        let label: String
        let seconds: TimeInterval
        let tint: Color
    }

    // MARK: Copy + formatting

    private var comparisonText: String {
        guard let delta = summary.baselineDelta else {
            let count = summary.baselineSampleCount ?? 0
            return count > 0
                ? AppLocalization.format("已记录 %d 晚 · 还在积累", count)
                : AppLocalization.text("数据还在积累")
        }
        let minutes = Int((abs(delta) / 60).rounded())
        let count = summary.baselineSampleCount ?? 0
        let difference = minutes < 5
            ? AppLocalization.text("和平时差不多")
            : AppLocalization.format(delta > 0 ? "多 %d 分钟" : "少 %d 分钟", minutes)
        guard count > 0 else { return difference }
        return AppLocalization.format("%@ · 基于 %d 晚", difference, count)
    }

    private var piboLine: String {
        if presentation.isCatchUp { return MorningSleepCopy.cardPiboCatchUpLine }
        guard let delta = summary.baselineDelta else { return MorningSleepCopy.cardPiboLine }
        let minutes = Int((abs(delta) / 60).rounded())
        if minutes < 5 { return AppLocalization.text("昨晚和平时睡得差不多。") }
        return AppLocalization.text(delta > 0
            ? "昨晚睡得比平时久一点。"
            : "昨晚睡得比平时少一点。")
    }

    private var weeklySummaryText: String {
        if weekly.nightsWithData < 5 { return AppLocalization.text("数据还在积累") }
        if let tip = weekly.suggestions.first { return AppLocalization.text(tip) }
        return AppLocalization.text("查看近 7 晚的睡眠变化")
    }

    private var headerMetadata: String {
        let range = "\(Self.time.string(from: summary.start))–\(Self.time.string(from: summary.end))"
        guard !presentation.isCatchUp else { return range }
        return "\(Self.day.string(from: summary.end)) · \(range)"
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return AppLocalization.format("%d 分钟", minutes) }
        if minutes == 0 { return AppLocalization.format("%d 小时", hours) }
        return AppLocalization.format("%d 小时 %d 分", hours, minutes)
    }

    /// Tighter form for the small weekly cell ("6h30").
    private func compactDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h\(String(format: "%02d", minutes))"
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    /// A card opened on a later day is a dated retrospective, not "last night" —
    /// saying 昨夜 there would misdate the night the user is looking at.
    private var titleText: String {
        guard presentation.isCatchUp else { return AppLocalization.text("昨夜睡眠") }
        return "\(Self.day.string(from: summary.wakeDay))\(AppLocalization.text("的睡眠"))"
    }
}

/// 7-night sleep-hours line with a soft area fill and the most recent night
/// highlighted. Pure (takes prebuilt points) so both hosts and `#Preview` feed
/// it without a live store.
private struct SleepSparkline: View {
    let points: [FootprintsTrendPoint]
    var tint: Color = LP.Colorful.purple700

    private var withData: [FootprintsTrendPoint] { points.filter(\.hasData) }

    private var yMax: Double {
        max(9, (withData.map(\.sleep).max() ?? 8).rounded(.up) + 1)
    }

    var body: some View {
        if withData.isEmpty {
            Text(AppLocalization.text("趋势数据还在积累"))
                .lpText(LP.Typography.c2Regular)
                .foregroundStyle(LP.Content.quarternary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Chart {
                ForEach(withData) { point in
                    AreaMark(
                        x: .value("日期", point.date),
                        yStart: .value("基线", 0),
                        yEnd: .value("小时", point.sleep)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [tint.opacity(0.20), tint.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("小时", point.sleep)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .foregroundStyle(tint)
                }
                if let latest = withData.last {
                    PointMark(
                        x: .value("日期", latest.date),
                        y: .value("小时", latest.sleep)
                    )
                    .symbolSize(70)
                    .foregroundStyle(tint)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...yMax)
        }
    }
}

#Preview {
    let calendar = Calendar.current
    let end = calendar.date(bySettingHour: 7, minute: 18, second: 0, of: .now) ?? .now
    let start = end.addingTimeInterval(-7.3 * 3_600)
    let deepEnd = start.addingTimeInterval(75 * 60)
    let coreEnd = deepEnd.addingTimeInterval(3.8 * 3_600)
    let remEnd = coreEnd.addingTimeInterval(95 * 60)
    let trend = (0..<7).map { offset in
        FootprintsTrendPoint(
            date: calendar.date(byAdding: .day, value: -6 + offset, to: .now) ?? .now,
            steps: 0,
            sleep: 6.4 + Double(offset % 3) * 0.6,
            activeEnergy: 0,
            hrv: 0,
            hasData: true
        )
    }
    let weekly = SleepWeeklyReport(
        nightsWithData: 7,
        averageDuration: 7.1 * 3_600,
        averageBedtimeMinutes: 23 * 60 + 42,
        averageWakeMinutes: 7 * 60 + 5,
        averageScore: 82,
        regularity: 76,
        suggestions: ["最近睡眠质量不错，保持下去。"],
        trend: trend
    )
    return MorningSleepCard(presentation: MorningSleepPresentation(
        summary: MorningSleepSummary(
            wakeDay: calendar.startOfDay(for: end),
            generatedAt: .now,
            start: start,
            end: end,
            total: 7.3 * 3_600,
            core: 4.45 * 3_600,
            deep: 75 * 60,
            rem: 95 * 60,
            awake: 18 * 60,
            segments: [
                SleepSegmentValue(start: start, end: deepEnd, stage: .deep),
                SleepSegmentValue(start: deepEnd, end: coreEnd, stage: .core),
                SleepSegmentValue(start: coreEnd, end: remEnd, stage: .rem),
            ],
            hasDetailedStages: true,
            hasInBedSignal: true,
            hasTerminalAwakeSignal: true,
            awakeningCount: 2,
            continuity: 0.93,
            baselineDelta: 24 * 60,
            baselineSampleCount: 8,
            overnightHRV: 46,
            sleepingWristTemperature: 33.2,
            sleepingWristTemperatureDelta: 0.2,
            respiratoryRate: 14.2,
            oxygenSaturation: nil,
            sleepHeartRateAverage: 57,
            sleepHeartRateMin: 49,
            sleepLatency: 12 * 60
        ),
        isSettled: true,
        isCatchUp: false
    ), appearance: .default, weekly: weekly)
}

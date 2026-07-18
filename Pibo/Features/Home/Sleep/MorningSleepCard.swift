import Charts
import SwiftUI

/// Once-per-wake-day sheet shown over the home world, tuned for a calm just-woke
/// moment: one hero (how long you slept), the sleep-cloud visualization as the
/// single signature graphic, then quietly de-noised facts. No scores, no
/// per-tile decoration — durations, proportions, and clock times only.
struct MorningSleepCard: View {
    @Environment(\.dismiss) private var dismiss

    let summary: MorningSleepSummary
    let appearance: PiboAppearance
    /// Built by the host (which owns store + history) so this view stays free of
    /// heavyweight @Environment and `#Preview` can pass a fixture directly.
    let weekly: SleepWeeklyReport

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
                    showsDuration: false
                )

                if summary.hasDetailedStages, summary.total > 0 {
                    stagesSection
                }
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
                Text(AppLocalization.text("昨夜睡眠"))
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(LP.Content.primary)
                Text("\(Self.time.string(from: summary.start)) – \(Self.time.string(from: summary.end))")
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
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(LP.Fill.bgContainer))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.text("关闭"))
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xs) {
            Text(durationText(summary.total))
                .lpText(LP.Typography.uiH2)
                .foregroundStyle(LP.Content.primary)
                .monospacedDigit()
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(comparisonText)
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(LP.Content.tertiary)
        }
        .padding(.top, LP.Spacing.xs)
    }

    /// A quiet personal sign-off — the portrait sits on the surface with no box,
    /// so Pibo reads as a note in the margin rather than a widget.
    private var piboNote: some View {
        HStack(alignment: .center, spacing: LP.Spacing.s) {
            PiboPortraitView(appearance: appearance)
                .frame(width: 30, height: 36)
            Text(MorningSleepCopy.cardPiboLine)
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Sleep stages (merged bar + rows)

    private var stagesSection: some View {
        section("睡眠阶段") {
            panel {
                stageBar
                VStack(spacing: LP.Spacing.s) {
                    ForEach(stageSlices) { slice in
                        if slice.seconds > 0 {
                            stageRow(slice)
                        }
                    }
                }
            }
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

    private var stageBar: some View {
        let denom = max(1, summary.deep + summary.core + summary.rem + summary.awake)
        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(stageSlices) { slice in
                    if slice.seconds > 0 {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(slice.tint)
                            .frame(width: max(3, geo.size.width * (slice.seconds / denom) - 2))
                    }
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func stageRow(_ slice: StageSlice) -> some View {
        let denom = max(1, summary.deep + summary.core + summary.rem + summary.awake)
        let pct = Int((slice.seconds / denom * 100).rounded())
        return HStack(spacing: LP.Spacing.s) {
            Circle().fill(slice.tint).frame(width: 8, height: 8)
            Text(AppLocalization.text(slice.label))
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.secondary)
            Spacer(minLength: 0)
            Text(durationText(slice.seconds))
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.primary)
                .monospacedDigit()
            Text("\(pct)%")
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.quarternary)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Structure + body-signal facts (de-noised)

    private var structureSection: some View {
        section("睡眠结构") {
            panel {
                statGrid {
                    statCell(
                        "连续性",
                        value: summary.continuity.map { "\(Int(($0 * 100).rounded()))" },
                        unit: "%"
                    )
                    statCell(
                        "夜醒",
                        value: summary.awakeningCount.map(String.init),
                        unit: "次"
                    )
                    statCell(
                        "入睡用时",
                        value: summary.sleepLatency.map { "\(Int(($0 / 60).rounded()))" },
                        unit: "分",
                        caption: summary.sleepLatency != nil ? AppLocalization.text("估算") : nil
                    )
                }
            }
        }
    }

    private var signalsSection: some View {
        section("夜间指标") {
            panel {
                statGrid {
                    statCell(
                        "腕温",
                        value: summary.sleepingWristTemperature.map { String(format: "%.1f", $0) },
                        unit: "℃",
                        caption: wristTemperatureCaption
                    )
                    statCell(
                        "HRV",
                        value: summary.overnightHRV.map { "\(Int($0.rounded()))" },
                        unit: "ms"
                    )
                    statCell(
                        "平均心率",
                        value: summary.sleepHeartRateAverage.map { "\(Int($0.rounded()))" },
                        unit: "bpm"
                    )
                    statCell(
                        "最低心率",
                        value: summary.sleepHeartRateMin.map { "\(Int($0.rounded()))" },
                        unit: "bpm"
                    )
                    statCell(
                        "呼吸",
                        value: summary.respiratoryRate.map { String(format: "%.1f", $0) },
                        unit: "次/分"
                    )
                    statCell(
                        "血氧",
                        value: summary.oxygenSaturation.map { String(format: "%.0f", $0 * 100) },
                        unit: "%"
                    )
                }
            }
        }
    }

    // MARK: Recent nights

    private var weeklySection: some View {
        section("近 7 晚") {
            panel {
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
    }

    private var dataNote: some View {
        Text(AppLocalization.text("数据来自 HealthKit。— 表示这一晚没有可用记录；不代表设备异常，也不用于医疗判断。"))
            .lpText(LP.Typography.c2Regular)
            .foregroundStyle(LP.Content.quarternary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, LP.Spacing.xs)
    }

    // MARK: Reusable chrome

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.tertiary)
                .textCase(nil)
            content()
        }
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.l) {
            content()
        }
        .padding(LP.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
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

    private struct StageSlice: Identifiable {
        var id: String { label }
        let label: String
        let seconds: TimeInterval
        let tint: Color
    }

    // MARK: Copy + formatting

    private var comparisonText: String {
        guard let delta = summary.baselineDelta else {
            return AppLocalization.text("个人常态仍在积累")
        }
        let minutes = Int((abs(delta) / 60).rounded())
        if minutes < 5 { return AppLocalization.text("接近你的近期个人常态") }
        return AppLocalization.format(
            "比近期个人常态%@ %d 分钟",
            delta > 0 ? "多睡" : "少睡",
            minutes
        )
    }

    private var wristTemperatureCaption: String? {
        guard let delta = summary.sleepingWristTemperatureDelta else { return nil }
        return AppLocalization.format(
            "基线 %@%.1f",
            delta >= 0 ? "+" : "",
            delta
        )
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
    return MorningSleepCard(summary: MorningSleepSummary(
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
        overnightHRV: 46,
        sleepingWristTemperature: 33.2,
        sleepingWristTemperatureDelta: 0.2,
        respiratoryRate: 14.2,
        oxygenSaturation: nil,
        sleepHeartRateAverage: 57,
        sleepHeartRateMin: 49,
        sleepLatency: 12 * 60
    ), appearance: .default, weekly: weekly)
}

import SwiftUI

/// Shared sleep detail sheet (Harmony-first 2026-09-09 「连续云雾睡眠展开详情」),
/// used by the history 「展开睡眠详情」 button and by the morning card.
///
/// Everything shown comes from one `SleepNightDetail`; missing values read
/// "—" / 未记录, an explicit 0 stays 0, and no curve, stage or baseline is
/// invented for a night that does not carry it.
struct SleepDetailContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let detail: SleepNightDetail
    let history: HealthHistoryStore
    /// DEBUG fixture routes label the sheet so it can never pass for real data.
    var debugNotice: String?
    let onClose: () -> Void

    @State private var showsMiniTrail = false
    @State private var bodyExpanded = true
    @State private var trendExpanded = false

    private static let ink = Color(hex: 0xF6EFE6)
    private static let secondaryInk = Color(hex: 0xB6BED0)
    private static let tertiaryInk = Color(hex: 0x8D97AC)
    private static let quietInk = Color(hex: 0xA5AEC2)
    private static let missingInk = Color(hex: 0x7F899C)
    private static let rule = Color(hex: 0x4B6176, alpha: 0x24 / 255)

    var body: some View {
        let _ = history.revision
        VStack(spacing: 0) {
            if let debugNotice {
                Text(debugNotice)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color(hex: 0xB4452F))
            }
            header
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)
            if showsMiniTrail, let timeline = trailTimeline {
                SleepCloudTrailCanvas(
                    segments: detail.plottedSegments,
                    timeline: timeline,
                    center: 13,
                    heightScale: 0.3
                )
                .frame(height: 26)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
            ScrollView(showsIndicators: false) {
                content
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                let next = offset > 180 ? true : (offset < 100 ? false : showsMiniTrail)
                guard next != showsMiniTrail else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    showsMiniTrail = next
                }
            }
        }
        .background(
            LinearGradient(
                colors: [Color(hex: 0x232B3B), Color(hex: 0x1A2230)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var trailTimeline: SleepTrailTimeline? {
        SleepTrailGeometry.timeline(
            segments: detail.plottedSegments,
            fallbackStart: detail.start,
            fallbackEnd: detail.end
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(AppLocalization.text("睡眠详情"))
                    .font(.system(size: 18))
                    .foregroundStyle(Self.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(Self.dayText(detail.wakeDay))
                    .font(.system(size: 12))
                    .foregroundStyle(Self.quietInk)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xC4CBDC))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.text("关闭睡眠详情"))
        }
    }

    // MARK: Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            overview
            if detail.hasStages {
                HistorySleepCard(
                    totalSeconds: detail.total,
                    start: detail.start,
                    end: detail.end,
                    segments: detail.segments,
                    embedded: true
                )
                .padding(.top, 20)
                Text(AppLocalization.text("轻点云雾，查看阶段时间"))
                    .font(.system(size: 11))
                    .foregroundStyle(Self.tertiaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
            }
            rule
            stages
            rule
            structure
            rule
            nightBody
            rule
            trend
            rule
            footer
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            if detail.total > 0 {
                let minutes = Int((detail.total / 60).rounded(.down))
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(minutes / 60)").font(.system(size: 46, weight: .light))
                    Text(AppLocalization.text("小时")).font(.system(size: 23))
                    Text("\(minutes % 60)").font(.system(size: 46, weight: .light))
                    Text(AppLocalization.text("分")).font(.system(size: 23))
                }
                .foregroundStyle(Self.ink)
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(AppLocalization.format("睡眠 %d 小时 %d 分", minutes / 60, minutes % 60))
            } else {
                Text(AppLocalization.text("暂无睡眠数据"))
                    .font(.system(size: 26))
                    .foregroundStyle(Self.quietInk)
            }
            Text("\(SleepTrailFormat.clock(detail.start)) — \(SleepTrailFormat.clock(detail.end))")
                .font(.system(size: 16))
                .foregroundStyle(Self.secondaryInk)
                .monospacedDigit()
            let baseline = SleepDetailFormat.baseline(
                delta: detail.baselineDelta,
                sampleCount: detail.baselineSampleCount
            )
            if !baseline.isEmpty {
                Text(baseline)
                    .font(.system(size: 12))
                    .foregroundStyle(Self.quietInk)
            }
        }
        .padding(.top, 8)
    }

    private var rule: some View {
        Rectangle()
            .fill(Self.rule)
            .frame(height: 1)
            .padding(.vertical, 18)
            .accessibilityHidden(true)
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(AppLocalization.text(key))
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Self.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Stages

    @ViewBuilder
    private var stages: some View {
        sectionTitle("睡眠阶段")
        if detail.hasStages {
            VStack(spacing: 16) {
                ForEach(detail.stageStats) { stat in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(SleepTrailPalette.color(stat.stage))
                            .frame(width: 8, height: 8)
                        Text(stat.stage.trailDisplayName)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: 0xC4CBDC))
                            .frame(width: 32, alignment: .leading)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(hex: 0x303A50))
                                Capsule()
                                    .fill(SleepTrailPalette.color(stat.stage))
                                    .frame(width: geometry.size.width * CGFloat(min(100, stat.percent) / 100))
                            }
                        }
                        .frame(height: 9)
                        .accessibilityHidden(true)
                        Text(SleepDetailFormat.duration(stat.seconds))
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: 0xE7E3E5))
                            .monospacedDigit()
                            .frame(width: 87, alignment: .trailing)
                        Text(SleepDetailFormat.percent(stat.percent))
                            .font(.system(size: 11))
                            .foregroundStyle(Self.quietInk)
                            .monospacedDigit()
                            .frame(width: 46, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(stat.stage.trailDisplayName)
                    .accessibilityValue("\(SleepDetailFormat.duration(stat.seconds))，\(SleepDetailFormat.percent(stat.percent))")
                }
            }
            .padding(.top, 18)
            Text(AppLocalization.format(
                "占已记录阶段时长（共 %@）；未记录的区间留空，不计入",
                SleepDetailFormat.duration(detail.recordedStageSeconds)
            ))
            .font(.system(size: 10))
            .foregroundStyle(Self.tertiaryInk)
            .padding(.top, 12)
        } else {
            Text(AppLocalization.text(detail.total > 0 ? "缺少阶段记录" : "暂无睡眠阶段记录"))
                .font(.system(size: 13))
                .foregroundStyle(Self.tertiaryInk)
                .padding(.top, 12)
        }
    }

    // MARK: Structure

    private var structure: some View {
        HStack(alignment: .top, spacing: 14) {
            fact("入睡耗时", SleepDetailFormat.duration(detail.plausibleLatency))
            fact(
                "夜间醒来",
                detail.providerAwakeningCount.map { AppLocalization.format("%d 次", $0) } ?? "—",
                caption: detail.recordedAwakeIntervals.map {
                    AppLocalization.format("记录到 %d 段清醒", $0)
                }
            )
            fact("在床时长", SleepDetailFormat.duration(detail.plausibleInBed))
        }
    }

    private func fact(_ label: String, _ value: String, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(AppLocalization.text(label))
                .font(.system(size: 11))
                .foregroundStyle(Self.secondaryInk)
            Text(value)
                .font(.system(size: 16))
                .foregroundStyle(value == "—" ? Self.missingInk : Self.ink)
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(Self.tertiaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Night body

    @ViewBuilder
    private var nightBody: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                bodyExpanded.toggle()
            }
        } label: {
            HStack {
                Text(AppLocalization.text("夜间身体记录"))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Self.ink)
                Spacer(minLength: 0)
                Image(systemName: bodyExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Self.secondaryInk)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("夜间身体记录"))
        .accessibilityValue(AppLocalization.text(bodyExpanded ? "已展开" : "已收起"))

        if bodyExpanded {
            VStack(alignment: .leading, spacing: 0) {
                Text(AppLocalization.text("仅展示睡眠时段内的测量"))
                    .font(.system(size: 11))
                    .foregroundStyle(Self.tertiaryInk)
                    .padding(.bottom, 20)
                HStack(alignment: .top, spacing: 24) {
                    metric("平均心率", detail.nightValue(detail.sleepHeartRateAverage), unit: "bpm")
                    metric("最低心率", detail.nightValue(detail.sleepHeartRateMinimum), unit: "bpm")
                }
                rule
                HStack(alignment: .top, spacing: 24) {
                    metric("夜间 HRV", detail.nightValue(detail.overnightHRVSDNN), unit: "ms",
                           caption: "SDNN · 中位数")
                    metric("血氧饱和度", detail.nightValue(detail.oxygenSaturation).map { $0 * 100 },
                           unit: "%", caption: "夜间中位数")
                }
                rule
                HStack(alignment: .top, spacing: 24) {
                    metric("手腕温度", detail.nightValue(detail.wristTemperature), unit: "℃",
                           digits: 1, caption: "夜间中位数")
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
            .transition(.opacity)
        }
    }

    private func metric(
        _ label: String,
        _ value: Double?,
        unit: String,
        digits: Int = 0,
        caption: String? = nil
    ) -> some View {
        let text = SleepDetailFormat.number(value, digits: digits)
        return VStack(alignment: .leading, spacing: 6) {
            Text(AppLocalization.text(label))
                .font(.system(size: 12))
                .foregroundStyle(Self.secondaryInk)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(text)
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(value == nil ? Self.missingInk : Self.ink)
                    .monospacedDigit()
                if value != nil {
                    Text(unit)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0xC4CBDC))
                }
            }
            if let caption {
                Text(AppLocalization.text(value == nil ? "未记录" : caption))
                    .font(.system(size: 11))
                    .foregroundStyle(Self.tertiaryInk)
            } else if value == nil {
                Text(AppLocalization.text("未记录"))
                    .font(.system(size: 11))
                    .foregroundStyle(Self.tertiaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.text(label))
        .accessibilityValue(value == nil ? AppLocalization.text("未记录") : "\(text) \(unit)")
    }

    // MARK: Trend

    private var trendDays: [SleepNightDetail.TrendDay] {
        detail.trendDays { history.record(on: $0)?.sleepTotal }
    }

    @ViewBuilder
    private var trend: some View {
        let days = trendDays
        let maxHours = max(8, (days.compactMap(\.seconds).max() ?? 0) / 3600).rounded(.up)
        sectionTitle("最近7晚")
        Text(AppLocalization.text("每晚睡眠时长"))
            .font(.system(size: 11))
            .foregroundStyle(Self.tertiaryInk)
            .padding(.top, 6)
            .padding(.bottom, 12)
        HStack(alignment: .bottom, spacing: 10) {
            VStack {
                Text("\(Int(maxHours))h")
                Spacer(minLength: 0)
                Text("0h")
            }
            .font(.system(size: 10))
            .foregroundStyle(Self.tertiaryInk)
            .frame(height: 82)
            .padding(.bottom, 20)
            .accessibilityHidden(true)
            ForEach(days) { day in
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        Color.clear
                        if let seconds = day.seconds {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [SleepTrailPalette.rem, Color(hex: 0x788EE1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .frame(width: 18, height: max(2, CGFloat(seconds / 3600 / maxHours) * 82))
                        } else {
                            Text("—")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(hex: 0x647086))
                        }
                    }
                    .frame(height: 82)
                    Text("\(Calendar.current.component(.day, from: day.date))")
                        .font(.system(size: 10))
                        .foregroundStyle(Self.secondaryInk)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.dayText(day.date))
                .accessibilityValue(day.seconds.map { SleepDetailFormat.duration($0) } ?? AppLocalization.text("未记录"))
            }
        }
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                trendExpanded.toggle()
            }
        } label: {
            Text(AppLocalization.text(trendExpanded ? "收起睡眠趋势" : "查看睡眠趋势"))
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0xC4CBDC))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if trendExpanded {
            weeklyFacts(days: days)
                .transition(.opacity)
        }
    }

    private func weeklyFacts(days: [SleepNightDetail.TrendDay]) -> some View {
        let report = SleepWeeklyReport.make(
            history: history,
            endDay: detail.wakeDay,
            live: detail.total > 0
                ? .init(
                    total: detail.total,
                    deep: detail.stageStats.first { $0.stage == .deep }?.seconds ?? 0,
                    rem: detail.stageStats.first { $0.stage == .rem }?.seconds ?? 0,
                    awake: detail.stageStats.first { $0.stage == .awake }?.seconds ?? 0,
                    start: detail.start,
                    end: detail.end
                )
                : nil
        )
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                fact("平均时长", SleepDetailFormat.duration(report.averageDuration))
                fact("平均入睡", report.averageBedtimeMinutes.map(SleepWeeklyReport.timeText) ?? "—")
                fact("平均醒来", report.averageWakeMinutes.map(SleepWeeklyReport.timeText) ?? "—")
            }
            .padding(.top, 18)
            .padding(.bottom, 12)
            Text(AppLocalization.format("基于 %d 晚", report.nightsWithData))
                .font(.system(size: 11))
                .foregroundStyle(Self.tertiaryInk)
            ForEach(report.suggestions, id: \.self) { suggestion in
                Text(AppLocalization.text(suggestion))
                    .font(.system(size: 12))
                    .foregroundStyle(Self.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            ForEach(days) { day in
                HStack {
                    Text(Self.dayText(day.date))
                    Spacer(minLength: 0)
                    Text(day.seconds.map { SleepDetailFormat.duration($0) } ?? AppLocalization.text("未记录"))
                        .monospacedDigit()
                }
                .font(.system(size: 12))
                .foregroundStyle(Self.secondaryInk)
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
            }
            .padding(.top, 6)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("记录说明")
            Text(AppLocalization.text("来源：Apple 健康（HealthKit）"))
                .font(.system(size: 11))
                .foregroundStyle(Self.quietInk)
                .padding(.top, 4)
            Text(AppLocalization.text("— 表示未记录；缺失的区间留空，不补画。Apple 健康不提供夜间醒来次数，“记录到 N 段清醒”只统计已记录的清醒区间。HRV 为 Apple 健康的 SDNN。"))
                .font(.system(size: 11))
                .foregroundStyle(Self.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func dayText(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

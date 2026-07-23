import Charts
import SwiftUI
import UIKit

enum FootprintsDetailDestination: Identifiable {
    case metric(FootprintsMetric)
    case vitals
    case stress
    case workout(WorkoutRecord)
    case food(FoodPhoto)
    case doodle(WalkDoodleRecord)

    var id: String {
        switch self {
        case .metric(let metric): "metric-\(metric.rawValue)"
        case .vitals: "vitals"
        case .stress: "stress"
        case .workout(let workout): "workout-\(workout.id.uuidString)"
        case .food(let food): "food-\(food.id.uuidString)"
        case .doodle(let doodle): "doodle-\(doodle.id.uuidString)"
        }
    }
}

struct FootprintsDetailSheetHost: View {
    let destination: FootprintsDetailDestination
    let day: FootprintsDaySnapshot
    let trendPoints: [FootprintsTrendPoint]
    let stress: DerivedStress?
    let rmssd: Double?
    let stressBaseline: StressBaseline?

    var body: some View {
        Group {
            switch destination {
            case .metric(let metric):
                FootprintsMetricDetailView(metric: metric, day: day, points: trendPoints)
            case .vitals:
                FootprintsVitalsDetailView(day: day, points: trendPoints)
            case .stress:
                FootprintsStressDetailView(
                    stress: stress,
                    rmssd: rmssd,
                    baseline: stressBaseline
                )
            case .workout(let workout):
                FootprintsWorkoutDetailView(workout: workout)
            case .food(let food):
                FootprintsFoodDetailView(food: food)
            case .doodle(let doodle):
                FootprintsDoodleDetailView(doodle: doodle)
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
        .presentationBackground(LP.Fill.bgSurface)
    }
}

private struct FootprintsSheetHeader: View {
    @Environment(\.dismiss) private var dismiss

    let eyebrow: String
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: LP.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(Circle().fill(tint.opacity(0.1)))
            VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                Text(AppLocalization.text(eyebrow))
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(LP.Content.tertiary)
                Text(AppLocalization.text(title))
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.primary)
            }
            Spacer(minLength: 0)
            Button {
                LPHaptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LP.Content.secondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(LP.Fill.bgContainer))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.text("关闭"))
        }
    }
}

struct FootprintsMetricDetailView: View {
    let metric: FootprintsMetric
    let day: FootprintsDaySnapshot
    let points: [FootprintsTrendPoint]

    private var validPoints: [FootprintsTrendPoint] {
        points.filter { metric.hasValue($0.value(for: metric)) }
    }

    private var baseline: Double? {
        footprintsMedian(validPoints.map { $0.value(for: metric) })
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LP.Spacing.xxl) {
                FootprintsSheetHeader(
                    eyebrow: "数据依据",
                    title: metric.title,
                    icon: metric.icon,
                    tint: metric.tint
                )
                valueHeader
                trendChart
                metricDetails
                sourceCard
                Color.clear.frame(height: LP.Spacing.l)
            }
            .padding(LP.Spacing.l)
        }
    }

    private var valueHeader: some View {
        let current = metric.value(in: day)
        return VStack(alignment: .leading, spacing: LP.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.xs) {
                Text(metric.hasValue(current) ? metric.formatted(current) : "—")
                    .lpText(LP.Typography.uiH2)
                    .foregroundStyle(LP.Content.primary)
                    .monospacedDigit()
                Text(metric.unit)
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.tertiary)
            }
            Text(comparisonText(current))
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.secondary)
        }
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            HStack {
                Text(AppLocalization.text("近 30 天"))
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.primary)
                Spacer(minLength: 0)
                Text("\(validPoints.count) 个有效日")
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
            }

            Chart {
                ForEach(validPoints) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value(metric.title, point.value(for: metric))
                    )
                    .foregroundStyle(metric.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("日期", point.date),
                        y: .value(metric.title, point.value(for: metric))
                    )
                    .foregroundStyle(metric.tint.opacity(0.62))
                    .symbolSize(18)
                }

                if let baseline {
                    RuleMark(y: .value("个人中位数", baseline))
                        .foregroundStyle(LP.Content.quarternary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(LP.Separator.secondary)
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .foregroundStyle(LP.Content.quarternary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(LP.Separator.secondary)
                    AxisValueLabel().foregroundStyle(LP.Content.quarternary)
                }
            }
            .frame(height: 190)
        }
        .padding(LP.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
    }

    @ViewBuilder
    private var metricDetails: some View {
        switch metric {
        case .sleep:
            VStack(alignment: .leading, spacing: LP.Spacing.m) {
                FootprintsSectionHeader("这一晚")
                HStack(spacing: LP.Spacing.s) {
                    detailTile("深睡", value: hours(day.sleepDeep), tint: LP.Colorful.purple700)
                    detailTile("浅睡", value: hours(day.sleepCore), tint: LP.Colorful.blue400)
                    detailTile("眼动", value: hours(day.sleepREM), tint: LP.Colorful.purple300)
                }
                if let start = day.sleepStart, let end = day.sleepEnd {
                    Text("\(Self.time.string(from: start)) – \(Self.time.string(from: end))")
                        .lpText(LP.Typography.b4Medium)
                        .foregroundStyle(LP.Content.secondary)
                }
            }
        case .steps:
            VStack(alignment: .leading, spacing: LP.Spacing.m) {
                FootprintsSectionHeader("这一天")
                HStack(spacing: LP.Spacing.s) {
                    detailTile("脚步", value: "\(day.steps)", tint: LP.Colorful.green500)
                    detailTile("运动", value: "\(day.exerciseMinutes) min", tint: LP.Colorful.teal500)
                    detailTile("站立", value: "\(Int((Double(day.standMinutes) / 60).rounded())) h", tint: LP.Colorful.cyan500)
                }
            }
        case .activeEnergy:
            VStack(alignment: .leading, spacing: LP.Spacing.m) {
                FootprintsSectionHeader("活动构成")
                HStack(spacing: LP.Spacing.s) {
                    detailTile("活动消耗", value: "\(Int(day.activeEnergy.rounded()))", tint: LP.Colorful.orange500)
                    detailTile("运动分钟", value: "\(day.exerciseMinutes)", tint: LP.Colorful.green500)
                    detailTile("运动记录", value: "\(day.workouts.count)", tint: LP.Colorful.blue500)
                }
            }
        case .hrv:
            VStack(alignment: .leading, spacing: LP.Spacing.m) {
                FootprintsSectionHeader("同日心脏信号")
                HStack(spacing: LP.Spacing.s) {
                    detailTile("HRV", value: day.hrv > 0 ? "\(Int(day.hrv.rounded()))" : "—", tint: LP.Colorful.red500)
                    detailTile("静息心率", value: day.restingHeartRate > 0 ? "\(Int(day.restingHeartRate.rounded()))" : "—", tint: LP.Colorful.orange500)
                    detailTile("平均心率", value: day.heartRateAverage > 0 ? "\(Int(day.heartRateAverage.rounded()))" : "—", tint: LP.Colorful.pink500)
                }
            }
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Label("数据怎么来的", systemImage: "info.circle")
                .lpText(LP.Typography.b4Medium)
                .foregroundStyle(LP.Content.secondary)
            Text(AppLocalization.text(sourceText))
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LP.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(metric.softTint.opacity(0.72))
        )
    }

    private func detailTile(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xs) {
            Text(AppLocalization.text(label))
                .lpText(LP.Typography.c2Regular)
                .foregroundStyle(LP.Content.tertiary)
            Text(value)
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Capsule().fill(tint).frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LP.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                .strokeBorder(LP.Border.tertiary, lineWidth: 1)
        )
    }

    private func comparisonText(_ current: Double) -> String {
        guard metric.hasValue(current) else { return AppLocalization.text("这一天没有可用数据") }
        guard let baseline, validPoints.count >= 5 else {
            return AppLocalization.text("数据仍在积累，暂不判断变化")
        }
        let delta = current - baseline
        if abs(delta) <= max(0.1, baseline * 0.04) {
            return AppLocalization.text("接近你近期的个人中位数")
        }
        return AppLocalization.format(
            "比个人中位数%@ %@ %@",
            delta > 0 ? "高" : "低",
            metric.formatted(abs(delta)),
            metric.unit
        )
    }

    private var sourceText: String {
        switch metric {
        case .sleep:
            "来自 HealthKit 睡眠分析；夜间阶段会合并相邻片段。缺失不等于没有睡眠。"
        case .steps:
            "来自 HealthKit 步数与每小时聚合。手机或手表未随身携带时，记录可能不完整。"
        case .activeEnergy:
            "来自 HealthKit 活动能量和运动时间。不同设备与运动类型的估算方式可能不同。"
        case .hrv:
            "这里展示 HealthKit 的 SDNN 日均值，只与个人记录比较，不用于诊断压力或疾病。"
        }
    }

    private func hours(_ seconds: TimeInterval) -> String {
        seconds > 0 ? String(format: "%.1f h", seconds / 3_600) : "—"
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "H:mm"
        return formatter
    }()
}

struct FootprintsVitalsDetailView: View {
    let day: FootprintsDaySnapshot
    let points: [FootprintsTrendPoint]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LP.Spacing.xxl) {
                FootprintsSheetHeader(
                    eyebrow: "身体信号",
                    title: "测量与范围",
                    icon: "heart.text.square.fill",
                    tint: LP.Colorful.red500
                )
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: LP.Spacing.s
                ) {
                    vitalTile("平均心率", value(day.heartRateAverage), "bpm", LP.Colorful.red500)
                    vitalTile("静息心率", value(day.restingHeartRate), "bpm", LP.Colorful.orange500)
                    vitalTile("HRV", value(day.hrv), "ms", LP.Colorful.yellow600)
                    vitalTile("血氧", oxygenValue, "%", LP.Colorful.purple500)
                }

                if day.heartRateMinimum > 0, day.heartRateMaximum > 0 {
                    VStack(alignment: .leading, spacing: LP.Spacing.s) {
                        Text(AppLocalization.text("当天心率范围"))
                            .lpText(LP.Typography.b3Medium)
                            .foregroundStyle(LP.Content.primary)
                        Text("\(Int(day.heartRateMinimum.rounded()))–\(Int(day.heartRateMaximum.rounded())) bpm")
                            .lpText(LP.Typography.uiH4)
                            .foregroundStyle(LP.Content.primary)
                            .monospacedDigit()
                    }
                    .padding(LP.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                            .fill(LP.Fill.bgContainer)
                    )
                }

                VStack(alignment: .leading, spacing: LP.Spacing.s) {
                    Label("如何理解", systemImage: "info.circle")
                        .lpText(LP.Typography.b4Medium)
                        .foregroundStyle(LP.Content.secondary)
                    Text(AppLocalization.text("足迹优先展示你自己的长期变化。单次读数会受到佩戴、运动、测量时机等因素影响；如有健康疑虑，请咨询专业人士。"))
                        .lpText(LP.Typography.b4Regular)
                        .foregroundStyle(LP.Content.tertiary)
                }
                .padding(LP.Spacing.l)
                .background(
                    RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                        .fill(LP.Colorful.red100.opacity(0.72))
                )
            }
            .padding(LP.Spacing.l)
        }
    }

    private var oxygenValue: String {
        day.oxygenSaturation > 0 ? "\(Int((day.oxygenSaturation * 100).rounded()))" : "—"
    }

    private func value(_ number: Double) -> String {
        number > 0 ? "\(Int(number.rounded()))" : "—"
    }

    private func vitalTile(_ title: String, _ value: String, _ unit: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.xs) {
                Text(value)
                    .lpText(LP.Typography.uiH5)
                    .foregroundStyle(LP.Content.primary)
                Text(unit)
                    .lpText(LP.Typography.c2Regular)
                    .foregroundStyle(LP.Content.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LP.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
    }
}

struct FootprintsStressDetailView: View {
    let stress: DerivedStress?
    let rmssd: Double?
    let baseline: StressBaseline?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LP.Spacing.xxl) {
                FootprintsSheetHeader(
                    eyebrow: "今天",
                    title: "压力线索",
                    icon: "figure.mind.and.body",
                    tint: LP.Colorful.yellow600
                )
                if let stress {
                    HistoryStressCard(stress: stress, rmssd: rmssd, baseline: baseline)
                } else {
                    Text(AppLocalization.text("今天还没有足够的心率与 HRV 数据。"))
                        .lpText(LP.Typography.b3Regular)
                        .foregroundStyle(LP.Content.tertiary)
                        .padding(LP.Spacing.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                                .fill(LP.Fill.bgContainer)
                        )
                }
                Text(AppLocalization.text("压力指数是稀疏 HRV 测量与近期心率的估算结果。它用来观察个人变化，不是医学诊断，也不应用来评价一天的好坏。"))
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(LP.Content.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(LP.Spacing.l)
        }
    }
}

struct FootprintsWorkoutDetailView: View {
    let workout: WorkoutRecord

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LP.Spacing.xxl) {
                FootprintsSheetHeader(
                    eyebrow: Self.date.string(from: workout.start),
                    title: workoutName,
                    icon: workoutIcon,
                    tint: workoutTint
                )

                HStack(spacing: LP.Spacing.s) {
                    metricTile("时长", "\(workout.durationMinutes)", "min")
                    metricTile("消耗", "\(Int(workout.energyKcal.rounded()))", "kcal")
                    metricTile("距离", distanceText, "")
                }

                VStack(alignment: .leading, spacing: LP.Spacing.m) {
                    Text(AppLocalization.text("这段运动"))
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.primary)
                    detailRow("时间", workout.timeRangeText)
                    detailRow("平均配速", workout.paceMinPerKm.map(paceText) ?? "不适用")
                    detailRow("记录来源", "HealthKit 运动记录")
                }
                .padding(LP.Spacing.l)
                .background(
                    RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                        .fill(LP.Fill.bgContainer)
                )

                Text(AppLocalization.text("“这段路……花记住了。”"))
                    .lpText(LP.Typography.handSmall)
                    .foregroundStyle(LP.Content.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(LP.Spacing.l)
                    .background(
                        RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                            .fill(workoutTint.opacity(0.08))
                    )
            }
            .padding(LP.Spacing.l)
        }
    }

    private var workoutName: String {
        switch workout.kind {
        case .run: "户外跑步"
        case .walk: "户外散步"
        case .cycle: "骑行"
        case .swim: "游泳"
        case .hiit: "高强度间歇"
        case .yoga: "瑜伽"
        case .other: "运动"
        }
    }

    private var workoutIcon: String {
        switch workout.kind {
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .cycle: "figure.outdoor.cycle"
        case .swim: "figure.pool.swim"
        case .hiit: "figure.highintensity.intervaltraining"
        case .yoga: "figure.yoga"
        case .other: "figure.mixed.cardio"
        }
    }

    private var workoutTint: Color {
        switch workout.kind {
        case .run: LP.Colorful.green500
        case .walk: LP.Colorful.teal500
        case .cycle: LP.Colorful.blue500
        case .swim: LP.Colorful.cyan500
        case .hiit: LP.Colorful.orange500
        case .yoga: LP.Colorful.purple500
        case .other: LP.Colorful.cyan500
        }
    }

    private var distanceText: String {
        guard workout.distanceMeters > 0 else { return "—" }
        return String(format: "%.2f km", workout.distanceMeters / 1_000)
    }

    private func metricTile(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xs) {
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)
            Text(value)
                .lpText(LP.Typography.uiH5)
                .foregroundStyle(LP.Content.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if !unit.isEmpty {
                Text(unit)
                    .lpText(LP.Typography.c2Regular)
                    .foregroundStyle(LP.Content.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LP.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                .fill(workoutTint.opacity(0.08))
        )
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.tertiary)
            Spacer(minLength: LP.Spacing.s)
            Text(AppLocalization.text(value))
                .lpText(LP.Typography.b4Medium)
                .foregroundStyle(LP.Content.secondary)
        }
    }

    private func paceText(_ pace: Double) -> String {
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d'%02d\" /km", minutes, seconds)
    }

    private static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()
}

struct FootprintsFoodDetailView: View {
    let food: FoodPhoto

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LP.Spacing.xxl) {
                FootprintsSheetHeader(
                    eyebrow: food.meal?.title ?? "露珠相机",
                    title: food.dishName ?? food.subjectLabel ?? "一张记录",
                    icon: food.meal?.symbol ?? "camera.fill",
                    tint: LP.Colorful.green500
                )
                image
                if let analysis = food.analysis {
                    analysisView(analysis)
                } else {
                    Text(AppLocalization.text("这张照片保留了识别标签，但没有完整的营养分析。"))
                        .lpText(LP.Typography.b4Regular)
                        .foregroundStyle(LP.Content.tertiary)
                        .padding(LP.Spacing.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                                .fill(LP.Fill.bgContainer)
                        )
                }
            }
            .padding(LP.Spacing.l)
        }
    }

    private var image: some View {
        Group {
            if let uiImage = UIImage(data: food.pngData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .padding(LP.Spacing.l)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 42))
                    .foregroundStyle(LP.Content.quarternary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
        .overlay(alignment: .bottomTrailing) {
            Text(food.timeLabel)
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(LP.Content.secondary)
                .padding(.horizontal, LP.Spacing.s)
                .padding(.vertical, 5)
                .background(Capsule().fill(LP.Fill.bgPop.opacity(0.92)))
                .padding(LP.Spacing.s)
        }
    }

    private func analysisView(_ analysis: FoodAnalysis) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.l) {
            HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.xs) {
                Text("\(analysis.totalCalories)")
                    .lpText(LP.Typography.uiH2)
                    .foregroundStyle(LP.Fill.foundationAccent)
                Text("kcal · 估算")
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Content.tertiary)
            }

            HStack(spacing: LP.Spacing.s) {
                macro("蛋白质", analysis.proteinG)
                macro("碳水", analysis.carbG)
                macro("脂肪", analysis.fatG)
            }

            if !analysis.items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(analysis.items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .lpText(LP.Typography.b4Medium)
                                    .foregroundStyle(LP.Content.secondary)
                                if let quantity = item.quantity {
                                    Text(quantity)
                                        .lpText(LP.Typography.c2Regular)
                                        .foregroundStyle(LP.Content.tertiary)
                                }
                            }
                            Spacer(minLength: LP.Spacing.s)
                            Text("\(item.calories) kcal")
                                .lpText(LP.Typography.b4Medium)
                                .foregroundStyle(LP.Content.secondary)
                        }
                        .padding(.vertical, LP.Spacing.m)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(LP.Separator.secondary).frame(height: 1)
                        }
                    }
                }
            }

            if let note = analysis.note, !note.isEmpty {
                Text(note)
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .padding(LP.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                            .fill(LP.Colorful.green100.opacity(0.72))
                    )
            }
        }
    }

    private func macro(_ title: String, _ grams: Double?) -> some View {
        VStack(spacing: LP.Spacing.xs) {
            Text(grams.map { "\(Int($0.rounded()))g" } ?? "—")
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.primary)
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.c2Regular)
                .foregroundStyle(LP.Content.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LP.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
    }
}

struct FootprintsDoodleDetailView: View {
    let doodle: WalkDoodleRecord
    @State private var drawProgress: CGFloat = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LP.Spacing.xxl) {
                FootprintsSheetHeader(
                    eyebrow: Self.date.string(from: doodle.createdAt),
                    title: doodle.title ?? "用脚画下的路",
                    icon: "scribble.variable",
                    tint: LP.Colorful.green500
                )

                WalkDoodleShape(coordinates: doodle.coordinates)
                    .trim(from: 0, to: drawProgress)
                    .stroke(
                        LP.Fill.foundationAccent,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                    )
                    .padding(LP.Spacing.xxl)
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .background(
                        RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                            .fill(LP.Neutral.grey200.opacity(0.72))
                    )

                HStack(spacing: LP.Spacing.s) {
                    metric("距离", DoodleGeometry.distanceText(doodle.distanceMeters))
                    metric("圈地", DoodleGeometry.areaText(doodle.areaSquareMeters))
                    metric("时长", durationText)
                }

                Button {
                    LPHaptics.tap()
                    drawProgress = 0
                    withAnimation(.easeInOut(duration: 1.8)) { drawProgress = 1 }
                } label: {
                    Label("再走一遍", systemImage: "play.fill")
                        .lpText(LP.Typography.b4Medium)
                        .foregroundStyle(LP.Fill.foundationOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LP.Spacing.m)
                        .background(
                            RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                                .fill(LP.Fill.foundationAccent)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(LP.Spacing.l)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8)) { drawProgress = 1 }
        }
    }

    private var durationText: String {
        let minutes = max(1, Int((doodle.durationSeconds / 60).rounded()))
        return "\(minutes) min"
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xs) {
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.c2Regular)
                .foregroundStyle(LP.Content.tertiary)
            Text(value)
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LP.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
    }

    private static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 H:mm"
        return formatter
    }()
}

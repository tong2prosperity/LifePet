import SwiftUI
import UIKit

struct FootprintsBodySignalsCard: View {
    let day: FootprintsDaySnapshot
    let onOpen: () -> Void

    var body: some View {
        Button {
            LPHaptics.tap()
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: LP.Spacing.l) {
                HStack {
                    VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                        Text(AppLocalization.text("身体信号"))
                            .lpText(LP.Typography.uiH5)
                            .foregroundStyle(LP.Content.primary)
                        Text(AppLocalization.text("只描述记录，不替代医学判断"))
                            .lpText(LP.Typography.c1Regular)
                            .foregroundStyle(LP.Content.tertiary)
                    }
                    Spacer(minLength: LP.Spacing.s)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LP.Content.quarternary)
                }

                HStack(spacing: LP.Spacing.s) {
                    signal(
                        icon: "heart.fill",
                        title: "心率",
                        value: value(day.heartRateAverage),
                        unit: "bpm",
                        color: LP.Colorful.red500
                    )
                    signal(
                        icon: "heart.circle.fill",
                        title: "静息",
                        value: value(day.restingHeartRate),
                        unit: "bpm",
                        color: LP.Colorful.orange500
                    )
                    signal(
                        icon: "lungs.fill",
                        title: "血氧",
                        value: day.oxygenSaturation > 0
                            ? "\(Int((day.oxygenSaturation * 100).rounded()))"
                            : "—",
                        unit: "%",
                        color: LP.Colorful.purple500
                    )
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
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(AppLocalization.text("轻点查看测量范围与数据说明"))
    }

    private func signal(
        icon: String,
        title: String,
        value: String,
        unit: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.c2Medium)
                .foregroundStyle(LP.Content.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(LP.Content.primary)
                    .monospacedDigit()
                Text(unit)
                    .lpText(LP.Typography.c2Regular)
                    .foregroundStyle(LP.Content.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LP.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }

    private func value(_ number: Double) -> String {
        number > 0 ? "\(Int(number.rounded()))" : "—"
    }
}

struct FootprintsStressCompactCard: View {
    let stress: DerivedStress
    let baseline: StressBaseline?
    let onOpen: () -> Void

    var body: some View {
        Button {
            LPHaptics.tap()
            onOpen()
        } label: {
            HStack(spacing: LP.Spacing.l) {
                ZStack {
                    Circle()
                        .stroke(LP.Neutral.grey250, lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: max(0.03, min(1, Double(stress.index) / 100)))
                        .stroke(
                            stress.level.tint,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(stress.index)")
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Content.primary)
                        .monospacedDigit()
                }
                .frame(width: 66, height: 66)

                VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                    HStack(spacing: LP.Spacing.s) {
                        Text(AppLocalization.text("压力线索"))
                            .lpText(LP.Typography.b2Medium)
                            .foregroundStyle(LP.Content.primary)
                        Text(AppLocalization.text(stress.level.displayName))
                            .lpText(LP.Typography.c1Medium)
                            .foregroundStyle(stress.level.tint)
                            .padding(.horizontal, LP.Spacing.s)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(stress.level.bg))
                    }
                    Text(AppLocalization.text(stress.level.caption))
                        .lpText(LP.Typography.b4Regular)
                        .foregroundStyle(LP.Content.secondary)
                        .lineLimit(2)
                    Text(baselineText)
                        .lpText(LP.Typography.c2Regular)
                        .foregroundStyle(LP.Content.tertiary)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LP.Content.quarternary)
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
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(AppLocalization.text("轻点查看压力指数的数据依据"))
    }

    private var baselineText: String {
        let days = baseline?.dayCount ?? 0
        if days >= StressScore.fullPersonalDays {
            return AppLocalization.format("个人基线 · 已学习 %d 天", days)
        }
        return AppLocalization.format("正在了解你 · %d/%d 天", days, StressScore.fullPersonalDays)
    }
}

struct FootprintsMomentsSection: View {
    let day: FootprintsDaySnapshot
    let onWorkout: (WorkoutRecord) -> Void
    let onFood: (FoodPhoto) -> Void
    let onDoodle: (WalkDoodleRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            FootprintsSectionHeader(
                "这一天留下的东西",
                caption: "运动、照片与用脚画下的路，都可以继续查看"
            )

            if day.workouts.isEmpty && day.foods.isEmpty && day.doodles.isEmpty {
                emptyState
            } else {
                if !day.workouts.isEmpty { workouts }
                if !day.foods.isEmpty { foods }
                if !day.doodles.isEmpty { doodles }
            }
        }
    }

    private var workouts: some View {
        VStack(spacing: LP.Spacing.s) {
            ForEach(day.workouts) { workout in
                Button {
                    LPHaptics.tap()
                    onWorkout(workout)
                } label: {
                    HStack(spacing: LP.Spacing.m) {
                        Image(systemName: workoutIcon(workout.kind))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(workoutTint(workout.kind))
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(workoutTint(workout.kind).opacity(0.1)))

                        VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                            Text(AppLocalization.text(workoutName(workout.kind)))
                                .lpText(LP.Typography.b3Medium)
                                .foregroundStyle(LP.Content.primary)
                            Text("\(workout.timeRangeText) · \(workout.durationMinutes) min")
                                .lpText(LP.Typography.c1Regular)
                                .foregroundStyle(LP.Content.tertiary)
                        }

                        Spacer(minLength: LP.Spacing.s)
                        VStack(alignment: .trailing, spacing: LP.Spacing.xs) {
                            Text("\(Int(workout.energyKcal.rounded()))")
                                .lpText(LP.Typography.b3Medium)
                                .foregroundStyle(LP.Content.primary)
                            Text("kcal")
                                .lpText(LP.Typography.c2Regular)
                                .foregroundStyle(LP.Content.tertiary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LP.Content.quarternary)
                    }
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

    private var foods: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: LP.Spacing.m) {
                ForEach(day.foods) { food in
                    Button {
                        LPHaptics.tap()
                        onFood(food)
                    } label: {
                        VStack(alignment: .leading, spacing: LP.Spacing.s) {
                            ZStack(alignment: .topTrailing) {
                                foodImage(food)
                                    .frame(width: 132, height: 116)
                                    .background(
                                        RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                                            .fill(LP.Fill.bgContainer)
                                    )
                                if let calories = food.totalCalories {
                                    Text("\(calories) kcal")
                                        .lpText(LP.Typography.c2Medium)
                                        .foregroundStyle(LP.Content.primary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(LP.Fill.bgPop.opacity(0.92)))
                                        .padding(6)
                                }
                            }
                            Text(food.dishName ?? food.subjectLabel ?? "一张记录")
                                .lpText(LP.Typography.b4Medium)
                                .foregroundStyle(LP.Content.secondary)
                                .lineLimit(1)
                            Text(food.timeLabel)
                                .lpText(LP.Typography.c2Regular)
                                .foregroundStyle(LP.Content.tertiary)
                        }
                        .frame(width: 132, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var doodles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: LP.Spacing.m) {
                ForEach(day.doodles) { doodle in
                    Button {
                        LPHaptics.tap()
                        onDoodle(doodle)
                    } label: {
                        VStack(alignment: .leading, spacing: LP.Spacing.s) {
                            WalkDoodleShape(coordinates: doodle.coordinates)
                                .stroke(
                                    LP.Fill.foundationAccent,
                                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                                )
                                .padding(LP.Spacing.m)
                                .frame(width: 164, height: 124)
                                .background(
                                    RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                                        .fill(LP.Neutral.grey200.opacity(0.72))
                                )
                            Text(doodle.title ?? "用脚画下的路")
                                .lpText(LP.Typography.b4Medium)
                                .foregroundStyle(LP.Content.secondary)
                            Text("\(DoodleGeometry.distanceText(doodle.distanceMeters)) · \(DoodleGeometry.areaText(doodle.areaSquareMeters))")
                                .lpText(LP.Typography.c2Regular)
                                .foregroundStyle(LP.Content.tertiary)
                        }
                        .frame(width: 164, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: LP.Spacing.m) {
            Image(systemName: "tray")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LP.Content.tertiary)
                .frame(width: 42, height: 42)
                .background(Circle().fill(LP.Neutral.grey200))
            VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                Text(AppLocalization.text("这一天没有额外记录"))
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Content.secondary)
                Text(AppLocalization.text("没有运动、照片或涂鸦，也是一种完整的日子"))
                    .lpText(LP.Typography.c1Regular)
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

    @ViewBuilder
    private func foodImage(_ food: FoodPhoto) -> some View {
        if let image = UIImage(data: food.pngData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(LP.Spacing.s)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 28))
                .foregroundStyle(LP.Content.quarternary)
        }
    }

    private func workoutName(_ kind: HealthEvent.WorkoutKind) -> String {
        switch kind {
        case .run: "户外跑步"
        case .walk: "户外散步"
        case .cycle: "骑行"
        case .swim: "游泳"
        case .hiit: "高强度间歇"
        case .yoga: "瑜伽"
        case .other: "运动"
        }
    }

    private func workoutIcon(_ kind: HealthEvent.WorkoutKind) -> String {
        switch kind {
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .cycle: "figure.outdoor.cycle"
        case .swim: "figure.pool.swim"
        case .hiit: "figure.highintensity.intervaltraining"
        case .yoga: "figure.yoga"
        case .other: "figure.mixed.cardio"
        }
    }

    private func workoutTint(_ kind: HealthEvent.WorkoutKind) -> Color {
        switch kind {
        case .run: LP.Colorful.green500
        case .walk: LP.Colorful.teal500
        case .cycle: LP.Colorful.blue500
        case .swim: LP.Colorful.cyan500
        case .hiit: LP.Colorful.orange500
        case .yoga: LP.Colorful.purple500
        case .other: LP.Colorful.cyan500
        }
    }
}

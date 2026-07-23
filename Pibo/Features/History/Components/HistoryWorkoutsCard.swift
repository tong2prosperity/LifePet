import SwiftUI

/// 运动记录 card — one tinted pill per workout with 时长 / 消耗 / 平均配速
/// (Figma `activities content card` 1374:890). Reads real per-day `WorkoutRecord`s
/// (backfilled from HK); pace is hidden when the workout has no usable distance.
struct HistoryWorkoutsCard: View {
    let workouts: [WorkoutRecord]

    var body: some View {
        HistoryCard(title: "运动记录", background: { LP.Fill.bgContainer }) {
            VStack(spacing: LP.Spacing.s) {
                if workouts.isEmpty {
                    emptyRow
                } else {
                    ForEach(workouts) { WorkoutRow(workout: $0) }
                }
            }
            .padding(.horizontal, LP.Spacing.s)
            .padding(.bottom, LP.Spacing.s)
        }
    }

    private var emptyRow: some View {
        Text(AppLocalization.text("今天还没有运动记录"))
            .lpText(LP.Typography.b4Regular)
            .foregroundStyle(LP.Content.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LP.Spacing.xl)
            .padding(.vertical, LP.Spacing.l)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(LP.Colorful.green100))
    }
}

private struct WorkoutRow: View {
    let workout: WorkoutRecord

    var body: some View {
        let s = WorkoutStyle.of(workout.kind)
        VStack(spacing: LP.Spacing.s) {
            HStack {
                HStack(spacing: LP.Spacing.xs) {
                    Image(systemName: s.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(s.tint)
                    Text(AppLocalization.text(s.name))
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.primary)
                }
                Spacer(minLength: 0)
                Text(workout.timeRangeText)
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.tertiary)
            }
            HStack(alignment: .top, spacing: LP.Spacing.s) {
                metric("时长", "\(workout.durationMinutes)", "min")
                metric("消耗", "\(Int(workout.energyKcal))", "cal")
                if let pace = workout.paceMinPerKm {
                    metric("平均配速", Self.paceText(pace), "")
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, LP.Spacing.xl)
        .padding(.vertical, LP.Spacing.l)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(s.bg))
    }

    private func metric(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.xs) {
            Text(AppLocalization.text(label))
                .lpText(LP.Typography.c2Medium)
                .foregroundStyle(LP.Content.quarternary)
            HStack(alignment: .bottom, spacing: LP.Spacing.xs) {
                Text(value).lpText(LP.Typography.b1Medium).foregroundStyle(LP.Content.primary)
                if !unit.isEmpty {
                    Text(unit).lpText(LP.Typography.b3Medium).foregroundStyle(LP.Content.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func paceText(_ p: Double) -> String {
        let m = Int(p)
        let s = Int((p - Double(m)) * 60)
        return String(format: "%d'%02d\"", m, s)
    }
}

/// Per-kind icon / name / colors for a workout pill.
private struct WorkoutStyle {
    let name: String
    let icon: String
    let tint: Color
    let bg: Color

    static func of(_ kind: HealthEvent.WorkoutKind) -> WorkoutStyle {
        switch kind {
        case .run:   return .init(name: "户外跑步", icon: "figure.run",  tint: LP.Colorful.green500, bg: LP.Colorful.green100)
        case .walk:  return .init(name: "户外散步", icon: "figure.walk", tint: LP.Colorful.teal500,  bg: LP.Colorful.teal100)
        case .cycle: return .init(name: "骑行",     icon: "figure.outdoor.cycle", tint: LP.Colorful.blue500, bg: LP.Colorful.blue100)
        case .swim:  return .init(name: "游泳",     icon: "figure.pool.swim", tint: LP.Colorful.cyan500, bg: LP.Colorful.cyan100)
        case .hiit:  return .init(name: "高强度间歇", icon: "figure.highintensity.intervaltraining", tint: LP.Colorful.orange500, bg: LP.Colorful.orange100)
        case .yoga:  return .init(name: "瑜伽",     icon: "figure.yoga", tint: LP.Colorful.purple500, bg: LP.Colorful.purple100)
        case .other: return .init(name: "运动",     icon: "figure.mixed.cardio", tint: LP.Colorful.cyan500, bg: LP.Colorful.cyan100)
        }
    }
}

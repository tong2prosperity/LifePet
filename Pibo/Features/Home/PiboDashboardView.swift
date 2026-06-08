import SwiftUI

/// 上滑 Dashboard (历史数据二楼) — the daily health data behind a swipe-up.
/// Shows **raw** HealthKit readings (no derived stats), the direct-data view the
/// home spec calls for (风吹草地 / 睡眠云朵 / 露珠活动 / 运动 / 体征).
struct PiboDashboardView: View {
    @Environment(PetStateStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: LP.Spacing.m),
                           GridItem(.flexible(), spacing: LP.Spacing.m)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LP.Spacing.l) {
                header
                LazyVGrid(columns: columns, spacing: LP.Spacing.m) {
                    metricCard("步数", value: "\(store.rawSteps)", unit: "步",
                               icon: "figure.walk", tint: LP.Fill.foundationAccent)
                    metricCard("睡眠", value: sleepValue, unit: "",
                               icon: "moon.zzz.fill", tint: Color(hex: 0x6C8BD0))
                    metricCard("运动", value: "\(store.rawExerciseMinutes)", unit: "分钟",
                               icon: "flame.fill", tint: Color(hex: 0xE08A4B))
                    metricCard("活动能量", value: "\(Int(store.rawActiveEnergy))", unit: "千卡",
                               icon: "bolt.fill", tint: Color(hex: 0xD1A23B))
                    metricCard("心率", value: heartRateValue, unit: "bpm",
                               icon: "heart.fill", tint: Color(hex: 0xD15B5B))
                    metricCard("HRV", value: hrvValue, unit: "ms",
                               icon: "waveform.path.ecg", tint: Color(hex: 0x4FA3A0))
                    metricCard("站立", value: "\(store.rawStandMinutes)", unit: "分钟",
                               icon: "figure.stand", tint: Color(hex: 0x7FA86B))
                    metricCard("正念", value: "\(store.rawMindfulMinutes)", unit: "分钟",
                               icon: "leaf.fill", tint: LP.Fill.foundationAccent)
                }
            }
            .padding(LP.Spacing.l)
        }
        .background(LP.Fill.bgSurface.ignoresSafeArea())
        .overlay(alignment: .top) { grabber }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AppLocalization.text("今日数据"))
                .lpText(LP.Typography.uiH2)
                .foregroundStyle(LP.Content.primary)
            Text(store.relationshipDayLabel)
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(LP.Content.tertiary)
        }
        .padding(.top, LP.Spacing.l)
    }

    private var grabber: some View {
        Capsule().fill(LP.Content.quarternary)
            .frame(width: 40, height: 5)
            .padding(.top, LP.Spacing.s)
    }

    private func metricCard(_ title: String, value: String, unit: String,
                            icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            HStack(spacing: LP.Spacing.s) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                Text(AppLocalization.text(title))
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(LP.Content.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .lpText(LP.Typography.uiH3)
                    .foregroundStyle(LP.Content.primary)
                if !unit.isEmpty {
                    Text(AppLocalization.text(unit))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LP.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .strokeBorder(LP.Separator.primary, lineWidth: 1)
        )
        .lpShadow(LP.Shadow.elevation1)
    }

    private var sleepValue: String {
        let h = store.rawSleepHours
        guard h > 0 else { return "—" }
        let hours = Int(h)
        let mins = Int((h - Double(hours)) * 60)
        return mins == 0 ? "\(hours)h" : "\(hours)h\(mins)m"
    }

    private var heartRateValue: String {
        store.rawHeartRate > 0 ? "\(Int(store.rawHeartRate))" : "—"
    }

    private var hrvValue: String {
        store.rawHRV > 0 ? "\(Int(store.rawHRV))" : "—"
    }
}

#Preview {
    PiboDashboardView().environment(PetStateStore(demoMode: true))
}

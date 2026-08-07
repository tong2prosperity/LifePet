import SwiftUI

/// 压力 card — StressWatch-style. The four-tier read + 「压力指数」refresh with
/// every per-minute heart-rate update (`DerivedStress`: sparse RMSSD anchor +
/// live HR-over-resting modulation), so the card feels live even though真正的
/// HRV 测量仍是每 2–5 小时一次. Today only; the host hides it when there's no
/// reading. `rmssd` is the raw anchor value (nil = HR-only estimate, no HRV yet).
struct HistoryStressCard: View {
    let stress: DerivedStress
    let rmssd: Double?
    /// The personal baseline behind the score — surfaced so the user can see the
    /// individualized computation (基线均值 / 已学天数 / 冷启动状态).
    var baseline: StressBaseline? = nil

    var body: some View {
        HistoryCard(title: "压力", background: { LP.Fill.bgContainer }) {
            VStack(alignment: .leading, spacing: LP.Spacing.m) {
                HStack(alignment: .center, spacing: LP.Spacing.m) {
                    Text(AppLocalization.text(stress.level.displayName))
                        .lpText(LP.Typography.uiH4)
                        .foregroundStyle(stress.level.tint)
                        .padding(.horizontal, LP.Spacing.l)
                        .padding(.vertical, LP.Spacing.s)
                        .background(Capsule().fill(stress.level.bg))
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.xs) {
                        Text("\(stress.index)")
                            .lpText(LP.Typography.uiH2)
                            .foregroundStyle(LP.Content.primary)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.3), value: stress.index)
                        Text("压力指数")
                            .lpText(LP.Typography.c2Medium)
                            .foregroundStyle(LP.Content.tertiary)
                    }
                }

                Text(AppLocalization.text(stress.level.caption))
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(freshnessLine)
                    .lpText(LP.Typography.c2Regular)
                    .foregroundStyle(LP.Content.quarternary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(baselineLine)
                    .lpText(LP.Typography.c2Regular)
                    .foregroundStyle(LP.Content.quarternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, LP.Spacing.xl)
            .padding(.bottom, LP.Spacing.l)
        }
    }

    /// Explains where the number comes from — honest about the sparse HRV.
    private var freshnessLine: String {
        if stress.isEstimated {
            return AppLocalization.text("尚无 HRV 测量，暂按心率估算；心率每分钟随动。")
        }
        let rmssdPart = rmssd.map { String(format: "HRV %.0f ms · ", $0) } ?? ""
        if let age = stress.hrvAgeMinutes {
            let ageText = age < 1
                ? AppLocalization.text("刚刚")
                : AppLocalization.format("%d 分钟前", age)
            return rmssdPart + AppLocalization.format("测于 %@ · 随心率实时校准", ageText)
        }
        return rmssdPart + AppLocalization.text("随心率实时校准")
    }

    /// Whether the score is judged against the wearer's own baseline yet, and how
    /// far the personalization has come — makes the "有没有在算" transparent.
    private var baselineLine: String {
        let days = baseline?.dayCount ?? 0
        let personalized = days >= StressScore.coldStartDays && (baseline?.sdLn ?? 0) > 0
        if personalized, let mean = baseline?.geoMean {
            return AppLocalization.format("个人基线 %.0f ms · 已学 %d 天", mean, days)
        }
        return AppLocalization.format("建立个人参考中 · %d/%d 天",
                                      min(days, StressScore.coldStartDays), StressScore.coldStartDays)
    }
}

#Preview {
    VStack(spacing: 16) {
        HistoryStressCard(
            stress: DerivedStress(score: 0.18, level: .excellent, hrvAgeMinutes: 12, isEstimated: false),
            rmssd: 52)
        HistoryStressCard(
            stress: DerivedStress(score: 0.58, level: .notice, hrvAgeMinutes: 140, isEstimated: false),
            rmssd: 24)
        HistoryStressCard(
            stress: DerivedStress(score: 0.44, level: .normal, hrvAgeMinutes: nil, isEstimated: true),
            rmssd: nil)
    }
    .padding()
    .background(Color(hex: 0xEAEEEF))
}

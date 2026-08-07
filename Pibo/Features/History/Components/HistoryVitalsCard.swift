import SwiftUI

/// 体征 card — a 2×2 grid of vital tiles: 实时心率 / 静息心率 / HRV(RMSSD) /
/// 血氧(SpO2), each a tinted tile with a qualitative word + value (Figma
/// `body status content` 1405:4320).
struct HistoryVitalsCard: View {
    let heartRate: Double      // bpm
    let restingHR: Double      // bpm
    /// **Our own** RMSSD (`HRVAnalysis`), not Apple's `heartRateVariabilitySDNN`.
    /// The tile used to show SDNN under a 「压力水平」 label while the 压力卡 right
    /// below showed the RMSSD-derived index — two different numbers both
    /// presented as "压力". SDNN reads systematically higher than RMSSD and the
    /// gap widens as HRV rises, so they can never be reconciled by eye.
    let rmssd: Double          // ms
    /// Tier for `rmssd`, judged against the personal baseline by the caller.
    /// Passed in rather than derived here so the scoring thresholds stay in
    /// `pibo-core` — this view owns presentation only.
    let stressLevel: StressLevel?
    let oxygen: Double         // fraction 0–1

    var body: some View {
        HistoryCard(title: "体征", background: { LP.Fill.bgContainer }) {
            VStack(spacing: LP.Spacing.s) {
                HStack(spacing: LP.Spacing.s) {
                    heartTile
                    restingTile
                }
                HStack(spacing: LP.Spacing.s) {
                    stressTile
                    oxygenTile
                }
            }
            .padding(.horizontal, LP.Spacing.s)
            .padding(.bottom, LP.Spacing.s)
        }
    }

    private var heartTile: VitalTile {
        VitalTile(icon: "heart.fill", title: "实时心率",
                  qualifier: heartRate <= 0 ? "暂无" : (heartRate > 100 ? "偏快" : (heartRate < 60 ? "偏慢" : "平稳")),
                  value: heartRate > 0 ? "\(Int(heartRate))" : "—", unit: "bpm",
                  tint: LP.Colorful.red500, bg: LP.Colorful.red100)
    }
    private var restingTile: VitalTile {
        VitalTile(icon: "heart.circle.fill", title: "静息心率",
                  qualifier: restingHR <= 0 ? "暂无" : (restingHR > 70 ? "偏高" : (restingHR < 50 ? "偏低" : "正常")),
                  value: restingHR > 0 ? "\(Int(restingHR))" : "—", unit: "bpm",
                  tint: LP.Colorful.orange500, bg: LP.Colorful.orange100)
    }
    private var stressTile: VitalTile {
        VitalTile(icon: "figure.mind.and.body", title: "HRV",
                  qualifier: rmssd > 0 ? (stressLevel?.displayName ?? "建立个人参考中") : "暂无",
                  value: rmssd > 0 ? String(format: "%.0f", rmssd) : "—", unit: "ms",
                  tint: LP.Colorful.yellow500, bg: LP.Colorful.yellow100)
    }
    private var oxygenTile: VitalTile {
        let pct = Int((oxygen * 100).rounded())
        return VitalTile(icon: "lungs.fill", title: "血氧",
                         qualifier: oxygen <= 0 ? "暂无" : (pct >= 95 ? "正常" : "偏低"),
                         value: oxygen > 0 ? "\(pct)" : "—", unit: "%",
                         tint: LP.Colorful.purple500, bg: LP.Colorful.purple100)
    }
}

private struct VitalTile: View {
    let icon: String
    let title: String
    let qualifier: String
    let value: String
    let unit: String
    let tint: Color
    let bg: Color

    var body: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            HStack(spacing: LP.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint)
                Text(AppLocalization.text(title))
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.primary)
            }
            VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                Text(AppLocalization.text(qualifier))
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.quarternary)
                HStack(alignment: .bottom, spacing: LP.Spacing.xs) {
                    Text(value).lpText(LP.Typography.b1Medium).foregroundStyle(LP.Content.primary)
                    Text(unit).lpText(LP.Typography.b3Medium).foregroundStyle(LP.Content.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LP.Spacing.xl)
        .padding(.vertical, LP.Spacing.l)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(bg))
    }
}

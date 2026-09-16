import SwiftUI

/// 体征 card — a 2×2 grid: 心率 / 静息心率 / HRV(RMSSD) / 血氧(SpO2).
///
/// History values are day aggregates, not live readings, so the tiles carry no
/// 「实时」 wording and no hard-coded 偏快/偏低 categories. The HRV qualifier is
/// supplied by the caller (today's Core baseline tier, or 当日中位数).
struct HistoryVitalsCard: View {
    let heartRate: Double?      // bpm, the day's average
    let restingHR: Double?      // bpm
    /// **Our own** RMSSD for the day (`HRVAnalysis`), not Apple's SDNN.
    let rmssd: Double?          // ms
    let rmssdQualifier: String
    let oxygen: Double?         // fraction 0–1

    var body: some View {
        HistoryCard(title: "体征", background: { LP.Fill.bgContainer }) {
            VStack(spacing: LP.Spacing.s) {
                HStack(spacing: LP.Spacing.s) {
                    VitalTile(icon: "heart.fill", title: "心率",
                              qualifier: Self.recordWord(heartRate),
                              value: heartRate.map { "\(Int($0.rounded()))" } ?? "—", unit: "bpm",
                              tint: LP.Colorful.red500, bg: LP.Colorful.red100)
                    VitalTile(icon: "heart.circle.fill", title: "静息心率",
                              qualifier: Self.recordWord(restingHR),
                              value: restingHR.map { "\(Int($0.rounded()))" } ?? "—", unit: "bpm",
                              tint: LP.Colorful.orange500, bg: LP.Colorful.orange100)
                }
                HStack(spacing: LP.Spacing.s) {
                    VitalTile(icon: "figure.mind.and.body", title: "HRV",
                              qualifier: rmssd == nil ? "暂无" : rmssdQualifier,
                              value: rmssd.map { String(format: "%.0f", $0) } ?? "—", unit: "ms",
                              tint: LP.Colorful.yellow500, bg: LP.Colorful.yellow100)
                    VitalTile(icon: "lungs.fill", title: "血氧",
                              qualifier: Self.recordWord(oxygen),
                              value: oxygen.map { "\(Int(($0 * 100).rounded()))" } ?? "—", unit: "%",
                              tint: LP.Colorful.purple500, bg: LP.Colorful.purple100)
                }
            }
            .padding(.horizontal, LP.Spacing.s)
            .padding(.bottom, LP.Spacing.s)
        }
    }

    private static func recordWord(_ value: Double?) -> String {
        value == nil ? "暂无" : "已同步记录"
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

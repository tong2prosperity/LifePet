import SwiftUI

/// 活动 card — 卡路里 / 运动 / 站立 over a water-ripple illustration on a cyan
/// gradient (Figma `activity card` 1194:1635).
struct HistoryActivityCard: View {
    let kcal: Int
    let exerciseMinutes: Int
    let standHours: Int
    /// Apple Activity ring goals (`HKActivitySummary`). 0 = unknown → fall back to
    /// a sensible default below.
    var moveGoal: Double = 0
    var exerciseGoal: Int = 0
    var standGoal: Int = 0

    var body: some View {
        HistoryCard(title: "活动", background: { background }) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: LP.Spacing.s) {
                    HistoryStatColumn(label: "卡路里", value: "\(kcal)", unit: "kcal")
                    HistoryStatColumn(label: "运动", value: "\(exerciseMinutes)", unit: "min")
                    HistoryStatColumn(label: "站立", value: "\(standHours)", unit: "h")
                }
                .padding(.horizontal, LP.Spacing.xl)
                .padding(.bottom, LP.Spacing.s)

                WaterSurface(intensities: dropIntensities)
                    .frame(height: 86)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, LP.Spacing.l)
                    .padding(.bottom, LP.Spacing.l)
            }
        }
    }

    /// 三列雨量 = 卡路里 / 运动 / 站立 各自对**真实环目标**的达成度 [0,1]（水池压在
    /// 对应数字下方）。目标来自 `HKActivitySummary`；某项未设目标(0)时回退到 Apple
    /// 三环常见默认值，保证模拟器/无目标设备也有合理表现。
    private var dropIntensities: [Double] {
        let moveTarget = moveGoal > 0 ? moveGoal : 500
        let exTarget = exerciseGoal > 0 ? Double(exerciseGoal) : 30
        let standTarget = standGoal > 0 ? Double(standGoal) : 12
        return [min(1, Double(kcal) / moveTarget),
                min(1, Double(exerciseMinutes) / exTarget),
                min(1, Double(standHours) / standTarget)]
    }

    private var background: some View {
        ZStack {
            LP.Colorful.cyan100
            LinearGradient(stops: [
                .init(color: LP.Colorful.cyan400.opacity(0), location: 0.4),
                .init(color: LP.Colorful.cyan400.opacity(0.5), location: 1.0),
            ], startPoint: .top, endPoint: .bottom)
        }
    }
}

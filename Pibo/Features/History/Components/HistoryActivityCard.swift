import PiboCore
import SwiftUI

/// 活动 card — 卡路里 / 运动 / 站立 over the falling-drop water surface on a cyan
/// gradient (Figma `activity card` 1194:1635).
///
/// Each column is independent: a missing metric reads "—" and only silences
/// its own drops, so a recorded calorie column keeps animating when exercise
/// is missing. Drop intensity and missing-goal defaults come from Core's
/// `PiboCoreActivityWater`. With nothing recorded the water is not drawn.
struct HistoryActivityCard: View {
    let kcal: Int?
    let exerciseMinutes: Int?
    let standHours: Int?
    /// Apple Activity ring goals (`HKActivitySummary`); 0 = unknown → Core default.
    var moveGoal: Double = 0
    var exerciseGoal: Int = 0
    var standGoal: Int = 0

    var body: some View {
        HistoryCard(title: "活动", background: { background }) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: LP.Spacing.s) {
                    HistoryStatColumn(label: "卡路里", value: kcal.map { "\($0)" } ?? "—", unit: "kcal")
                    HistoryStatColumn(label: "运动", value: exerciseMinutes.map { "\($0)" } ?? "—", unit: "min")
                    HistoryStatColumn(label: "站立", value: standHours.map { "\($0)" } ?? "—", unit: "h")
                }
                .padding(.horizontal, LP.Spacing.xl)
                .padding(.bottom, LP.Spacing.s)

                if kcal != nil || exerciseMinutes != nil || standHours != nil {
                    WaterSurface(intensities: Self.dropIntensities(
                        kcal: kcal, exerciseMinutes: exerciseMinutes, standHours: standHours,
                        moveGoal: moveGoal, exerciseGoal: exerciseGoal, standGoal: standGoal
                    ))
                    .frame(height: 86)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, LP.Spacing.l)
                    .padding(.bottom, LP.Spacing.l)
                } else {
                    Text(AppLocalization.text("暂无活动记录"))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, LP.Spacing.xl)
                        .padding(.bottom, LP.Spacing.l)
                }
            }
        }
    }

    /// [卡路里, 运动, 站立] ∈ [0,1]. A missing column passes 0 so only its own
    /// drops stop; goals of 0 are resolved by Core's defaults.
    static func dropIntensities(
        kcal: Int?, exerciseMinutes: Int?, standHours: Int?,
        moveGoal: Double, exerciseGoal: Int, standGoal: Int
    ) -> [Double] {
        let result = PiboCoreActivityWater.intensities(
            activeCalories: Double(kcal ?? 0),
            exerciseMinutes: Double(exerciseMinutes ?? 0),
            standHours: Double(standHours ?? 0),
            moveGoal: moveGoal,
            exerciseGoal: Double(exerciseGoal),
            standGoal: Double(standGoal)
        )
        return [result.move, result.exercise, result.stand]
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

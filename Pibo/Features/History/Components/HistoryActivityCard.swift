import SwiftUI

/// 活动 card — 卡路里 / 运动 / 站立 over a water-ripple illustration on a cyan
/// gradient (Figma `activity card` 1194:1635).
struct HistoryActivityCard: View {
    let kcal: Int
    let exerciseMinutes: Int
    let standHours: Int

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

                RippleField()
                    .frame(height: 86)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, LP.Spacing.l)
                    .padding(.bottom, LP.Spacing.l)
            }
        }
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

/// Procedural "rain into water" ripples — concentric ellipse rings with a falling
/// rain stroke, matching the 活动 card's bottom illustration.
private struct RippleField: View {
    var tint: Color = LP.Colorful.cyan500

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ForEach(0..<3, id: \.self) { i in
                ripple
                    .frame(width: w * 0.26, height: h * 0.46)
                    .position(x: w * (0.22 + 0.28 * Double(i)), y: h * 0.72)
            }
        }
    }

    private var ripple: some View {
        ZStack {
            Ellipse().stroke(tint, lineWidth: 2)
            Ellipse().stroke(tint.opacity(0.6), lineWidth: 1.5).scaleEffect(0.55)
            Capsule()
                .fill(tint)
                .frame(width: 2, height: 18)
                .rotationEffect(.degrees(22))
                .offset(y: -20)
        }
    }
}

import SwiftUI

/// 今日脚步 card — big step count + an encouraging line over a grass field on a
/// blue gradient (Figma `activity card` 1374:529). The grass blades' heights map
/// to the day's step volume (designer note: 草坪粗细高矮映射步行状态).
struct HistoryStepsCard: View {
    let steps: Int
    let caption: String

    var body: some View {
        HistoryCard(title: "今日脚步", background: { background }) {
            VStack(spacing: LP.Spacing.xs) {
                HStack(alignment: .bottom, spacing: LP.Spacing.s) {
                    Text("\(steps)")
                        .lpText(LP.Typography.uiH4)
                        .foregroundStyle(LP.Content.primary)
                    Text("步")
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.primary)
                        .padding(.bottom, 6)
                }
                Text(caption)
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, LP.Spacing.s)

            GrassField(steps: steps)
                .frame(height: 76)
                .frame(maxWidth: .infinity)
                .clipped()
        }
    }

    private var background: some View {
        ZStack {
            LP.Fill.bgContainer
            LinearGradient(stops: [
                .init(color: Color(hex: 0x88C6FF, alpha: 0), location: 0.4),
                .init(color: Color(hex: 0x88C6FF, alpha: 0.8), location: 1.0),
            ], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Procedural grass strip — a row of rounded blades in three greens with a few
/// fireflies. Blade heights follow a fixed organic pattern, scaled by how active
/// the day was so a busy day reads as a fuller lawn.
private struct GrassField: View {
    let steps: Int

    private static let pattern: [CGFloat] = [
        0.45, 0.76, 1.0, 0.45, 1.0, 0.45, 0.76, 0.76, 1.0, 1.0, 0.45,
        0.45, 0.76, 0.45, 0.76, 0.45, 1.0, 0.76, 0.76, 0.45, 1.0, 0.45,
    ]
    private static let greens = [LP.Colorful.green400, LP.Colorful.green500, LP.Colorful.green300]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // Fuller lawn for an active day; never below 0.55 so it always reads.
            let vigor = max(0.55, min(1.0, Double(steps) / 10_000))
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: max(2, w / CGFloat(Self.pattern.count) * 0.28)) {
                    ForEach(Self.pattern.indices, id: \.self) { i in
                        Capsule()
                            .fill(Self.greens[i % Self.greens.count])
                            .frame(maxWidth: .infinity)
                            .frame(height: h * Self.pattern[i] * vigor)
                    }
                }
                .frame(width: w, height: h, alignment: .bottom)

                fireflies(w: w, h: h)
            }
        }
    }

    private func fireflies(w: CGFloat, h: CGFloat) -> some View {
        let spots: [(CGFloat, CGFloat)] = [(0.18, 0.35), (0.46, 0.22), (0.62, 0.5), (0.83, 0.3)]
        return ForEach(spots.indices, id: \.self) { i in
            Circle()
                .fill(LP.Colorful.yellow400)
                .frame(width: 4, height: 4)
                .shadow(color: LP.Colorful.yellow300.opacity(0.8), radius: 3)
                .position(x: w * spots[i].0, y: h * spots[i].1)
        }
    }
}

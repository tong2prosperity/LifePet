import SwiftUI

struct MiniGameFootprintAsset: View {
    enum Side {
        case left
        case right
    }

    var side: Side
    var tint: Color = .white

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(tint.opacity(0.78))
                    .frame(width: 4 + CGFloat(index), height: 4 + CGFloat(index))
                    .offset(x: CGFloat(index - 1) * 4, y: CGFloat(index) * -3)
            }
            Capsule()
                .fill(tint.opacity(0.9))
                .frame(width: 13, height: 20)
                .offset(y: 8)
        }
        .rotationEffect(.degrees(side == .left ? -16 : 16))
        .accessibilityHidden(true)
    }
}

struct MiniGameFireflyAsset: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(LP.Colorful.yellow300.opacity(0.38))
                .blur(radius: 2)
            Circle()
                .fill(LP.Colorful.yellow300)
                .padding(3)
            Circle()
                .fill(.white.opacity(0.72))
                .frame(width: 3, height: 3)
                .offset(x: -2, y: -2)
        }
        .accessibilityHidden(true)
    }
}

struct MiniGameMistAsset: View {
    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.48 + Double(index) * 0.08))
                    .frame(width: CGFloat(30 - index * 3), height: 6)
                    .offset(x: CGFloat(index % 2 == 0 ? -3 : 4), y: CGFloat(index * 6 - 9))
            }
        }
        .accessibilityHidden(true)
    }
}

struct MiniGameRingAsset: View {
    var tint: Color = LP.Colorful.cyan400

    var body: some View {
        Circle()
            .stroke(tint.opacity(0.92), lineWidth: 4)
            .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1).padding(5))
            .shadow(color: tint.opacity(0.2), radius: 6, y: 2)
            .accessibilityHidden(true)
    }
}

struct MiniGameDoodleAsset: View {
    var tint: Color = LP.Fill.foundationAccent

    var body: some View {
        DoodleLineShape()
            .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .overlay(alignment: .bottomTrailing) {
                MiniGamePetalAsset(tint: tint)
                    .frame(width: 8, height: 13)
                    .offset(x: 2, y: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct DoodleLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY * 0.70))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.24, y: rect.minY + rect.height * 0.18),
            control2: CGPoint(x: rect.width * 0.36, y: rect.maxY * 0.95)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.28),
            control1: CGPoint(x: rect.width * 0.62, y: rect.minY + rect.height * 0.08),
            control2: CGPoint(x: rect.width * 0.78, y: rect.maxY * 0.82)
        )
        return path
    }
}

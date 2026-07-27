import SwiftUI

struct MiniGameMemoryGridAsset: View {
    var active: Set<Int>

    init(active: Set<Int>) {
        self.active = active
    }

    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(active.contains(index) ? .white.opacity(0.92) : .white.opacity(0.28))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct MiniGameMatchCardsAsset: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.45))
                .frame(width: 21, height: 25)
                .rotationEffect(.degrees(-8))
                .offset(x: -6, y: 2)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.92))
                .frame(width: 21, height: 25)
                .rotationEffect(.degrees(8))
                .offset(x: 6, y: -2)
                .overlay {
                    Circle()
                        .fill(MiniGameKind.speedMatch.tint.opacity(0.7))
                        .frame(width: 7, height: 7)
                        .offset(x: 6, y: -7)
                }
        }
        .accessibilityHidden(true)
    }
}

struct MiniGameRhythmAsset: View {
    var tint: Color = LP.Colorful.red400

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach([12, 24, 17, 28, 15], id: \.self) { height in
                Capsule()
                    .fill(tint.opacity(height > 20 ? 0.95 : 0.58))
                    .frame(width: 4, height: CGFloat(height))
            }
        }
        .accessibilityHidden(true)
    }
}

struct MiniGameGardenPatchAsset: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(.white.opacity(0.24))
                .frame(width: 34, height: 14)
                .offset(y: 11)
            ForEach(0..<3, id: \.self) { index in
                MiniGameFlowerAsset(level: index)
                    .frame(width: 16 + CGFloat(index) * 2, height: 16 + CGFloat(index) * 2)
                    .offset(x: CGFloat(index - 1) * 9, y: CGFloat(index % 2 == 0 ? -3 : 3))
            }
        }
        .accessibilityHidden(true)
    }
}

struct MiniGameHuarongBadgeAsset: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.2))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(.white.opacity(0.72), lineWidth: 1))
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white.opacity(0.95))
                .frame(width: 14, height: 14)
                .offset(x: 7, y: 4)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white.opacity(0.62))
                .frame(width: 7, height: 15)
                .offset(x: 3, y: 20)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white.opacity(0.62))
                .frame(width: 7, height: 15)
                .offset(x: 18, y: 18)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(MiniGameKind.huarongRoad.tint.opacity(0.7))
                .frame(width: 12, height: 5)
                .offset(x: 8, y: 25)
        }
        .accessibilityHidden(true)
    }
}

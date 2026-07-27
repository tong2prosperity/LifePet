import SwiftUI

struct MiniGamePiboAsset: View {
    var flowerScale: CGFloat = 1
    var showFlower = true

    var body: some View {
        ZStack(alignment: .top) {
            Image("pibo_body")
                .resizable()
                .scaledToFit()
                .shadow(color: LP.Content.primary.opacity(0.08), radius: 10, y: 5)
                .accessibilityHidden(true)

            if showFlower {
                MiniGameSproutAsset()
                    .frame(width: 46 * flowerScale, height: 58 * flowerScale)
                    .offset(y: -12 * flowerScale)
            }
        }
        .accessibilityHidden(true)
    }
}

struct MiniGameFlowerAsset: View {
    var level = 0

    private var petalCount: Int { min(10, 5 + level) }
    private var size: CGFloat { CGFloat(34 + level * 11) }

    var body: some View {
        ZStack {
            ForEach(0..<petalCount, id: \.self) { index in
                Capsule()
                    .fill(petalFill(index))
                    .frame(width: size * 0.38, height: size * 0.72)
                    .offset(y: -size * 0.32)
                    .rotationEffect(.degrees(Double(index) * 360 / Double(petalCount)))
            }

            Circle()
                .fill(LP.Colorful.yellow300)
                .frame(width: size * 0.56, height: size * 0.56)
                .overlay(Circle().strokeBorder(LP.Colorful.yellow700.opacity(0.24), lineWidth: 1))
        }
        .frame(width: size, height: size)
        .shadow(color: LP.Fill.foundationAccent.opacity(0.16), radius: 8, y: 3)
        .accessibilityHidden(true)
    }

    private func petalFill(_ index: Int) -> Color {
        [LP.Colorful.pink300, LP.Colorful.orange300, LP.Colorful.lime300, LP.Colorful.cyan300][(index + level) % 4]
    }
}

struct MiniGameSproutAsset: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(LP.Colorful.green600)
                .frame(width: 8, height: 34)
                .offset(y: 12)

            Capsule()
                .fill(LP.Colorful.lime400)
                .frame(width: 18, height: 34)
                .rotationEffect(.degrees(-38))
                .offset(x: -11, y: -2)

            Capsule()
                .fill(LP.Colorful.green500)
                .frame(width: 18, height: 34)
                .rotationEffect(.degrees(38))
                .offset(x: 11, y: -2)
        }
        .accessibilityHidden(true)
    }
}

struct MiniGameDewAsset: View {
    var tint: Color = LP.Colorful.cyan500

    var body: some View {
        DropShape()
            .fill(
                LinearGradient(
                    colors: [LP.Neutral.grey0.opacity(0.95), tint.opacity(0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(DropShape().strokeBorder(tint.opacity(0.4), lineWidth: 1.4))
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(0.72))
                    .frame(width: 7, height: 7)
                    .offset(x: 8, y: 10)
            }
            .shadow(color: tint.opacity(0.22), radius: 8, y: 4)
            .accessibilityHidden(true)
    }
}

private struct DropShape: InsettableShape {
    var insetAmount = 0.0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.18),
            control1: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.20),
            control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.34)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.12),
            control2: CGPoint(x: rect.maxX - rect.width * 0.24, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.18),
            control1: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.12)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.34),
            control2: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.20)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

struct MiniGamePetalAsset: View {
    var tint: Color = LP.Colorful.pink400

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [LP.Neutral.grey0.opacity(0.75), tint],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(Capsule().strokeBorder(tint.opacity(0.34), lineWidth: 1))
            .rotationEffect(.degrees(-24))
            .shadow(color: tint.opacity(0.18), radius: 5, y: 3)
            .accessibilityHidden(true)
    }
}

struct MiniGameBellAsset: View {
    var swing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(LP.Colorful.yellow300.opacity(0.28))
                .frame(width: 126, height: 126)

            VStack(spacing: -2) {
                Capsule()
                    .fill(LP.Colorful.orange400)
                    .frame(width: 42, height: 18)
                BellBodyShape()
                    .fill(
                        LinearGradient(
                            colors: [LP.Colorful.yellow300, LP.Colorful.orange500],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 94, height: 88)
                    .overlay(BellBodyShape().strokeBorder(LP.Colorful.orange700.opacity(0.34), lineWidth: 2))
                Circle()
                    .fill(LP.Colorful.orange700)
                    .frame(width: 20, height: 20)
            }
        }
        .rotationEffect(.degrees(swing ? 10 : -10))
        .shadow(color: LP.Colorful.orange500.opacity(0.24), radius: 16, y: 6)
        .accessibilityHidden(true)
    }
}

private struct BellBodyShape: InsettableShape {
    var insetAmount = 0.0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.maxY - rect.height * 0.10),
            control1: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.minY + rect.height * 0.08),
            control2: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.maxY - rect.height * 0.32)
        )
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY - rect.height * 0.10))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.maxY - rect.height * 0.32),
            control2: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.minY + rect.height * 0.08)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

struct MiniGamePotAsset: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [LP.Colorful.orange300, LP.Colorful.orange500],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                        .strokeBorder(LP.Colorful.orange700.opacity(0.32), lineWidth: 1.5)
                )
            Capsule()
                .fill(LP.Colorful.yellow300.opacity(0.55))
                .frame(height: 8)
                .padding(.horizontal, 10)
                .offset(y: -10)
        }
        .shadow(color: LP.Colorful.orange500.opacity(0.18), radius: 8, y: 4)
        .accessibilityHidden(true)
    }
}

private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.16, y: rect.midY - rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.16, y: rect.midY + rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.16, y: rect.midY + rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.16, y: rect.midY - rect.height * 0.16))
        path.closeSubpath()
        return path
    }
}

struct MiniGameRockAsset: View {
    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 14,
            bottomLeadingRadius: 10,
            bottomTrailingRadius: 16,
            topTrailingRadius: 9,
            style: .continuous
        )
        .fill(
            LinearGradient(
                colors: [LP.Neutral.grey200, LP.Neutral.grey500],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 14,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 16,
                topTrailingRadius: 9,
                style: .continuous
            )
            .strokeBorder(LP.Neutral.grey700.opacity(0.24), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

struct MiniGameMemoryShardAsset: View {
    var body: some View {
        SparkleShape()
            .fill(
                LinearGradient(
                    colors: [LP.Colorful.yellow200, LP.Colorful.yellow500],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(SparkleShape().stroke(LP.Colorful.yellow700.opacity(0.28), lineWidth: 1))
            .shadow(color: LP.Colorful.yellow400.opacity(0.28), radius: 8, y: 3)
            .accessibilityHidden(true)
    }
}

struct MiniGameBlackHoleAsset: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(LP.Neutral.grey900.opacity(0.84))
            Circle()
                .stroke(LP.Colorful.purple300.opacity(0.82), lineWidth: 3)
                .padding(4)
            Circle()
                .stroke(LP.Colorful.cyan300.opacity(0.42), lineWidth: 2)
                .padding(11)
        }
        .shadow(color: LP.Colorful.purple500.opacity(0.28), radius: 10)
        .accessibilityHidden(true)
    }
}

struct MiniGameTrainAsset: View {
    var tint: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.78), tint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                        .strokeBorder(.white.opacity(0.58), lineWidth: 1)
                )

            HStack(spacing: 6) {
                Circle().fill(LP.Content.primary.opacity(0.42)).frame(width: 8, height: 8)
                Circle().fill(LP.Content.primary.opacity(0.42)).frame(width: 8, height: 8)
            }
            .offset(y: 5)

            Capsule()
                .fill(.white.opacity(0.72))
                .frame(width: 24, height: 7)
                .offset(y: -9)
        }
        .shadow(color: tint.opacity(0.2), radius: 8, y: 4)
        .accessibilityHidden(true)
    }
}

struct MiniGameStationAsset: View {
    var tint: Color
    var active = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                .fill(tint.opacity(active ? 0.34 : 0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                        .strokeBorder(tint.opacity(active ? 0.72 : 0.28), lineWidth: 1.4)
                )

            VStack(spacing: 4) {
                Capsule()
                    .fill(tint.opacity(0.9))
                    .frame(width: 34, height: 8)
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(.white.opacity(0.62))
                            .frame(width: 10, height: 16)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct MiniGameKindBadgeAsset: View {
    let kind: MiniGameKind

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [kind.tint.opacity(0.86), kind.tint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))

            badgeContent
        }
        .shadow(color: kind.tint.opacity(0.18), radius: 10, y: 4)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var badgeContent: some View {
        switch kind {
        case .walkDoodle:
            MiniGameDoodleAsset(tint: .white)
                .frame(width: 28, height: 24)
        case .huarongRoad:
            MiniGameHuarongBadgeAsset()
                .frame(width: 28, height: 32)
        case .stepLights:
            ZStack {
                MiniGameFootprintAsset(side: .left)
                    .frame(width: 16, height: 24)
                    .offset(x: -7, y: 2)
                MiniGameFireflyAsset()
                    .frame(width: 13, height: 13)
                    .offset(x: 11, y: -9)
            }
        case .bellSquat:
            MiniGameBellAsset(swing: true)
                .scaleEffect(0.26)
        case .memoryMatrix:
            MiniGameMemoryGridAsset(active: [1, 4, 6])
                .frame(width: 30, height: 26)
        case .mistBreath:
            MiniGameMistAsset()
                .frame(width: 32, height: 24)
        case .breathFloat:
            ZStack {
                MiniGameRingAsset(tint: .white.opacity(0.84))
                    .frame(width: 32, height: 32)
                MiniGamePiboAsset(flowerScale: 0.22, showFlower: false)
                    .frame(width: 22, height: 22)
            }
        case .dualNBack:
            MiniGameMemoryGridAsset(active: [0, 4, 8])
                .frame(width: 30, height: 30)
        case .mirrorPetals:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 2)
                    .frame(width: 28, height: 30)
                MiniGamePetalAsset()
                    .frame(width: 11, height: 20)
                    .offset(x: 7, y: -2)
            }
        case .speedMatch:
            MiniGameMatchCardsAsset()
                .frame(width: 31, height: 25)
        case .trainThought:
            MiniGameTrainAsset(tint: .white.opacity(0.88))
                .frame(width: 30, height: 24)
        case .petDetective:
            ZStack {
                MiniGameMemoryShardAsset()
                    .frame(width: 15, height: 15)
                    .offset(x: 11, y: -10)
                MiniGamePiboAsset(flowerScale: 0.22, showFlower: false)
                    .frame(width: 24, height: 24)
                    .offset(x: -4, y: 4)
            }
        case .flowerMerge:
            ZStack {
                MiniGameFlowerAsset(level: 0)
                    .frame(width: 22, height: 22)
                    .offset(x: -7, y: 5)
                MiniGameFlowerAsset(level: 2)
                    .frame(width: 27, height: 27)
                    .offset(x: 7, y: -4)
            }
        case .potStack:
            VStack(spacing: -5) {
                ForEach(0..<3, id: \.self) { _ in
                    MiniGamePotAsset()
                        .frame(width: 29, height: 17)
                }
            }
        case .rhythmTap:
            MiniGameRhythmAsset(tint: .white)
                .frame(width: 30, height: 28)
        case .waterTiming:
            ZStack {
                MiniGameFlowerAsset(level: 1)
                    .frame(width: 25, height: 25)
                    .offset(y: 6)
                MiniGameDewAsset(tint: .white.opacity(0.85))
                    .frame(width: 14, height: 20)
                    .offset(x: 9, y: -9)
            }
        case .piboRunner:
            ZStack {
                MiniGameRockAsset()
                    .frame(width: 13, height: 13)
                    .offset(x: 13, y: 9)
                MiniGamePiboAsset(flowerScale: 0.24, showFlower: false)
                    .frame(width: 26, height: 26)
                    .offset(x: -4, y: 2)
            }
        case .idleGarden:
            MiniGameGardenPatchAsset()
                .frame(width: 32, height: 28)
        }
    }
}

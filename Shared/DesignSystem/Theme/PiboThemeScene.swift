import SwiftUI

// MARK: - Theme rendering
//
// Interprets a `PiboTheme` into views:
//   • `PiboThemeScene`    — the full backdrop (sky gradient + ground band) that
//                           sits *behind* Pibo in the home activity zone.
//   • `PiboHeadItemView`  — the 毛/花 that grows on Pibo's head for the theme.
//
// Both are pure functions of the theme tokens, so a new `PiboTheme` preset needs
// no changes here. Ground art is stylized (Canvas vector), matching the home
// 《关于毛的主题》mockup (Figma 74:6101) without trying to be pixel-perfect.

/// The themed backdrop. Place Pibo + UI on top in a `ZStack`.
struct PiboThemeScene: View {
    let theme: PiboTheme

    var body: some View {
        let scene = theme.scene
        ZStack {
            LinearGradient(
                colors: [scene.skyTop, scene.skyBottom],
                startPoint: .top, endPoint: .bottom
            )
            Canvas { ctx, size in
                Self.drawGround(scene, in: ctx, size: size)
            }
        }
        .ignoresSafeArea()
    }

    /// Draw the ground band per terrain.
    static func drawGround(_ scene: PiboScene, in ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        switch scene.terrain {
        case .meadow:
            let top = h * 0.62
            var hill = Path()
            hill.move(to: CGPoint(x: 0, y: h))
            hill.addLine(to: CGPoint(x: 0, y: top + 14))
            hill.addQuadCurve(to: CGPoint(x: w, y: top + 20),
                              control: CGPoint(x: w * 0.5, y: top - 16))
            hill.addLine(to: CGPoint(x: w, y: h))
            hill.closeSubpath()
            ctx.fill(hill, with: .color(scene.ground))
            // Scattered petals near the surface.
            for p in petals {
                let pt = CGPoint(x: p.x * w, y: top + p.y * (h - top))
                let r: CGFloat = 3 + p.s * 4
                let petal = Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r * 0.7,
                                                   width: r * 2, height: r * 1.4))
                ctx.fill(petal, with: .color(scene.groundAccent.opacity(0.85)))
            }

        case .beach:
            let seaTop = h * 0.56, sandTop = h * 0.66
            // Sea band with a wavy lower edge.
            var sea = Path()
            sea.move(to: CGPoint(x: 0, y: seaTop))
            sea.addLine(to: CGPoint(x: w, y: seaTop))
            sea.addLine(to: CGPoint(x: w, y: sandTop))
            sea.addQuadCurve(to: CGPoint(x: 0, y: sandTop),
                             control: CGPoint(x: w * 0.5, y: sandTop + 16))
            sea.closeSubpath()
            ctx.fill(sea, with: .color(scene.groundAccent))
            // Sand below, meeting the sea on the same wave.
            var sand = Path()
            sand.move(to: CGPoint(x: 0, y: sandTop))
            sand.addQuadCurve(to: CGPoint(x: w, y: sandTop),
                              control: CGPoint(x: w * 0.5, y: sandTop + 16))
            sand.addLine(to: CGPoint(x: w, y: h))
            sand.addLine(to: CGPoint(x: 0, y: h))
            sand.closeSubpath()
            ctx.fill(sand, with: .color(scene.ground))
            // Foam line.
            var foam = Path()
            foam.move(to: CGPoint(x: 0, y: sandTop))
            foam.addQuadCurve(to: CGPoint(x: w, y: sandTop),
                              control: CGPoint(x: w * 0.5, y: sandTop + 16))
            ctx.stroke(foam, with: .color(.white.opacity(0.7)), lineWidth: 2)

        case .platform:
            let topY = h * 0.72
            // Slab top face (parallelogram).
            var face = Path()
            face.move(to: CGPoint(x: w * 0.14, y: topY + h * 0.02))
            face.addLine(to: CGPoint(x: w * 0.86, y: topY - h * 0.02))
            face.addLine(to: CGPoint(x: w * 0.93, y: topY + h * 0.025))
            face.addLine(to: CGPoint(x: w * 0.21, y: topY + h * 0.065))
            face.closeSubpath()
            ctx.fill(face, with: .color(scene.ground))
            // Front thickness edge (darker).
            var edge = Path()
            edge.move(to: CGPoint(x: w * 0.21, y: topY + h * 0.065))
            edge.addLine(to: CGPoint(x: w * 0.93, y: topY + h * 0.025))
            edge.addLine(to: CGPoint(x: w * 0.93, y: topY + h * 0.055))
            edge.addLine(to: CGPoint(x: w * 0.21, y: topY + h * 0.095))
            edge.closeSubpath()
            ctx.fill(edge, with: .color(scene.groundAccent))
        }
    }

    /// Deterministic petal layout (x, y in 0…1 of the ground band, s = size).
    private static let petals: [(x: CGFloat, y: CGFloat, s: CGFloat)] = [
        (0.08, 0.42, 0.6), (0.17, 0.70, 0.3), (0.27, 0.30, 0.9), (0.34, 0.62, 0.5),
        (0.45, 0.48, 0.2), (0.52, 0.78, 0.7), (0.61, 0.36, 0.4), (0.69, 0.66, 0.8),
        (0.77, 0.44, 0.3), (0.84, 0.72, 0.6), (0.91, 0.34, 0.5), (0.96, 0.60, 0.2),
        (0.13, 0.88, 0.4), (0.58, 0.92, 0.3),
    ]
}

// MARK: - Head item

/// The 毛/花 on Pibo's head. Size is the rendered height in points.
struct PiboHeadItemView: View {
    let item: PiboHeadItem
    var size: CGFloat = 56

    private static let green = Color(hex: 0x2FAE66)
    private static let twig  = Color(hex: 0x8A6A4A)
    private static let bloom = Color(hex: 0xF3A9BE)

    var body: some View {
        switch item {
        case .sprout:    sprout
        case .peachBranch: peachBranch
        case .seaweed:   seaweed
        case .mystery:   mystery
        }
    }

    private var sprout: some View {
        ZStack {
            Capsule().fill(Self.green)
                .frame(width: size * 0.10, height: size * 0.66)
            leaf.fill(Self.green)
                .frame(width: size * 0.42, height: size * 0.30)
                .rotationEffect(.degrees(-34)).offset(x: -size * 0.16, y: -size * 0.16)
            leaf.fill(Self.green)
                .frame(width: size * 0.42, height: size * 0.30)
                .rotationEffect(.degrees(34)).scaleEffect(x: -1)
                .offset(x: size * 0.16, y: -size * 0.22)
        }
        .frame(width: size, height: size)
    }

    private var peachBranch: some View {
        ZStack {
            Capsule().fill(Self.twig)
                .frame(width: size * 0.08, height: size * 0.7)
                .rotationEffect(.degrees(12))
            Circle().fill(Self.bloom)
                .frame(width: size * 0.34, height: size * 0.34)
                .offset(x: size * 0.04, y: -size * 0.24)
            Circle().fill(Self.bloom.opacity(0.85))
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: -size * 0.16, y: -size * 0.02)
            Circle().fill(.white.opacity(0.9))
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: size * 0.04, y: -size * 0.24)
        }
        .frame(width: size, height: size)
    }

    private var seaweed: some View {
        leaf
            .fill(Self.green)
            .frame(width: size * 0.5, height: size * 0.82)
            .rotationEffect(.degrees(-12))
            .frame(width: size, height: size)
    }

    private var mystery: some View {
        ZStack {
            Ellipse().fill(.black)
                .frame(width: size * 1.5, height: size * 0.5)
            Text("?")
                .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
                .foregroundStyle(Self.green)
                .offset(y: -size * 0.06)
        }
        .frame(width: size * 1.6, height: size)
    }

    /// A simple leaf shape (used by sprout + seaweed).
    private var leaf: LeafShape { LeafShape() }
}

/// A pointed leaf — two opposing quad curves.
private struct LeafShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY),
                       control: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY),
                       control: CGPoint(x: r.maxX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Preview

#Preview("Pibo themes") {
    ScrollView(.horizontal) {
        HStack(spacing: 0) {
            ForEach(PiboTheme.previewFixtures) { theme in
                ZStack(alignment: .top) {
                    PiboThemeScene(theme: theme)
                    VStack(spacing: LP.Spacing.s2) {
                        Text(theme.displayName.isEmpty ? "默认" : theme.displayName)
                            .lpText(LP.Typography.uiH5)
                            .foregroundStyle(LP.Content.primary)
                            .padding(.top, LP.Spacing.l)
                        Spacer()
                        // Pibo placeholder blob with the head item on top.
                        ZStack(alignment: .top) {
                            Capsule().fill(.white)
                                .frame(width: 96, height: 110)
                                .overlay(Capsule().stroke(LP.Content.quarternary, lineWidth: 1.5))
                            PiboHeadItemView(item: theme.headItem)
                                .offset(y: -42)
                        }
                        .padding(.bottom, 80)
                    }
                }
                .frame(width: 240, height: 480)
                .clipShape(RoundedRectangle(cornerRadius: LP.Radius.xl))
            }
        }
        .padding(LP.Spacing.l)
    }
    .background(LP.Fill.bgSurface)
}

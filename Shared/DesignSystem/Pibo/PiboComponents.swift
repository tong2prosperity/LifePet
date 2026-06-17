import SwiftUI

// MARK: - Pibo body-part components (separated, Figma-faithful)
//
// Each Pibo part is its own `View`/`Shape`, drawn from the EXACT Figma geometry
// of the 主体形象 (node `1855:4343`) — not a hand-drawn approximation. The
// organic parts (身子 / 手 / 腿 / 头顶植物) embed the real Figma bezier paths;
// the face primitives (眼睛 大椭圆 / 眉毛 小圆 / 鼻子 双瓣) are the exact Figma
// ellipses/circles. Everything stays recolorable + parametric so the editor can
// still customize, but the DEFAULT renders identical to the design.
//
// Source SVGs (Figma dev-mode export):
//   • 身子  Vector 9   viewBox 226.195 × 212.156, fill #FFFFFF
//   • 手    Vector 16  viewBox 51.2648 × 135.003, stroke #FFFFFF width 32 round
//   • 腿    Group 72   two vertical strokes, width 32 round → tall capsules
//   • 脸    Group 48   eyes rx10.5 ry5.5 #56616C · brows r3.38 #56616C · nose
//                       rx11.7 ry10.4 #D7E0E5  (in a 72 × 52 box)
//   • 头顶植物 Group 83 leaf fill #468B5B + white vein, viewBox 45.6353 × 127.067

/// Map native SVG coords → a target rect (the Shape's frame).
@inline(__always)
private func sp(_ x: CGFloat, _ y: CGFloat, in r: CGRect, _ w: CGFloat, _ h: CGFloat) -> CGPoint {
    CGPoint(x: r.minX + x / w * r.width, y: r.minY + y / h * r.height)
}

// MARK: 身子 — Figma body path (Vector 9)

/// The exact Figma body blob — a single closed bezier, recolored by the caller.
struct PiboBodyShape: Shape {
    func path(in r: CGRect) -> Path {
        let w: CGFloat = 226.195, h: CGFloat = 212.156
        var p = Path()
        p.move(to: sp(99.3059, 0.291955, in: r, w, h))
        p.addCurve(to: sp(16.4509, 169.987, in: r, w, h),
                   control1: sp(16.9664, 5.41454, in: r, w, h),
                   control2: sp(-25.6264, 119.537, in: r, w, h))
        p.addCurve(to: sp(210.213, 161.388, in: r, w, h),
                   control1: sp(58.5282, 220.437, in: r, w, h),
                   control2: sp(157.757, 234.786, in: r, w, h))
        p.addCurve(to: sp(99.3059, 0.291955, in: r, w, h),
                   control1: sp(253.848, 100.332, in: r, w, h),
                   control2: sp(205.277, -6.30086, in: r, w, h))
        p.closeSubpath()
        return p
    }
}

// MARK: 手 — Figma arm centerline (Vector 16)

/// The arm centerline — stroked (round cap, width ≈ 32 native units) by the
/// composer so it scales with the portrait. The composer mirrors it for the
/// right arm.
struct PiboArmShape: Shape {
    /// Native stroke width in the 51.2648 × 135.003 viewBox.
    static let nativeWidth: CGFloat = 32
    static let viewBox = CGSize(width: 51.2648, height: 135.003)
    func path(in r: CGRect) -> Path {
        let w = Self.viewBox.width, h = Self.viewBox.height
        var p = Path()
        p.move(to: sp(35.2617, 16.0031, in: r, w, h))
        p.addCurve(to: sp(16.2617, 119.003, in: r, w, h),
                   control1: sp(16.2617, 51.0031, in: r, w, h),
                   control2: sp(15.2617, 99.0031, in: r, w, h))
        return p
    }
}

// MARK: 眼睛 — big ellipse

/// One eye (the *大椭圆*). Drawn upright inside `size`; the composer applies tilt
/// + mirroring. `wink` is stroked, the rest are filled. The Figma default is
/// `.ellipse` (rx10.5 ry5.5, axis-aligned).
struct PiboEye: View {
    var shape: PiboEyeShape
    var size: CGSize
    var color: Color

    var body: some View {
        switch shape {
        case .ellipse:
            Ellipse().fill(color).frame(width: size.width, height: size.height)
        case .round:
            let d = min(size.width, size.height) * 1.4
            Circle().fill(color).frame(width: d, height: d)
        case .sleepy:
            SleepyEyeShape().fill(color).frame(width: size.width, height: size.height)
        case .sparkle:
            ZStack {
                Ellipse().fill(color)
                Circle().fill(.white.opacity(0.92))
                    .frame(width: size.width * 0.32, height: size.width * 0.32)
                    .offset(x: -size.width * 0.14, y: -size.height * 0.22)
            }
            .frame(width: size.width, height: size.height)
        case .wink:
            WinkEyeShape()
                .stroke(color, style: StrokeStyle(lineWidth: max(2, size.height * 0.55),
                                                  lineCap: .round, lineJoin: .round))
                .frame(width: size.width, height: size.height)
        }
    }
}

/// Lower half-disc — a half-lidded / sleepy eye.
private struct SleepyEyeShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY),
                       control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.6))
        p.closeSubpath()
        return p
    }
}

/// Upward smile arc — a happy ◡ eye.
private struct WinkEyeShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY * 0.78))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY * 0.78),
                       control: CGPoint(x: r.midX, y: r.minY))
        return p
    }
}

// MARK: 眉毛 — small circle

/// One eyebrow (the *小圆*). Figma default is `.dot` (r3.38). `slash` rotates by
/// the composer-passed `angle`.
struct PiboBrow: View {
    var shape: PiboBrowShape
    var size: CGSize
    var color: Color
    var angle: Double = 0

    var body: some View {
        switch shape {
        case .dot:
            let d = min(size.width, size.height)
            Circle().fill(color).frame(width: d, height: d)
        case .dash:
            Capsule().fill(color)
                .frame(width: size.width, height: max(2, size.height * 0.5))
        case .slash:
            Capsule().fill(color)
                .frame(width: size.width, height: max(2, size.height * 0.5))
                .rotationEffect(.degrees(angle))
        case .none:
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

// MARK: 鼻子 / 腮 — light double bump

/// The nose / 腮 — the light double bump below the eyes (Figma two ellipses
/// rx11.7 ry10.4 #D7E0E5, centers 16.6 apart so they overlap).
struct PiboNose: View {
    var shape: PiboNoseShape
    var size: CGSize
    var color: Color

    var body: some View {
        switch shape {
        case .doubleBump:
            // Two overlapping ellipses; exact Figma ratios (bump 23.4 / span 40,
            // centers ±8.32 → ±0.208).
            ZStack {
                Ellipse().fill(color)
                    .frame(width: size.width * 0.585, height: size.height)
                    .offset(x: -size.width * 0.208)
                Ellipse().fill(color)
                    .frame(width: size.width * 0.585, height: size.height)
                    .offset(x: size.width * 0.208)
            }
            .frame(width: size.width, height: size.height)
        case .single:
            Ellipse().fill(color)
                .frame(width: size.width * 0.62, height: size.height)
        case .none:
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

// MARK: 腿 / 脚 — tall capsule (Figma foot stroke)

/// One foot — the Figma foot is a vertical line stroked 32 wide with round caps,
/// i.e. a tall capsule. The composer mirrors + spreads the pair and tucks the
/// tops behind the body.
struct PiboLeg: View {
    var size: CGSize
    var color: Color

    var body: some View {
        Capsule().fill(color).frame(width: size.width, height: size.height)
    }
}

// MARK: 头顶植物 — the head plant (its own component)

/// The plant growing on Pibo's head. **Separated on purpose.** `.singleLeaf` is
/// the exact Figma leaf (Group 83); the others are parametric alternatives. Drawn
/// within `size` (height ≈ `size`), colored by `color`; the composer applies sway.
struct PiboPlant: View {
    var kind: PiboPlantKind
    var size: CGFloat
    var color: Color

    /// Figma leaf aspect (viewBox 45.6353 / 127.067).
    static let leafAspect: CGFloat = 45.6353 / 127.067

    var body: some View {
        switch kind {
        case .singleLeaf: singleLeaf
        case .sprout:     sprout
        case .bud:        bud
        case .curl:       curl
        }
    }

    /// The exact Figma single curved leaf + white center vein.
    private var singleLeaf: some View {
        let w = size * Self.leafAspect
        return ZStack {
            PiboFigmaLeafShape().fill(color)
            PiboFigmaLeafShape().stroke(.white.opacity(0.9), lineWidth: max(0.5, size * 0.004))
            PiboFigmaLeafVein().stroke(.white.opacity(0.85), lineWidth: max(0.8, size * 0.008))
        }
        .frame(width: w, height: size)
        .frame(width: size, height: size)   // center the narrow leaf in a square slot
    }

    /// Two opposing leaves on a short stem.
    private var sprout: some View {
        ZStack {
            Capsule().fill(color)
                .frame(width: size * 0.10, height: size * 0.6)
                .offset(y: size * 0.12)
            PiboLeafShape().fill(color)
                .frame(width: size * 0.46, height: size * 0.34)
                .rotationEffect(.degrees(-36)).offset(x: -size * 0.17, y: -size * 0.10)
            PiboLeafShape().fill(color)
                .frame(width: size * 0.46, height: size * 0.34)
                .rotationEffect(.degrees(36)).scaleEffect(x: -1)
                .offset(x: size * 0.17, y: -size * 0.16)
        }
        .frame(width: size, height: size)
    }

    /// A twig with a couple of blossom circles.
    private var bud: some View {
        ZStack {
            Capsule().fill(color.opacity(0.9))
                .frame(width: size * 0.08, height: size * 0.66)
                .rotationEffect(.degrees(10))
            Circle().fill(color)
                .frame(width: size * 0.34, height: size * 0.34)
                .offset(x: size * 0.03, y: -size * 0.22)
            Circle().fill(color.opacity(0.85))
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: -size * 0.15, y: 0)
            Circle().fill(.white.opacity(0.85))
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: size * 0.03, y: -size * 0.22)
        }
        .frame(width: size, height: size)
    }

    /// The 魔丸 「?」 curl — a stem ending in a curled tip.
    private var curl: some View {
        ZStack {
            CurlShape()
                .stroke(color, style: StrokeStyle(lineWidth: max(2, size * 0.10),
                                                  lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.5, height: size)
            Circle().fill(color)
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(x: size * 0.02, y: size * 0.40)
        }
        .frame(width: size, height: size)
    }
}

/// The exact Figma single-leaf fill path (Group 83 / Vector 41), viewBox
/// 45.6353 × 127.067.
struct PiboFigmaLeafShape: Shape {
    func path(in r: CGRect) -> Path {
        let w: CGFloat = 45.6353, h: CGFloat = 127.067
        var p = Path()
        p.move(to: sp(40.7111, 78.989, in: r, w, h))
        p.addCurve(to: sp(27.2111, 122.989, in: r, w, h),
                   control1: sp(44.7111, 89.989, in: r, w, h), control2: sp(29.7111, 95.489, in: r, w, h))
        p.addCurve(to: sp(22.2112, 81.489, in: r, w, h),
                   control1: sp(24.5445, 114.822, in: r, w, h), control2: sp(19.8112, 95.089, in: r, w, h))
        p.addCurve(to: sp(8.21114, 41.489, in: r, w, h),
                   control1: sp(25.2112, 64.489, in: r, w, h), control2: sp(15.7111, 56.989, in: r, w, h))
        p.addCurve(to: sp(8.21114, 4.98896, in: r, w, h),
                   control1: sp(0.711138, 25.989, in: r, w, h), control2: sp(5.71114, -0.511043, in: r, w, h))
        p.addCurve(to: sp(32.2111, 26.489, in: r, w, h),
                   control1: sp(10.7111, 10.489, in: r, w, h), control2: sp(19.2111, 22.489, in: r, w, h))
        p.addCurve(to: sp(32.2111, 56.989, in: r, w, h),
                   control1: sp(45.2111, 30.489, in: r, w, h), control2: sp(31.7111, 44.989, in: r, w, h))
        p.addCurve(to: sp(40.7111, 78.989, in: r, w, h),
                   control1: sp(32.7111, 68.989, in: r, w, h), control2: sp(36.7111, 67.989, in: r, w, h))
        p.closeSubpath()
        return p
    }
}

/// The leaf's white center vein (Vector 42).
struct PiboFigmaLeafVein: Shape {
    func path(in r: CGRect) -> Path {
        let w: CGFloat = 45.6353, h: CGFloat = 127.067
        var p = Path()
        p.move(to: sp(8.21093, 3.98895, in: r, w, h))
        p.addCurve(to: sp(28.7109, 61.989, in: r, w, h),
                   control1: sp(10.7109, 27.489, in: r, w, h), control2: sp(26.2109, 33.989, in: r, w, h))
        p.addCurve(to: sp(27.5056, 125.989, in: r, w, h),
                   control1: sp(30.8562, 86.0159, in: r, w, h), control2: sp(24.0987, 109.914, in: r, w, h))
        return p
    }
}

/// A pointed leaf — used by the `sprout` variant.
struct PiboLeafShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

/// A curl — stem rising then hooking over, for the `curl` variant.
private struct CurlShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.midY),
                       control: CGPoint(x: r.midX - r.width * 0.1, y: r.maxY * 0.75))
        p.addArc(center: CGPoint(x: r.midX + r.width * 0.22, y: r.midY),
                 radius: r.width * 0.24,
                 startAngle: .degrees(180), endAngle: .degrees(20), clockwise: false)
        return p
    }
}

// MARK: - Previews (each component stands alone)

#Preview("Pibo components") {
    let ink = Color(hex: 0x56616C)
    return ScrollView {
        VStack(spacing: LP.Spacing.l) {
            PiboBodyShape().fill(.white)
                .frame(width: 160, height: 150)
                .background(Color(hex: 0xEAEEF0))
            HStack(spacing: 20) {
                ForEach(PiboEyeShape.allCases) { s in
                    PiboEye(shape: s, size: CGSize(width: 34, height: 18), color: ink)
                        .frame(width: 40, height: 30)
                }
            }
            HStack(spacing: 24) {
                ForEach(PiboPlantKind.allCases) { k in
                    PiboPlant(kind: k, size: 80, color: Color(hex: 0x468B5B))
                }
            }
        }
        .padding(40)
    }
    .background(Color(hex: 0xEAEEF0))
}

import SwiftUI

/// 品种(bohair) selector — three sprout cards with the center one highlighted and
/// tagged by rarity (Figma `bohair card list` 1194:1170 + `hair label` 1374:633).
///
/// Display-only for now: there's no 品种 data model yet (认知能量 will unlock
/// 品种 later — see CLAUDE.md energy table), so the side cards are dimmed copies
/// and the center shows the day's sprout with an "SSR" tab. Wire to a real 品种
/// per day when that system lands.
struct HistoryBohairList: View {
    var rarity: String = "SSR"

    var body: some View {
        HStack(spacing: 31) {
            bohairCard(size: 80, glyph: 40).opacity(0.3)
            VStack(spacing: 0) {
                Text(rarity)
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Content.accent)
                    .padding(.horizontal, LP.Spacing.l)
                    .padding(.vertical, 2)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: LP.Radius.l, topTrailingRadius: LP.Radius.l)
                            .fill(LP.Colorful.green200))
                bohairCard(size: 120, glyph: 60)
            }
            bohairCard(size: 80, glyph: 40).opacity(0.3)
        }
    }

    private func bohairCard(size: CGFloat, glyph: CGFloat) -> some View {
        SproutGlyph()
            .frame(width: glyph, height: glyph)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(LP.Fill.bgContainer))
            .lpShadow(LP.Shadow.elevation1)
    }
}

/// A flat green seedling glyph (stem + two leaves) — stands in for the Figma
/// `bohair` sprout vector (1194:1147) without shipping a raster asset.
struct SproutGlyph: View {
    var color: Color = LP.Colorful.green500

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Capsule()
                    .fill(color)
                    .frame(width: max(2, w * 0.07), height: h * 0.52)
                    .offset(y: h * 0.2)
                LeafShape()
                    .fill(color)
                    .frame(width: w * 0.5, height: h * 0.36)
                    .rotationEffect(.degrees(-32))
                    .offset(x: -w * 0.17, y: h * 0.02)
                LeafShape()
                    .fill(color)
                    .frame(width: w * 0.5, height: h * 0.36)
                    .rotationEffect(.degrees(32))
                    .offset(x: w * 0.17, y: -h * 0.1)
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(0.9, contentMode: .fit)
    }
}

/// A pointed leaf (two mirrored quad curves meeting at tip + base).
private struct LeafShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

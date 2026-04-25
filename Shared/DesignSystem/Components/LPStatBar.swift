import SwiftUI

/// 8pt-tall progress bar with a 1.5pt ink border and a radius-2 track.
/// The *fill* encodes meaning — don't swap variants for visual variety.
///
/// - `.ink`: neutral fact (default).
/// - `.coral`: needs attention (low sleep, high stress).
/// - `.sage`: doing well (streak, recovery).
/// - `.striped`: unmet need / absent data (45° ink stripes, drawn via `Canvas`).
struct LPStatBar: View {
    enum Variant { case ink, coral, sage, striped }

    let label: String
    let valueText: String
    /// Value in [0, 1].
    let progress: Double
    let variant: Variant

    init(label: String, valueText: String, progress: Double, variant: Variant = .ink) {
        self.label = label
        self.valueText = valueText
        self.progress = min(max(progress, 0), 1)
        self.variant = variant
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s1) {
            HStack {
                Text(label).lpText(LP.Typography.monoTiny).foregroundStyle(LP.Colors.muted)
                Spacer(minLength: LP.Spacing.s2)
                Text(valueText).lpText(LP.Typography.monoTiny).foregroundStyle(LP.Colors.muted)
            }
            track
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(valueText))
    }

    // MARK: - Track

    /// The track is a single `ZStack` with three layers:
    /// 1. paper fill behind everything
    /// 2. the progress fill, clipped to the track radius
    /// 3. the ink stroke on top, so it always stays crisp over the fill
    ///
    /// We keep the `GeometryReader` narrow-scoped and apply `.frame(height: 8)`
    /// with `.fixedSize(horizontal: false, vertical: true)` so the reader can't
    /// expand vertically in a `VStack` and push siblings.
    private var track: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: LP.Radius.button, style: .continuous)
            ZStack(alignment: .leading) {
                shape.fill(LP.Colors.paperCard)
                fillView(width: geo.size.width * progress, height: geo.size.height)
                    .clipShape(shape)
                shape.strokeBorder(LP.Colors.ink, lineWidth: LP.BorderWidth.regular)
            }
        }
        .frame(height: 8)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func fillView(width: CGFloat, height: CGFloat) -> some View {
        switch variant {
        case .ink:
            Rectangle().fill(LP.Colors.ink).frame(width: max(0, width))
        case .coral:
            Rectangle().fill(LP.Colors.coral).frame(width: max(0, width))
        case .sage:
            Rectangle().fill(LP.Colors.sage).frame(width: max(0, width))
        case .striped:
            StripeTexture().frame(width: max(0, width))
        }
    }
}

// MARK: - Previews

#Preview("Variants") {
    VStack(alignment: .leading, spacing: LP.Spacing.s4) {
        LPStatBar(label: "SLEEP",    valueText: "72", progress: 0.72, variant: .ink)
        LPStatBar(label: "ACTIVITY", valueText: "48", progress: 0.48, variant: .coral)
        LPStatBar(label: "CALM",     valueText: "86", progress: 0.86, variant: .sage)
        LPStatBar(label: "COMPANY",  valueText: "34", progress: 0.34, variant: .striped)
    }
    .padding(LP.Spacing.s5)
    .frame(maxWidth: 320)
    .lpPaper(.app)
}

// MARK: - Stripe texture

/// 45° ink stripes on a paper field — matches the CSS
/// `repeating-linear-gradient(45deg, ink 0 3px, transparent 3px 6px)` texture.
/// Uses `Canvas` because SwiftUI's `LinearGradient` can't express a *repeating*
/// pattern — a gradient interpolates across its stops once.
private struct StripeTexture: View {
    /// Width of one ink dash measured horizontally.
    private let dashWidth: CGFloat = 3
    /// Width of the paper gap between dashes.
    private let gapWidth: CGFloat = 3

    var body: some View {
        Canvas(opaque: false) { ctx, size in
            let stride = dashWidth + gapWidth
            // Start one height's worth to the left so the 45° slant covers the
            // left edge cleanly, then march across until we're past the right.
            var x = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + dashWidth, y: 0))
                path.addLine(to: CGPoint(x: x + dashWidth + size.height, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                path.closeSubpath()
                ctx.fill(path, with: .color(LP.Colors.ink))
                x += stride
            }
        }
    }
}

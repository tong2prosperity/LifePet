import SwiftUI

/// 1.5pt-tall dashed horizontal rule. Use this for section separators —
/// it draws via `Path.stroke`, which is what `Rectangle().strokeBorder` would
/// silently fail to do at sub-stroke-width heights (the `strokeBorder` inset
/// collapses the path).
///
/// ```swift
/// LPDashedRule()                          // hairline divider, default dash
/// LPDashedRule(color: LP.Colors.coral)    // accent-colored
/// ```
struct LPDashedRule: View {
    var color: Color = LP.Colors.hairline
    var lineWidth: CGFloat = LP.BorderWidth.regular
    var dash: [CGFloat] = LP.DashPattern.draft

    var body: some View {
        GeometryReader { geo in
            Path { p in
                let y = lineWidth / 2
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: geo.size.width, y: y))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, dash: dash))
        }
        .frame(height: lineWidth)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: LP.Spacing.s4) {
        LPDashedRule()
        LPDashedRule(color: LP.Colors.coral, dash: [4, 3])
        LPDashedRule(color: LP.Colors.ink, lineWidth: 1, dash: [2, 2])
    }
    .padding(LP.Spacing.s5)
    .lpPaper(.app)
}

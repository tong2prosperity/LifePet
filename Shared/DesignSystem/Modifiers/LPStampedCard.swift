import SwiftUI

extension View {
    /// "Stamped" card — paper-tone fill, 1.5pt ink stroke, with a same-shape
    /// ink rectangle peeking 2pt down-and-right behind the card. This is the
    /// signature card chrome for the home screen and figure-pad surfaces;
    /// `lpCard(...)` (the flat default) is for editorial / muted contexts.
    ///
    /// ```swift
    /// VStack { … }
    ///     .lpStampedCard()                                    // default fill
    ///     .lpStampedCard(fill: doneBg, dashed: true)          // tinted + dashed
    /// ```
    func lpStampedCard(
        radius: CGFloat = 10,
        padding: EdgeInsets = .init(top: 9, leading: 11, bottom: 8, trailing: 11),
        fill: Color = LP.Colors.paperCool,
        stroke: Color = LP.Colors.ink,
        dashed: Bool = false,
        offset: CGSize = CGSize(width: 2, height: 2)
    ) -> some View {
        modifier(LPStampedCardModifier(
            radius: radius,
            padding: padding,
            fill: fill,
            stroke: stroke,
            dashed: dashed,
            offset: offset
        ))
    }
}

private struct LPStampedCardModifier: ViewModifier {
    let radius: CGFloat
    let padding: EdgeInsets
    let fill: Color
    let stroke: Color
    let dashed: Bool
    let offset: CGSize

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            )
            .overlay(border)
            .background(
                // The same-size shadow rect, offset down-right behind the card.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(stroke)
                    .offset(x: offset.width, y: offset.height)
            )
    }

    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if dashed {
            shape.strokeBorder(stroke, style: StrokeStyle(lineWidth: LP.BorderWidth.regular, dash: [5, 4]))
        } else {
            shape.strokeBorder(stroke, lineWidth: LP.BorderWidth.regular)
        }
    }
}

#Preview("Variants") {
    VStack(spacing: LP.Spacing.s4) {
        Text("Default stamped card")
            .lpText(LP.Typography.body)
            .lpStampedCard()
        Text("Tinted + dashed")
            .lpText(LP.Typography.body)
            .lpStampedCard(fill: Color(hex: 0xFEF4E6), dashed: true)
        Text("Sage + larger")
            .lpText(LP.Typography.body)
            .lpStampedCard(radius: 14, fill: LP.Colors.sageSoft, stroke: LP.Colors.sage)
    }
    .padding(LP.Spacing.s5)
    .lpPaper(.app)
}

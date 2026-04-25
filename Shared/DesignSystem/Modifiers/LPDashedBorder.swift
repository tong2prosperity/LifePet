import SwiftUI

extension View {
    /// Draw a solid LP border on top of the view.
    func lpSolidBorder(
        _ color: Color = LP.Colors.ink,
        width: CGFloat = LP.BorderWidth.regular,
        radius: CGFloat = LP.Radius.card
    ) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: width)
        )
    }

    /// Draw a dashed LP border. Dashed = *draft* in this system — placeholder,
    /// unlocked-later, or optional slot. Don't use it for mere decoration.
    func lpDashedBorder(
        _ color: Color = LP.Colors.ink,
        width: CGFloat = LP.BorderWidth.regular,
        radius: CGFloat = LP.Radius.card,
        dash: [CGFloat] = LP.DashPattern.draft
    ) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    color,
                    // `.butt` cap matches CSS `border: dashed` — round caps would
                    // lengthen each dash by lineWidth and swallow the gaps.
                    style: StrokeStyle(lineWidth: width, lineCap: .butt, dash: dash)
                )
        )
    }
}

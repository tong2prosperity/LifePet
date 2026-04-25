import SwiftUI

extension LP {
    enum CardVariant {
        case `default`   // white card, ink border
        case coral       // P0 — current state, pet emotion
        case sage        // P1 — health, social, achievement
        case ghost       // draft / unlocked-later (dashed)

        var fill: Color {
            switch self {
            case .default: return LP.Colors.paperCard
            case .coral:   return LP.Colors.coralSoft
            case .sage:    return LP.Colors.sageSoft
            case .ghost:   return LP.Colors.paperCard
            }
        }

        var stroke: Color {
            switch self {
            case .default, .ghost: return LP.Colors.ink
            case .coral:           return LP.Colors.coral
            case .sage:            return LP.Colors.sage
            }
        }

        var isDashed: Bool {
            switch self {
            case .ghost:                   return true
            case .default, .coral, .sage:  return false
            }
        }
    }
}

extension View {
    /// Wrap a view in an LP card surface (fill + 1.5pt stroke + radius + padding).
    /// The ghost variant swaps to a dashed border.
    func lpCard(
        _ variant: LP.CardVariant = .default,
        padding: CGFloat = LP.Spacing.cardPadding,
        radius: CGFloat = LP.Radius.card
    ) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(variant.fill)
            )
            .modifier(LPCardStroke(variant: variant, radius: radius))
    }
}

private struct LPCardStroke: ViewModifier {
    let variant: LP.CardVariant
    let radius: CGFloat

    func body(content: Content) -> some View {
        if variant.isDashed {
            content.lpDashedBorder(variant.stroke, radius: radius)
        } else {
            content.lpSolidBorder(variant.stroke, radius: radius)
        }
    }
}

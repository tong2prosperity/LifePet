import SwiftUI

/// LifePet button. One primary per screen, Mono 11pt / uppercase / tracking 0.2em,
/// radius 2pt, 1.5pt border.
///
/// Variants:
/// - **primary** — ink fill, paper label. The one main action.
/// - **secondary** — paper fill, ink border. Side actions.
/// - **coral** — coral fill for P0 emotional moments (e.g. "PET IS SICK → TEND").
/// - **ghost** — dashed border for draft / optional / unlocked-later.
///
/// Two initializers:
/// - `LPButton("START", variant: .primary) { … }` — plain string label.
/// - `LPButton(variant: .primary, action: …) { Label("START", systemImage: "play") }`
///   — custom label builder when you need an icon or formatted content.
/// Variant for `LPButton`. Hoisted out of the generic so call sites never have
/// to spell `LPButton<Text>.Variant`.
enum LPButtonVariant { case primary, secondary, coral, ghost }

struct LPButton<Label: View>: View {
    typealias Variant = LPButtonVariant

    let variant: Variant
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    init(
        variant: Variant = .secondary,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.variant = variant
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
                .lpText(LP.Typography.monoLabel)
                .foregroundStyle(foreground)
                .padding(.horizontal, LP.Spacing.s4)
                .padding(.vertical, verticalPadding)
                .frame(minHeight: minHeight)
                .background(
                    RoundedRectangle(cornerRadius: LP.Radius.button, style: .continuous)
                        .fill(background)
                )
                .modifier(LPButtonStroke(variant: variant))
                // Make the full chrome tappable — especially important for
                // `.ghost` where the fill is transparent.
                .contentShape(RoundedRectangle(cornerRadius: LP.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // Platform-aware sizing: iOS follows the 44pt hit-area guide; watchOS trims
    // so buttons don't eat the vertical budget on a 41mm face.
    private var verticalPadding: CGFloat {
        #if os(watchOS)
        return LP.Spacing.s2
        #else
        return LP.Spacing.s3
        #endif
    }

    private var minHeight: CGFloat {
        #if os(watchOS)
        return 34
        #else
        return 44
        #endif
    }

    private var foreground: Color {
        switch variant {
        case .primary:             return LP.Colors.paper
        case .coral:               return .white
        case .secondary, .ghost:   return LP.Colors.ink
        }
    }

    private var background: Color {
        switch variant {
        case .primary:             return LP.Colors.ink
        case .coral:               return LP.Colors.coral
        case .secondary:           return LP.Colors.paperCard
        case .ghost:               return .clear
        }
    }
}

// MARK: - Plain-string convenience

extension LPButton where Label == Text {
    init(_ title: String, variant: Variant = .secondary, action: @escaping () -> Void) {
        self.init(variant: variant, action: action, label: { Text(title) })
    }
}

// MARK: - Stroke

private struct LPButtonStroke: ViewModifier {
    let variant: LPButtonVariant

    func body(content: Content) -> some View {
        switch variant {
        case .primary, .secondary, .coral:
            content.lpSolidBorder(strokeColor, radius: LP.Radius.button)
        case .ghost:
            content.lpDashedBorder(LP.Colors.ink, radius: LP.Radius.button)
        }
    }

    private var strokeColor: Color {
        switch variant {
        case .coral: return LP.Colors.coral
        default:     return LP.Colors.ink
        }
    }
}

// MARK: - Previews

#Preview("Variants") {
    VStack(alignment: .leading, spacing: LP.Spacing.s3) {
        LPButton("PRIMARY",   variant: .primary)   {}
        LPButton("SECONDARY", variant: .secondary) {}
        LPButton("CORAL",     variant: .coral)     {}
        LPButton("GHOST",     variant: .ghost)     {}
    }
    .padding(LP.Spacing.s5)
    .lpPaper(.app)
}

#Preview("With icon label") {
    LPButton(variant: .primary, action: {}) {
        Label("START", systemImage: "play.fill")
    }
    .padding(LP.Spacing.s5)
    .lpPaper(.app)
}

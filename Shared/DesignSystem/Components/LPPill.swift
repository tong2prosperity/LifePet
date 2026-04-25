import SwiftUI

/// Small capsule tag — version numbers, priorities, filter chips, age ranges.
/// Always Mono, always uppercase.
///
/// Pass an `action` to get a tappable filter chip; omit it for a static tag.
struct LPPill: View {
    enum Variant { case `default`, coral, sage, ghost }

    /// Half-step vertical padding. Pills need a 3pt inset to look right at the
    /// 10pt Mono tiny size — documented here instead of hidden as a magic literal.
    private static let verticalPadding: CGFloat = 3

    let title: String
    let variant: Variant
    let action: (() -> Void)?

    init(_ title: String, variant: Variant = .default, action: (() -> Void)? = nil) {
        self.title = title
        self.variant = variant
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .contentShape(Capsule(style: .continuous))
        } else {
            label
        }
    }

    private var label: some View {
        Text(title)
            .lpText(LP.Typography.monoTiny)
            .foregroundStyle(foreground)
            .padding(.horizontal, LP.Spacing.s3)
            .padding(.vertical, Self.verticalPadding)
            .background(Capsule(style: .continuous).fill(background))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(stroke, lineWidth: LP.BorderWidth.regular)
            )
    }

    private var foreground: Color {
        switch variant {
        case .default: return LP.Colors.ink
        case .coral:   return .white
        case .sage:    return .white
        case .ghost:   return LP.Colors.muted
        }
    }

    private var background: Color {
        switch variant {
        case .default: return LP.Colors.paperCard
        case .coral:   return LP.Colors.coral
        case .sage:    return LP.Colors.sage
        case .ghost:   return .clear
        }
    }

    private var stroke: Color {
        switch variant {
        case .default, .ghost: return LP.Colors.ink
        case .coral:           return LP.Colors.coral
        case .sage:            return LP.Colors.sage
        }
    }
}

// MARK: - Previews

#Preview("Variants") {
    HStack(spacing: LP.Spacing.s2) {
        LPPill("DEFAULT")
        LPPill("P0",   variant: .coral)
        LPPill("V1.0", variant: .sage)
        LPPill("V1.1", variant: .ghost)
    }
    .padding(LP.Spacing.s5)
    .lpPaper(.app)
}

#Preview("Tappable (filter chip)") {
    LPPill("22–32 Y/O", variant: .coral, action: {})
        .padding(LP.Spacing.s5)
        .lpPaper(.app)
}

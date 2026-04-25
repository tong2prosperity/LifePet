import SwiftUI

/// Pet-speaks bubble. Handwritten text, 14-14-14-2 corner radii (the sharp
/// corner is bottom-leading to point back toward the pet).
///
/// Use `.calm` for normal dialogue (paper fill, ink border). Use `.urgent`
/// when the pet is hurt/stressed — coral fill + coral text. `lpShadow` is a
/// no-op on watchOS, so the shape renders flat there without branching here.
struct LPSpeechBubble: View {
    enum Tone { case calm, urgent }

    let text: String
    let tone: Tone

    init(_ text: String, tone: Tone = .calm) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .lpText(LP.Typography.handSmall)
            .foregroundStyle(foreground)
            .padding(.horizontal, LP.Spacing.s3)
            .padding(.vertical, LP.Spacing.s2)
            .background(shape.fill(background))
            .overlay(shape.strokeBorder(stroke, lineWidth: LP.BorderWidth.regular))
            .lpShadow(LP.Shadow.sm)
            .accessibilityAddTraits(.isStaticText)
    }

    private var shape: some InsettableShape {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 14,
                bottomLeading: 2,
                bottomTrailing: 14,
                topTrailing: 14
            ),
            style: .continuous
        )
    }

    private var foreground: Color { tone == .urgent ? LP.Colors.coral : LP.Colors.ink2 }
    private var background: Color { tone == .urgent ? LP.Colors.coralSoft : LP.Colors.paperCard }
    private var stroke:     Color { tone == .urgent ? LP.Colors.coral : LP.Colors.ink }
}

// MARK: - Previews

#Preview("Tones") {
    VStack(alignment: .leading, spacing: LP.Spacing.s4) {
        LPSpeechBubble("今天能陪我出去走走吗？")
        LPSpeechBubble("我有点不舒服……", tone: .urgent)
    }
    .padding(LP.Spacing.s5)
    .lpPaper(.app)
}

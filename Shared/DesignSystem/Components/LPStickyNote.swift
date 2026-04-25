import SwiftUI

/// Yellow sticky note — the pet's handwritten aside, or a designer's note.
///
/// iOS renders it with a small rotation (±0.6°/0.8°) and a soft shadow, the
/// way a real sticky peels on paper. watchOS renders it flat — a rotated
/// rectangle loses corners to the bezel on a 41mm face. (The rotation wrap is
/// a private iOS-only modifier; callers don't branch.)
struct LPStickyNote: View {
    enum Tilt { case left, right, flat }

    let text: String
    let tilt: Tilt
    /// Maximum width. `nil` lets the note grow to fit its container — prefer
    /// this inside a narrow column. Default caps at 360pt on iOS for the
    /// "peeled from a notebook" feel.
    let maxWidth: CGFloat?

    init(_ text: String, tilt: Tilt = .left, maxWidth: CGFloat? = defaultMaxWidth) {
        self.text = text
        self.tilt = tilt
        self.maxWidth = maxWidth
    }

    var body: some View {
        Text(text)
            .lpText(LP.Typography.handSmall)
            .foregroundStyle(LP.Colors.stickyInk)
            .frame(maxWidth: maxWidth ?? .infinity, alignment: .leading)
            .padding(.horizontal, LP.Spacing.s3)
            .padding(.vertical, LP.Spacing.s3)
            .background(LP.Colors.sticky)
            .lpShadow(LP.Shadow.sm)
            .modifier(LPStickyTilt(tilt: tilt))
    }

    /// Default max width: 360pt on iOS, unconstrained on watchOS.
    private static var defaultMaxWidth: CGFloat? {
        #if os(watchOS)
        return nil
        #else
        return 360
        #endif
    }
}

private struct LPStickyTilt: ViewModifier {
    let tilt: LPStickyNote.Tilt

    func body(content: Content) -> some View {
        #if os(iOS)
        content.rotationEffect(angle)
        #else
        content  // flat on watchOS
        #endif
    }

    private var angle: Angle {
        switch tilt {
        case .left:  return .degrees(-0.6)
        case .right: return .degrees( 0.8)
        case .flat:  return .degrees( 0)
        }
    }
}

// MARK: - Previews

#Preview("Tilts") {
    VStack(alignment: .leading, spacing: LP.Spacing.s5) {
        LPStickyNote("它在窗边看了你三次。", tilt: .left)
        LPStickyNote("宠物手写体的话，一条不超过 2 行。", tilt: .right)
        LPStickyNote("Flat — 用在列表里不希望晃动的场景。", tilt: .flat)
    }
    .padding(LP.Spacing.s5)
    .lpPaper(.app)
}

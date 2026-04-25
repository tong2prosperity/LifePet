import SwiftUI

/// Rubber-stamp chip — rotated 3° coral outline with Mono uppercase text.
/// Great for version markers ("V1.0 CANON") or achievement stamps.
///
/// Renders as `EmptyView` on watchOS — the rotation + 2pt border turns into
/// pixel noise on a 41mm face. Safe to place in shared views unconditionally.
struct LPStamp: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        #if os(iOS)
        Text(title)
            .lpText(LP.Typography.monoTiny)
            .foregroundStyle(LP.Colors.coral)
            .padding(.horizontal, LP.Spacing.s3)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.button, style: .continuous)
                    .strokeBorder(LP.Colors.coral, lineWidth: LP.BorderWidth.heavy)
            )
            .rotationEffect(.degrees(-3))
        #else
        EmptyView()
        #endif
    }
}

// MARK: - Previews

#if os(iOS)
#Preview("Stamp") {
    LPStamp("V1.0 CANON")
        .padding(LP.Spacing.s6)
        .lpPaper(.app)
}
#endif

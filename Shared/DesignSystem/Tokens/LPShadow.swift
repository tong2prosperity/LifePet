import SwiftUI

extension LP {
    /// Shadows are *floating hints* — never depth layers, never stacked.
    ///
    /// The tokens are available on every platform, but `View.lpShadow(_:)` is a
    /// **no-op on watchOS**: drop-shadows on the OLED panel wash into halos and
    /// the design leans on 1.5pt lines for separation there. Callers can reference
    /// `LP.Shadow.*` from any target without a `#if` wrapper.
    enum Shadow {
        /// Sticky note / light floating card.
        static let sm = Spec(color: .black.opacity(0.08), radius: 3,  x: 0, y: 2)
        /// Popover / tooltip.
        static let md = Spec(color: .black.opacity(0.10), radius: 6,  x: 0, y: 4)
        /// Modal / sheet / tweaks panel.
        static let lg = Spec(color: .black.opacity(0.12), radius: 12, x: 0, y: 8)

        struct Spec {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }
}

extension View {
    /// Apply an LP shadow. No-op on watchOS — safe to call unconditionally.
    func lpShadow(_ spec: LP.Shadow.Spec) -> some View {
        #if os(iOS)
        shadow(color: spec.color, radius: spec.radius, x: spec.x, y: spec.y)
        #else
        self
        #endif
    }
}

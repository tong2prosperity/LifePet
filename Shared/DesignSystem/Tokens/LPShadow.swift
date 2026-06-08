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

        // — Figma UI Kit ramp (node 57:226 §shadow): shadow-1 … shadow-4 —
        //   Soft ambient elevation for the new card/pop surfaces. ⚠️ Provisional
        //   blur/offset — the Figma effect styles aren't exported yet (selection
        //   tool blocked); tuned to read as gentle floats on the off-white paper.
        static let elevation1 = Spec(color: .black.opacity(0.04), radius: 4,  x: 0, y: 1)
        static let elevation2 = Spec(color: .black.opacity(0.06), radius: 8,  x: 0, y: 2)
        static let elevation3 = Spec(color: .black.opacity(0.08), radius: 16, x: 0, y: 6)
        static let elevation4 = Spec(color: .black.opacity(0.12), radius: 28, x: 0, y: 12)

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

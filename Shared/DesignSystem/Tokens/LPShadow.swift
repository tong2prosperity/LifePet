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
        //   Exact effect styles exported via `get_variable_defs` on 2026-06-10.
        //   Each elevation is **two** stacked drop shadows: a tight ambient
        //   layer (#000 @ ~3% blur 1.8–32) plus a softer key layer that carries
        //   the offset. `lpShadow` applies both. Figma `radius` = blur; we drop
        //   `spread` (always 0). Subtle on the light surfaces by design.
        static let elevation1 = Spec(layers: [
            .init(color: .black.opacity(0.031), radius: 1.8, x: 0, y: 0),
            .init(color: .black.opacity(0.039), radius: 4,   x: 0, y: 0.5),
        ])
        static let elevation2 = Spec(layers: [
            .init(color: .black.opacity(0.031), radius: 3,  x: 0, y: 0),
            .init(color: .black.opacity(0.039), radius: 24, x: 0, y: 2.4),
        ])
        static let elevation3 = Spec(layers: [
            .init(color: .black.opacity(0.031), radius: 3,  x: 0, y: 0),
            .init(color: .black.opacity(0.059), radius: 32, x: 0, y: 6),
        ])
        static let elevation4 = Spec(layers: [
            .init(color: .black.opacity(0.031), radius: 32,  x: 0, y: 4),
            .init(color: .black.opacity(0.078), radius: 100, x: 0, y: 8),
        ])

        /// A shadow spec. May carry multiple stacked drop-shadow `layers`
        /// (the Figma elevation ramp), or a single layer (`sm`/`md`/`lg`).
        struct Spec {
            struct Layer {
                let color: Color
                let radius: CGFloat
                let x: CGFloat
                let y: CGFloat
            }

            let layers: [Layer]

            init(layers: [Layer]) { self.layers = layers }

            /// Single-layer convenience (back-compat with the original API).
            init(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
                self.layers = [Layer(color: color, radius: radius, x: x, y: y)]
            }

            // First-layer accessors so existing `spec.radius` / `.color` reads
            // keep compiling.
            var color: Color  { layers.first?.color  ?? .clear }
            var radius: CGFloat { layers.first?.radius ?? 0 }
            var x: CGFloat { layers.first?.x ?? 0 }
            var y: CGFloat { layers.first?.y ?? 0 }
        }
    }
}

extension View {
    /// Apply an LP shadow (all of its layers). No-op on watchOS — safe to call
    /// unconditionally.
    func lpShadow(_ spec: LP.Shadow.Spec) -> some View {
        #if os(iOS)
        return spec.layers.reduce(AnyView(self)) { view, layer in
            AnyView(view.shadow(color: layer.color, radius: layer.radius, x: layer.x, y: layer.y))
        }
        #else
        return self
        #endif
    }
}

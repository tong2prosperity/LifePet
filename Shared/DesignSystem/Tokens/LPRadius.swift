import CoreGraphics

extension LP {
    /// Corner radius scale. We intentionally skip 12 / 16 / 20 — the gaps
    /// keep the scale legible.
    ///
    /// - `sharp` (0): flush rails, section edges
    /// - `button` (2): buttons, pills, tool controls
    /// - `card` (4): default card / container — the house radius
    /// - `input` (8): text fields
    /// - `panel` (14): large overlays, floating panels
    /// - `pill` (999): capsule pill
    enum Radius {
        static let sharp:  CGFloat = 0
        static let button: CGFloat = 2
        static let card:   CGFloat = 4
        static let input:  CGFloat = 8
        static let panel:  CGFloat = 14
        static let pill:   CGFloat = 999

        // — Figma UI Kit scale (node 57:226 §Radius) —
        //   Named ramp straight off the Figma inspector. `infinite` preserves
        //   Figma's published 300pt value; use `pill`/Capsule for legacy views
        //   that intentionally require an unbounded capsule radius.
        static let xxs:      CGFloat = 2
        static let xs:       CGFloat = 4
        static let s:        CGFloat = 8
        static let m:        CGFloat = 12
        static let l:        CGFloat = 16
        static let xl:       CGFloat = 20
        static let xxl:      CGFloat = 36
        static let xxxl:     CGFloat = 48
        static let infinite: CGFloat = 300
    }
}

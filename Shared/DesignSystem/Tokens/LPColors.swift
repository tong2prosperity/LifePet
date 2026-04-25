import SwiftUI

extension LP {
    /// Palette tokens. Three scales (Ink / Paper / Accent) plus the Sticky pair.
    ///
    /// Semantic rules (do not break):
    /// - **Coral** = the emotion *right now* (pet speaking, current state, P0).
    ///   Do **not** use it to mean "error".
    /// - **Sage** = long-term wellness / social / achievement.
    ///   Do **not** use it to mean "success".
    /// - **Sticky yellow** = a handwritten line from the pet.
    ///
    /// **Light-mode only.** Every token below is a fixed sRGB literal — the
    /// whole aesthetic is "off-white paper", not an adaptive surface. Both app
    /// entry points pin `.preferredColorScheme(.light)` on the root scene so
    /// dark-mode users still see paper. If that ever changes, these literals
    /// need to become asset-catalog colors with dark variants.
    enum Colors {
        // — Ink scale (text · lines · pet outline) —
        static let ink       = Color(hex: 0x1A1A1A)
        static let ink2      = Color(hex: 0x3A3A3A)
        static let muted     = Color(hex: 0x6E665A)
        static let faint     = Color(hex: 0xBBBBBB)
        static let hairline  = Color(hex: 0xE7E3D9)

        // — Paper scale (backgrounds · containers) —
        static let paper      = Color(hex: 0xFAF7EF)  // app background
        static let paperCool  = Color(hex: 0xFAFAF5)  // pet stage, content area
        static let paperCard  = Color(hex: 0xFFFEF9)  // card, clickable container
        static let paperWarm  = Color(hex: 0xF4F0E4)  // quote block, inline code bg
        static let kraft      = Color(hex: 0xE7E3D9)  // secondary block

        // — Accents —
        static let coral      = Color(hex: 0xD14B3D)  // primary accent
        static let coralSoft  = Color(hex: 0xFDF3F1)  // accent card bg (P0)
        static let sage       = Color(hex: 0x3E7A5F)  // secondary accent
        static let sageSoft   = Color(hex: 0xF0F6F2)  // sage card bg (P1)

        // — Sticky —
        static let sticky     = Color(hex: 0xFEF4A8)
        static let stickyInk  = Color(hex: 0x5A4A2A)
    }
}

extension Color {
    /// Build a Color from a 0xRRGGBB literal. Alpha defaults to 1.0.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >>  8) & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

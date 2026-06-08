import SwiftUI

// MARK: - Figma "Pibo UI Kit" semantic token layer
//
// Mirrors the semantic Color tokens in the Figma UI Kit (node 57:226 §Color):
// `fill-*`, `content-*`, `line-separator-*`. These sit *on top of* the older
// `LP.Colors` paper palette — the raw palette stays for existing call sites; new
// UI should prefer these semantic slots so a single re-theme swaps the whole app.
//
// ⚠️ Provisional values. The designer has **not** filled the Figma color
// variables yet (Neutral / Colorful swatches are empty placeholders), so the hex
// below is *derived from the home 三屏 mockups* (node 74:6101) + the existing LP
// palette. When the Figma variables land, select node 57:226 in the desktop app
// and re-export via `get_variable_defs`, then replace the literals here — the
// token *names* are final, only the values are pending.

extension LP {
    /// Background / surface / accent / mask fills. `fill-*` in Figma.
    enum Fill {
        // — bg: stacking surfaces, lightest → most elevated —
        static let bgSurface   = Color(hex: 0xF6F6F2)  // app / page base (off-white)
        static let bgContainer = Color(hex: 0xFFFFFF)  // card, clickable container
        static let bgPop       = Color(hex: 0xFFFFFF)   // popover / elevated (pairs w/ shadow)

        // — foundation: brand accent + status —
        static let foundationAccent   = Color(hex: 0x23B26B)  // Pibo green (sprout / leaf / "?")
        static let foundationOnAccent  = Color(hex: 0xFFFFFF)  // text/icon on accent
        static let foundationError     = Color(hex: 0xE5484D)
        static let foundationSuccess   = Color(hex: 0x23B26B)

        // — mask: scrims behind modals / dimming —
        static let maskModal = Color(hex: 0x000000, alpha: 0.40)  // sheet/modal scrim
        static let maskMuted = Color(hex: 0x000000, alpha: 0.06)  // subtle press/hover
        static let maskDeep  = Color(hex: 0x000000, alpha: 0.60)  // full-cover dim
    }

    /// Foreground content (text · icons). `content-*` in Figma. The `invert*`
    /// ramp is for content sitting on a dark / accent fill.
    enum Content {
        static let primary     = Color(hex: 0x1A1A1A)  // titles, 与Pibo相识的第 N 天
        static let secondary   = Color(hex: 0x6B6B6B)  // greeting (早上好, lulu)
        static let tertiary    = Color(hex: 0x9A9A9A)  // captions / hints
        static let quarternary = Color(hex: 0xC2C2C2)  // disabled / faint
        static let accent      = Color(hex: 0x23B26B)  // links, accent text

        static let invertPrimary     = Color(hex: 0xFFFFFF)
        static let invertSecondary   = Color(hex: 0xFFFFFF, alpha: 0.72)
        static let invertTertiary    = Color(hex: 0xFFFFFF, alpha: 0.48)
        static let invertQuarternary = Color(hex: 0xFFFFFF, alpha: 0.28)
    }

    /// Hairline separators. `line-separator-*` in Figma.
    enum Separator {
        static let primary   = Color(hex: 0xE6E6E1)  // section / list dividers
        static let secondary = Color(hex: 0xF0F0EB)  // in-block, lightest
    }
}

import SwiftUI

// MARK: - Figma "Pibo UI Kit" semantic token layer
//
// The semantic Color tokens from the Figma UI Kit (node 57:226 §Color):
// `fill-*`, `content-*`, `line-separator-*`, `border-*`. These sit *on top of*
// the raw `LP.Neutral` / `LP.Colorful` primitives (`LPPalette.swift`) and the
// older `LP.Colors` paper palette. New UI should prefer these semantic slots so
// a single re-theme swaps the whole app.
//
// Values verified against Figma via `get_variable_defs` on 2026-07-11 — the
// designer has now filled the color variables, so these are the *real* tokens,
// not the earlier mockup-derived guesses. `content-*` / `fill-mask-*` are the
// brand ink (`grey 900` = #171D22) at fixed alphas; `line-*` / `border-*` are
// pure black at low alpha. Two labels still have no distinct published value
// in the source section and are flagged inline: `bgSurfaceSecondary` and
// `Border.secondary`.

extension LP {
    /// Background / surface / accent / mask fills. `fill-*` in Figma.
    enum Fill {
        // — bg: stacking surfaces, base → most elevated —
        static let bgSurface          = LP.Neutral.grey100  // fill-bg-surface-primary — app / page base
        // Figma lists fill-bg-surface-secondary, but its specimen is currently
        // bound to fill-bg-pop and get_variable_defs publishes no distinct var.
        // Preserve the existing grey200 fallback until the source token is bound.
        static let bgSurfaceSecondary = LP.Neutral.grey200
        static let bgContainer        = LP.Neutral.grey25   // fill-bg-container — card / clickable container
        static let bgPop              = LP.Neutral.grey0    // fill-bg-pop — popover / elevated (pairs w/ shadow)

        // — semantic: brand accent + status (Figma fill-semantic-*) —
        static let foundationAccent   = LP.Colorful.green500  // Pibo green (sprout / leaf / "?")
        static let foundationOnAccent = LP.Neutral.grey0      // text/icon on accent
        static let foundationError    = LP.Colorful.red500
        static let foundationWarning  = LP.Colorful.yellow500
        static let foundationSuccess  = LP.Colorful.lime500
        static let foundationInfo     = LP.Colorful.cyan500

        // — mask: scrims behind modals / dimming. Brand ink (grey 900) @ alpha —
        static let maskMuted    = LP.Neutral.grey900.opacity(41.0 / 255.0)   // subtle press/hover (#171D22 @ 0x29)
        static let maskModal    = LP.Neutral.grey900.opacity(102.0 / 255.0)  // sheet/modal scrim (@ 0x66)
        static let maskDeep     = LP.Neutral.grey900.opacity(163.0 / 255.0)  // full-cover dim (@ 0xA3)
        static let maskBlackout = LP.Neutral.grey900.opacity(204.0 / 255.0)  // near-opaque blackout (@ 0xCC)
    }

    /// Foreground content (text · icons). `content-*` in Figma — brand ink
    /// (`grey 900`) at fixed alpha, so it tints subtly cool over any surface.
    /// The `invert*` ramp is white at the same alphas, for content on a dark /
    /// accent fill.
    enum Content {
        static let primary     = LP.Neutral.grey900.opacity(224.0 / 255.0)  // titles, 与Pibo相识的第 N 天 (#171D22 @ 0xE0)
        static let secondary   = LP.Neutral.grey900.opacity(184.0 / 255.0)  // greeting, body (@ 0xB8)
        static let tertiary    = LP.Neutral.grey900.opacity(143.0 / 255.0)  // captions / hints (@ 0x8F)
        static let quarternary = LP.Neutral.grey900.opacity(112.0 / 255.0)  // disabled / faint (@ 0x70)
        static let accent      = LP.Colorful.green500               // links, accent text (#1FA843)

        static let invertPrimary     = Color.white.opacity(224.0 / 255.0)
        static let invertSecondary   = Color.white.opacity(184.0 / 255.0)
        static let invertTertiary    = Color.white.opacity(143.0 / 255.0)
        static let invertQuarternary = Color.white.opacity(112.0 / 255.0)
    }

    /// Hairline separators. `line-separator-*` in Figma — pure black at low
    /// alpha (distinct from masks, which use brand ink).
    enum Separator {
        static let primary   = Color.black.opacity(31.0 / 255.0)  // section / list dividers (#000 @ 0x1F)
        static let secondary = Color.black.opacity(20.0 / 255.0)  // in-block, lightest (@ 0x14)
    }

    /// Stroke / outline colors. `border-*` in Figma — pure black at low alpha.
    /// `primary` matches `Separator.primary`; the ramp steps down to a barely
    /// visible `tertiary` hairline. (Distinct from `LP.BorderWidth`, which is
    /// line *weight*, not color.)
    enum Border {
        static let primary   = Color.black.opacity(31.0 / 255.0)  // border-primary (#000 @ 0x1F)
        static let secondary = Color.black.opacity(20.0 / 255.0)  // border-secondary — inferred (no var); = separator-secondary
        static let tertiary  = Color.black.opacity(10.0 / 255.0)  // border-tertiary (@ 0x0A)
    }
}

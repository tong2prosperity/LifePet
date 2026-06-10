import SwiftUI

// MARK: - Figma "Pibo UI Kit" primitive palette (node 57:226 §Pibo Color)
//
// The raw color *primitives* exported from the Figma UI Kit via
// `get_variable_defs` (2026-06-10) — `neutral/grey *` and `Colorful/<hue> *`.
// These are the bottom layer of the token system: the **semantic** slots in
// `LPTokens.swift` (`LP.Fill` / `LP.Content` / `LP.Separator` / `LP.Border`)
// are composed from these, and *those* are what UI code should reach for.
//
// Reach for a raw `LP.Neutral` / `LP.Colorful` value only when you genuinely
// need a specific swatch the semantic layer doesn't expose (e.g. a chart series
// color, a per-hue chip). For text / surfaces / separators, prefer the semantic
// slots so a single re-theme swaps the whole app.
//
// Note: this neutral ramp is a **cool blue-grey** (base `grey 900` = #171D22),
// not the warm "off-white paper" of the legacy `LP.Colors` palette. The paper
// palette stays for the narrative/legacy components (图鉴 / 一起); the cool
// neutral is the product-UI surface the home / Dashboard now run on.

extension LP {
    /// Neutral grey ramp. `grey0` (white) → `grey900` (near-black ink), with
    /// half-steps (25 / 150 / 250 …) for fine surface separation. Cool-toned.
    enum Neutral {
        static let grey0   = Color(hex: 0xFFFFFF)
        static let grey25  = Color(hex: 0xFBFCFC)
        static let grey50  = Color(hex: 0xF8FAFB)
        static let grey100 = Color(hex: 0xF4F8F9)
        static let grey150 = Color(hex: 0xEFF4F6)
        static let grey200 = Color(hex: 0xE8EEF1)
        static let grey250 = Color(hex: 0xE0E8EC)
        static let grey300 = Color(hex: 0xD7E0E5)
        static let grey350 = Color(hex: 0xCDD7DD)
        static let grey400 = Color(hex: 0xC0CBD3)
        static let grey450 = Color(hex: 0xB1BDC7)
        static let grey500 = Color(hex: 0xA0ADB8)
        static let grey550 = Color(hex: 0x8F9CA8)
        static let grey600 = Color(hex: 0x7A8794)
        static let grey650 = Color(hex: 0x687480)
        static let grey700 = Color(hex: 0x56616C)
        static let grey750 = Color(hex: 0x454F58)
        static let grey800 = Color(hex: 0x343D45)
        static let grey850 = Color(hex: 0x252C33)
        static let grey900 = Color(hex: 0x171D22)
    }

    /// Colorful ramps. Ten hues, each `50` (lightest tint) → `900` (deepest
    /// shade) with `500` as the nominal mid. `green`/`lime` carry the brand
    /// accent + success; `red`/`yellow`/`cyan` back error/warning/info.
    enum Colorful {
        // — red —
        static let red50  = Color(hex: 0xF9F6F6)
        static let red100 = Color(hex: 0xF2E8EA)
        static let red200 = Color(hex: 0xE8CED3)
        static let red300 = Color(hex: 0xDFA5B0)
        static let red400 = Color(hex: 0xDA6C82)
        static let red500 = Color(hex: 0xE03A5A)
        static let red600 = Color(hex: 0x971C33)
        static let red700 = Color(hex: 0x6F1A2B)
        static let red800 = Color(hex: 0x4F1722)
        static let red900 = Color(hex: 0x311118)

        // — orange —
        static let orange50  = Color(hex: 0xF9F6F5)
        static let orange100 = Color(hex: 0xF3EAE7)
        static let orange200 = Color(hex: 0xEBD3CC)
        static let orange300 = Color(hex: 0xE4AFA0)
        static let orange400 = Color(hex: 0xE38063)
        static let orange500 = Color(hex: 0xF06A43)
        static let orange600 = Color(hex: 0xA23211)
        static let orange700 = Color(hex: 0x772913)
        static let orange800 = Color(hex: 0x542211)
        static let orange900 = Color(hex: 0x34170F)

        // — yellow —
        static let yellow50  = Color(hex: 0xF9F8F5)
        static let yellow100 = Color(hex: 0xF3F0E7)
        static let yellow200 = Color(hex: 0xEAE2CC)
        static let yellow300 = Color(hex: 0xE3D0A0)
        static let yellow400 = Color(hex: 0xE2BE64)
        static let yellow500 = Color(hex: 0xEDB733)
        static let yellow600 = Color(hex: 0xA07712)
        static let yellow700 = Color(hex: 0x765914)
        static let yellow800 = Color(hex: 0x534013)
        static let yellow900 = Color(hex: 0x33290F)

        // — green (brand accent) —
        static let green50  = Color(hex: 0xF6F9F7)
        static let green100 = Color(hex: 0xE8F2EB)
        static let green200 = Color(hex: 0xCFE8D5)
        static let green300 = Color(hex: 0xA6DDB5)
        static let green400 = Color(hex: 0x6FD78B)
        static let green500 = Color(hex: 0x1FA843)
        static let green600 = Color(hex: 0x1F943E)
        static let green700 = Color(hex: 0x1D6D32)
        static let green800 = Color(hex: 0x194D27)
        static let green900 = Color(hex: 0x12301A)

        // — lime (success) —
        static let lime50  = Color(hex: 0xF7F8F6)
        static let lime100 = Color(hex: 0xEBF0EA)
        static let lime200 = Color(hex: 0xD5E4D3)
        static let lime300 = Color(hex: 0xB4D5AF)
        static let lime400 = Color(hex: 0x8AC77F)
        static let lime500 = Color(hex: 0x58BE47)
        static let lime600 = Color(hex: 0x3C8231)
        static let lime700 = Color(hex: 0x316129)
        static let lime800 = Color(hex: 0x264521)
        static let lime900 = Color(hex: 0x1A2B17)

        // — teal —
        static let teal50  = Color(hex: 0xF6F9F8)
        static let teal100 = Color(hex: 0xE9F2F0)
        static let teal200 = Color(hex: 0xCFE7E2)
        static let teal300 = Color(hex: 0xA7DDD1)
        static let teal400 = Color(hex: 0x70D6C1)
        static let teal500 = Color(hex: 0x22B394)
        static let teal600 = Color(hex: 0x20937A)
        static let teal700 = Color(hex: 0x1D6D5C)
        static let teal800 = Color(hex: 0x194D42)
        static let teal900 = Color(hex: 0x12302A)

        // — blue —
        static let blue50  = Color(hex: 0xF6F7F9)
        static let blue100 = Color(hex: 0xE8EDF2)
        static let blue200 = Color(hex: 0xCFDAE8)
        static let blue300 = Color(hex: 0xA5C0DE)
        static let blue400 = Color(hex: 0x6D9FD9)
        static let blue500 = Color(hex: 0x438CE0)
        static let blue600 = Color(hex: 0x1C5596)
        static let blue700 = Color(hex: 0x1B426F)
        static let blue800 = Color(hex: 0x18314E)
        static let blue900 = Color(hex: 0x122031)

        // — cyan (info) —
        static let cyan50  = Color(hex: 0xF6F8F9)
        static let cyan100 = Color(hex: 0xE9F1F2)
        static let cyan200 = Color(hex: 0xCFE4E8)
        static let cyan300 = Color(hex: 0xA7D6DD)
        static let cyan400 = Color(hex: 0x70C9D7)
        static let cyan500 = Color(hex: 0x25AFC5)
        static let cyan600 = Color(hex: 0x1F8393)
        static let cyan700 = Color(hex: 0x1D626D)
        static let cyan800 = Color(hex: 0x19464D)
        static let cyan900 = Color(hex: 0x122C30)

        // — purple —
        static let purple50  = Color(hex: 0xF6F6F9)
        static let purple100 = Color(hex: 0xEAE9F2)
        static let purple200 = Color(hex: 0xD2D0E7)
        static let purple300 = Color(hex: 0xADA8DB)
        static let purple400 = Color(hex: 0x9B8BE7)
        static let purple500 = Color(hex: 0x7A6FE0)
        static let purple600 = Color(hex: 0x6251B8)
        static let purple700 = Color(hex: 0x483B91)
        static let purple800 = Color(hex: 0x31286A)
        static let purple900 = Color(hex: 0x1F1A42)

        // — pink —
        static let pink50  = Color(hex: 0xF9F6F8)
        static let pink100 = Color(hex: 0xF1EAEE)
        static let pink200 = Color(hex: 0xE5D2DF)
        static let pink300 = Color(hex: 0xD7ADCA)
        static let pink400 = Color(hex: 0xCB7BB2)
        static let pink500 = Color(hex: 0xC84AA0)
        static let pink600 = Color(hex: 0x872C6A)
        static let pink700 = Color(hex: 0x642650)
        static let pink800 = Color(hex: 0x471F3A)
        static let pink900 = Color(hex: 0x2D1625)
    }
}

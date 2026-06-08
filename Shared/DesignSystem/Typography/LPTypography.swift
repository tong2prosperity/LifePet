import SwiftUI

extension LP {
    /// Typography. Four faces with strict jobs:
    ///
    /// - **Serif** (Fraunces → `.serif`): titles, hero statements, narrative body.
    /// - **Hand** (Kalam / Caveat → `.rounded`): pet speech, sticky notes, user notes.
    ///   NOTE: `.rounded` is **SF Rounded**, a geometric sans — it does **not** read
    ///   as handwritten. Bundle the real Kalam/Caveat font for the demo and wire it
    ///   through `customFaceName(for:weight:)` below, otherwise "hand" surfaces will
    ///   look like rounded UI chrome.
    /// - **Mono** (`.monospaced`): labels, data values, timestamps, IDs.
    /// - **Sans** (`.default`): everything else.
    ///
    /// Sizes auto-scale per platform in `scaled(_:)` — watchOS compresses large
    /// display sizes more than small labels, and floors tiny labels at 9pt so mono
    /// timestamps stay readable at 41mm. See `LPSpacing` for the matching layout
    /// scale.
    enum Typography {
        // — Display / title scale (Serif) —
        static let display   = style(.serif, weight: .bold,     size: 56, tracking: -1.2, line: 1.02)
        static let h1        = style(.serif, weight: .bold,     size: 40, tracking: -0.8, line: 1.05)
        static let h2        = style(.serif, weight: .semibold, size: 28, tracking: -0.4, line: 1.10)
        static let h3        = style(.serif, weight: .semibold, size: 19, tracking:  0.0, line: 1.25)
        static let serifBody = style(.serif, weight: .regular,  size: 19, tracking:  0.0, line: 1.45)
        static let lede      = style(.serif, weight: .regular,  size: 20, tracking:  0.0, line: 1.45)
        static let serifItalic = style(.serif, weight: .regular, size: 17, tracking: 0, line: 1.45, italic: true)

        // — Hand (emotional copy) —
        static let handLarge = style(.hand, weight: .regular, size: 32, tracking: 0, line: 1.10)
        static let handMid   = style(.hand, weight: .regular, size: 22, tracking: 0, line: 1.30)
        static let handSmall = style(.hand, weight: .regular, size: 17, tracking: 0, line: 1.35)

        // — Mono (data · labels) —
        static let monoLabel = style(.mono, weight: .medium,  size: 11, tracking: 2.2, line: 1.20, upper: true)
        static let monoBody  = style(.mono, weight: .regular, size: 13, tracking: 0,   line: 1.50)
        static let monoTiny  = style(.mono, weight: .regular, size: 10, tracking: 1.0, line: 1.30, upper: true)

        // — Sans (default) —
        static let body      = style(.sans, weight: .regular,  size: 15, tracking: 0, line: 1.65)
        static let bodyBold  = style(.sans, weight: .semibold, size: 15, tracking: 0, line: 1.65)
        static let caption   = style(.sans, weight: .regular,  size: 13, tracking: 0, line: 1.45)

        // — Figma UI Kit ramp (node 57:226 §Typography) —
        //   The product-UI sans scale used by the home / Dashboard / cards:
        //   Headline `h1…h5`, body `b1…b4` (medium + regular), caption `c1…c2`.
        //   Distinct from the serif `h1/h2/h3` above (those stay for the LP
        //   narrative aesthetic). ⚠️ Sizes provisional — the Figma text styles
        //   aren't exported yet (selection tool blocked), so this ramp is anchored
        //   to the existing scale + the home 三屏 proportions. Replace with exact
        //   px when the variables export (select 57:226 in desktop).
        static let uiH1 = style(.sans, weight: .bold,     size: 40, tracking: -0.6, line: 1.10)
        static let uiH2 = style(.sans, weight: .bold,     size: 32, tracking: -0.4, line: 1.12)
        static let uiH3 = style(.sans, weight: .semibold, size: 24, tracking: -0.2, line: 1.20)
        static let uiH4 = style(.sans, weight: .semibold, size: 20, tracking:  0.0, line: 1.25)
        static let uiH5 = style(.sans, weight: .semibold, size: 16, tracking:  0.0, line: 1.30)

        static let b1Medium  = style(.sans, weight: .medium,  size: 17, tracking: 0, line: 1.45)
        static let b1Regular = style(.sans, weight: .regular, size: 17, tracking: 0, line: 1.45)
        static let b2Medium  = style(.sans, weight: .medium,  size: 15, tracking: 0, line: 1.50)
        static let b2Regular = style(.sans, weight: .regular, size: 15, tracking: 0, line: 1.50)
        static let b3Medium  = style(.sans, weight: .medium,  size: 14, tracking: 0, line: 1.50)
        static let b3Regular = style(.sans, weight: .regular, size: 14, tracking: 0, line: 1.50)
        static let b4Medium  = style(.sans, weight: .medium,  size: 13, tracking: 0, line: 1.45)
        static let b4Regular = style(.sans, weight: .regular, size: 13, tracking: 0, line: 1.45)

        static let c1Medium  = style(.sans, weight: .medium,  size: 12, tracking: 0.2, line: 1.35)
        static let c1Regular = style(.sans, weight: .regular, size: 12, tracking: 0.2, line: 1.35)
        static let c2Medium  = style(.sans, weight: .medium,  size: 11, tracking: 0.2, line: 1.30)
        static let c2Regular = style(.sans, weight: .regular, size: 11, tracking: 0.2, line: 1.30)
    }

    /// A typography recipe. Prefer applying via `Text("…").lpText(style)` — that
    /// modifier handles font, tracking, case, italic, and line spacing together.
    struct TextStyle {
        let face: Face
        let weight: Font.Weight
        let size: CGFloat
        let tracking: CGFloat
        let lineHeightMultiple: CGFloat
        let isUppercased: Bool
        let isItalic: Bool

        /// Resolved SwiftUI `Font`, including platform size scaling and the bundled
        /// custom face when one is registered.
        var font: Font {
            let scaled = LP.scaled(self)
            let base: Font
            if let name = LP.customFaceName(for: face, weight: weight) {
                base = .custom(name, size: scaled)
            } else {
                base = .system(size: scaled, weight: weight, design: face.systemDesign)
            }
            return isItalic ? base.italic() : base
        }

        /// Gap to feed into SwiftUI's `.lineSpacing(_:)`. SwiftUI's `lineSpacing`
        /// is the *extra* gap between baselines on top of the font's natural line
        /// height — not a total line-height override. We approximate the natural
        /// height per face (see `Face.naturalLineHeightRatio`) and return the
        /// delta needed to hit the CSS-style `lineHeightMultiple`.
        ///
        /// For sizes where the target line is tighter than the font's natural
        /// line (e.g. display/h1/h2 at ≤1.10 on serif ≈1.21), the delta clamps
        /// to 0 — SwiftUI won't compress below the natural leading. That matches
        /// how the same declaration behaves in a browser with overlap clipping
        /// disabled; the title simply renders at natural leading.
        var lineSpacing: CGFloat {
            let scaled = LP.scaled(self)
            let target  = scaled * lineHeightMultiple
            let natural = scaled * face.naturalLineHeightRatio
            return max(0, target - natural)
        }
    }

    enum Face {
        case serif, hand, mono, sans

        var systemDesign: Font.Design {
            switch self {
            case .serif: return .serif
            case .hand:  return .rounded       // see file header re: fallback quality
            case .mono:  return .monospaced
            case .sans:  return .default
            }
        }

        /// Approximate ratio of natural line height to font size for each system
        /// design. Measured from `UIFont.systemFont(ofSize: 17, weight: .regular)`
        /// with matching `UIFontDescriptor.SymbolicTraits` — stable across iOS 17+
        /// and watchOS 10+.
        var naturalLineHeightRatio: CGFloat {
            switch self {
            case .serif: return 1.21
            case .hand:  return 1.17   // .rounded
            case .mono:  return 1.16
            case .sans:  return 1.20
            }
        }
    }

    // MARK: - Internal helpers

    fileprivate static func style(
        _ face: Face,
        weight: Font.Weight,
        size: CGFloat,
        tracking: CGFloat,
        line: CGFloat,
        upper: Bool = false,
        italic: Bool = false
    ) -> TextStyle {
        TextStyle(
            face: face,
            weight: weight,
            size: size,
            tracking: tracking,
            lineHeightMultiple: line,
            isUppercased: upper,
            isItalic: italic
        )
    }

    /// Platform size scaling. watchOS uses a piecewise curve so tiny labels stay
    /// readable while display/h1/h2 compress to fit the 41–49mm face:
    ///
    /// - size ≥ 20pt → ×0.55 (display/h1/h2/lede)
    /// - 14pt ≤ size < 20pt → ×0.80 (body, h3, hand·mid)
    /// - size < 14pt → ×0.95 with a 9pt floor (mono labels, caption)
    fileprivate static func scaled(_ style: TextStyle) -> CGFloat {
        #if os(watchOS)
        let s = style.size
        if s >= 20 { return s * 0.55 }
        if s >= 14 { return s * 0.80 }
        return max(9, s * 0.95)
        #else
        return style.size
        #endif
    }

    /// Map a face + weight to a bundled custom-font PostScript name. Returns
    /// `nil` when the font isn't registered, in which case `TextStyle.font`
    /// falls back to the matching `Font.Design`.
    ///
    /// When you drop real font files into the target (e.g. `Fraunces-SemiBold.ttf`)
    /// and register them via `UIAppFonts`, fill in the switch below.
    fileprivate static func customFaceName(for face: Face, weight: Font.Weight) -> String? {
        // Intentionally empty. Hook up when real fonts are bundled, e.g.:
        // switch (face, weight) {
        // case (.serif, .bold):     return "Fraunces-Bold"
        // case (.serif, .semibold): return "Fraunces-SemiBold"
        // case (.serif, _):         return "Fraunces-Regular"
        // case (.hand,  .bold):     return "Kalam-Bold"
        // case (.hand,  _):         return "Kalam-Regular"
        // default:                  return nil
        // }
        return nil
    }
}

// MARK: - Text / View sugar

extension View {
    /// The single point of entry for applying a design-system text style.
    /// Applies font, tracking, uppercase transform (for labels), and the
    /// correct line spacing in one shot.
    ///
    /// ```swift
    /// Text("SLEEP · LAST NIGHT")
    ///     .lpText(LP.Typography.monoLabel)
    ///     .foregroundStyle(LP.Colors.muted)
    /// ```
    func lpText(_ style: LP.TextStyle) -> some View {
        self
            .font(style.font)
            .tracking(style.tracking)
            .textCase(style.isUppercased ? .uppercase : .none)
            .lineSpacing(style.lineSpacing)
    }
}

// MARK: - Previews

#Preview("Type specimen") {
    ScrollView {
        VStack(alignment: .leading, spacing: LP.Spacing.s4) {
            Text("一只会发光的小生物。").lpText(LP.Typography.display)
            Text("昨晚你睡了 7 小时").lpText(LP.Typography.h2)
            Text("它醒来的时候，第一件事就是看看你有没有起床。")
                .lpText(LP.Typography.serifBody).foregroundStyle(LP.Colors.ink2)
            Text("“我今天特别想出门。”").lpText(LP.Typography.handLarge)
                .foregroundStyle(LP.Colors.coral)
            Text("今天早睡一小时吧。").lpText(LP.Typography.handMid)
            Text("SLEEP · LAST NIGHT").lpText(LP.Typography.monoLabel)
                .foregroundStyle(LP.Colors.muted)
            Text("7h 12m · HRV 62ms · RHR 54").lpText(LP.Typography.monoBody)
                .foregroundStyle(LP.Colors.ink2)
            Text("默认正文，最常见的叙述。line-height 1.65，留白舒展。")
                .lpText(LP.Typography.body)
        }
        .padding(LP.Spacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .lpPaper(.app)
}

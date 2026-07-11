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
        //   The product-UI scale used by the home / Dashboard / cards: headline
        //   `uiH1…uiH5`, body `b1…b4` (medium + regular), caption `c1…c2`.
        //   Distinct from the serif `h1/h2/h3` above (those stay for the LP
        //   narrative aesthetic). Exact size / weight / line values verified
        //   via Figma design context on 2026-07-11 — the source face is
        //   **PingFang SC Medium/Regular** (= `.medium`/`.regular`, weight 500/400);
        //   PingFang SC ships with Apple platforms, so these styles resolve the
        //   Figma face directly instead of substituting SF for Latin glyphs.
        //   H1/H2 use a fixed 100pt line in Figma (≈1.56× / 2.08×); H3–H5 +
        //   b1/b2 use 1.35×, b3/b4 + c1/c2 use 1.5×. Figma headline tracking is
        //   -1%, represented by the point value for each font size below.
        static let uiH1 = style(.piboUI, weight: .medium, size: 64, tracking: -0.64, line: 100.0 / 64.0)
        static let uiH2 = style(.piboUI, weight: .medium, size: 48, tracking: -0.48, line: 100.0 / 48.0)
        static let uiH3 = style(.piboUI, weight: .medium, size: 36, tracking: -0.36, line: 1.35)
        static let uiH4 = style(.piboUI, weight: .medium, size: 28, tracking: -0.28, line: 1.35)
        static let uiH5 = style(.piboUI, weight: .medium, size: 20, tracking: -0.20, line: 1.35)

        static let b1Medium  = style(.piboUI, weight: .medium,  size: 20, tracking: 0, line: 1.35)
        static let b1Regular = style(.piboUI, weight: .regular, size: 20, tracking: 0, line: 1.35)  // code convenience — no Figma var (b1 ships medium only)
        static let b2Medium  = style(.piboUI, weight: .medium,  size: 18, tracking: 0, line: 1.35)
        static let b2Regular = style(.piboUI, weight: .regular, size: 18, tracking: 0, line: 1.35)
        static let b3Medium  = style(.piboUI, weight: .medium,  size: 16, tracking: 0, line: 1.50)
        static let b3Regular = style(.piboUI, weight: .regular, size: 16, tracking: 0, line: 1.50)
        static let b4Medium  = style(.piboUI, weight: .medium,  size: 14, tracking: 0, line: 1.50)
        static let b4Regular = style(.piboUI, weight: .regular, size: 14, tracking: 0, line: 1.50)

        static let c1Medium  = style(.piboUI, weight: .medium,  size: 12, tracking: 0, line: 1.50)
        static let c1Regular = style(.piboUI, weight: .regular, size: 12, tracking: 0, line: 1.50)
        static let c2Medium  = style(.piboUI, weight: .medium,  size: 10, tracking: 0, line: 1.50)
        static let c2Regular = style(.piboUI, weight: .regular, size: 10, tracking: 0, line: 1.50)
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

        var dynamicTypeReference: Font.TextStyle {
            switch size {
            case 28...:
                return .largeTitle
            case 20..<28:
                return .title2
            case 17..<20:
                return .body
            case 14..<17:
                return .callout
            case 12..<14:
                return .footnote
            default:
                return .caption2
            }
        }
    }

    enum Face {
        case serif, hand, mono, sans, piboUI

        var systemDesign: Font.Design {
            switch self {
            case .serif: return .serif
            case .hand:  return .rounded       // see file header re: fallback quality
            case .mono:  return .monospaced
            case .sans, .piboUI: return .default
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
            case .sans, .piboUI: return 1.20
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

    /// Map a face + weight to a bundled or platform font PostScript name.
    /// Returns `nil` when the face uses a SwiftUI system design.
    ///
    /// When you drop real font files into the target (e.g. `Fraunces-SemiBold.ttf`)
    /// and register them via `UIAppFonts`, fill in the switch below.
    fileprivate static func customFaceName(for face: Face, weight: Font.Weight) -> String? {
        if face == .piboUI {
            return weight == .medium ? "PingFangSC-Medium" : "PingFangSC-Regular"
        }

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

private struct LPDynamicTypeScalingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var lpDynamicTypeScalingEnabled: Bool {
        get { self[LPDynamicTypeScalingKey.self] }
        set { self[LPDynamicTypeScalingKey.self] = newValue }
    }
}

private struct LPTextStyleModifier: ViewModifier {
    @Environment(\.lpDynamicTypeScalingEnabled) private var scalesWithDynamicType
    @ScaledMetric private var dynamicSize: CGFloat

    let style: LP.TextStyle

    init(style: LP.TextStyle) {
        self.style = style
        _dynamicSize = ScaledMetric(
            wrappedValue: LP.scaled(style),
            relativeTo: style.dynamicTypeReference
        )
    }

    func body(content: Content) -> some View {
        let size = scalesWithDynamicType ? dynamicSize : LP.scaled(style)
        let targetLineHeight = size * style.lineHeightMultiple
        let naturalLineHeight = size * style.face.naturalLineHeightRatio

        content
            .font(resolvedFont(size: size))
            .tracking(style.tracking)
            .textCase(style.isUppercased ? .uppercase : .none)
            .lineSpacing(max(0, targetLineHeight - naturalLineHeight))
    }

    private func resolvedFont(size: CGFloat) -> Font {
        let base: Font
        if let name = LP.customFaceName(for: style.face, weight: style.weight) {
            base = .custom(name, fixedSize: size)
        } else {
            base = .system(size: size, weight: style.weight, design: style.face.systemDesign)
        }
        return style.isItalic ? base.italic() : base
    }
}

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
        modifier(LPTextStyleModifier(style: style))
    }

    /// Enables Dynamic Type scaling for LP typography inside a bounded feature
    /// surface. The default remains off so existing app screens keep their
    /// current layout until they are audited and opted in.
    func lpDynamicTypeScaling(_ enabled: Bool = true) -> some View {
        environment(\.lpDynamicTypeScalingEnabled, enabled)
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

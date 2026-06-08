import CoreGraphics

extension LP {
    /// Spacing scale in points. Multiples of 4 with intentional jumps
    /// (no 20 / 28 / 40) — the gaps are part of the visual rhythm.
    ///
    /// Raw tokens `s1…s8` are the same on every platform; use them when the
    /// layout needs an exact value (padding on a tiny pill, a 1-off gutter).
    /// **Semantic aliases** (`cardPadding`, `blockGap`, `sectionGap`,
    /// `screenMargin`) are platform-aware: watchOS returns a tightened value
    /// so a 48pt `sectionGap` doesn't eat half the face.
    enum Spacing {
        // — Raw scale (same on both platforms) —
        static let s1: CGFloat = 4    // tight inline gap
        static let s2: CGFloat = 8    // field gap, small component padding
        static let s3: CGFloat = 12   // label-to-value, small card padding
        static let s4: CGFloat = 16   // card padding, paragraph gap
        static let s5: CGFloat = 24   // block gap, screen side margin (iOS)
        static let s6: CGFloat = 32   // large block gap
        static let s7: CGFloat = 48   // chapter / section gap (iOS)
        static let s8: CGFloat = 64   // major section break

        // — Figma UI Kit scale (node 57:226 §Spacing) —
        //   Named t-shirt sizes used by Figma frames; same values as `s1…s8`
        //   above, exposed under the design-system names so new layouts can
        //   read `LP.Spacing.m` / `.l` straight off a Figma inspector.
        static let none:  CGFloat = 0
        static let xs:    CGFloat = 4    // = s1
        static let s:     CGFloat = 8    // = s2
        static let m:     CGFloat = 12   // = s3
        static let l:     CGFloat = 16   // = s4
        static let xl:    CGFloat = 20
        static let xxl:   CGFloat = 24   // = s5
        static let xxl3:  CGFloat = 32   // 3xl  = s6
        static let xxl4:  CGFloat = 36   // 4xl
        static let xxl5:  CGFloat = 40   // 5xl
        static let xxl6:  CGFloat = 48   // 6xl  = s7

        // — Semantic aliases (platform-aware) —
        static var inlineGap:   CGFloat { s1 }
        static var fieldGap:    CGFloat { s2 }
        static var tight:       CGFloat { s3 }
        static var cardPadding: CGFloat { pick(ios: s4, watch: s3) }  // 16 / 12
        static var blockGap:    CGFloat { pick(ios: s5, watch: s4) }  // 24 / 16
        static var sectionGap:  CGFloat { pick(ios: s7, watch: s5) }  // 48 / 24
        static var screenMargin: CGFloat { pick(ios: s5, watch: s2) } // 24 /  8

        private static func pick(ios: CGFloat, watch: CGFloat) -> CGFloat {
            #if os(watchOS)
            return watch
            #else
            return ios
            #endif
        }
    }
}

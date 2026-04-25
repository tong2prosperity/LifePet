import CoreGraphics

extension LP {
    /// Border tokens. The whole system is drawn with one line weight
    /// (1.5pt) in two styles:
    ///
    /// - **Solid** = confirmed, interactive, current state.
    /// - **Dashed** = draft, optional, placeholder, unlocked-later.
    ///
    /// That dashed/solid split is the design's semantic invention — don't
    /// introduce a third line style just to add visual variety.
    enum BorderWidth {
        static let regular: CGFloat = 1.5   // the default line
        static let hair:    CGFloat = 1.0   // in-block dividers
        static let heavy:   CGFloat = 2.0   // stamp border only
    }

    enum DashPattern {
        /// Matches the CSS dashed stroke used on ghost cards and draft chips.
        static let draft: [CGFloat] = [6, 4]
    }
}

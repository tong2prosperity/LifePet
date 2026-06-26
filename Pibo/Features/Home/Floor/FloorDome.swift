import SwiftUI

// MARK: - Domed crown

/// The 二楼 drawer's #E8EEF1 surface shape — a convex-up domed top (apex `rise`
/// above the frame) over a rectangle that fills all the way to the bottom. **One
/// shape, one colour**: the rising drawer reads as a single continuous surface with
/// a domed leading edge, so there's no two-tone band / convex-down lip to surface a
/// floating "lens" mid-drag (the bug where the closing transition didn't match the
/// closed state). The only on-screen edge is the top dome curve + its upward shadow;
/// the flat bottom always sits off-screen below the drawer. Filled by
/// `FloorContainer`'s drawer as the page background, with the content on top.
///
/// Lives in `Features/Home/Floor` (drawer chrome), not in `PiboHistoryView` — the
/// dome is the pull-up's surface, the history page is merely the content that rides
/// on top of it.
struct FloorDome: Shape {
    var rise: CGFloat = 54
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        // Convex-up top: shoulders at minY, apex `rise` above (control = 2·apex − shoulder).
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.midX, y: rect.minY - 2 * rise))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

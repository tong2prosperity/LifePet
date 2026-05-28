import SwiftUI

/// 20×20 pixel pet, rendered with `Canvas` so the rectangles stay crisp at any
/// scale. Mirrors the SVG in `原型-01-主页.html`:
/// - body: ink rectangles
/// - eyes / mouth highlight: paper-cool pixels
/// - mouth core + ear-tip sparkles: coral pixels
///
/// The pet bounces (translateY -6 + scaleY 1.03) on a 1.3s loop. Sparkles are
/// drawn separately by `PetStageView` so the pet's bounding box stays clean.
struct PixelPet: View {
    /// The drawing is authored on a 20-unit grid; the view fills any size.
    private static let grid: CGFloat = 20

    /// Solid black-ink pixels of the body.
    private static let bodyPixels: [(Int, Int, Int, Int)] = [
        (7, 2, 6, 1),       // top of head
        (6, 3, 8, 12),      // body
        (6, 15, 2, 3),      // left foot
        (12, 15, 2, 3),     // right foot
        // ear / antenna left
        (5, 5, 1, 1), (4, 4, 1, 1), (3, 3, 1, 1),
        // ear / antenna right
        (14, 5, 1, 1), (15, 4, 1, 1), (16, 3, 1, 1),
    ]

    /// Eye whites and mouth highlight (paper-cool pixels on the dark body).
    private static let eyePixels: [(Int, Int, Int, Int)] = [
        (8, 7, 1, 1),       // left eye
        (11, 7, 1, 1),      // right eye
    ]

    /// Coral pixels — tongue + ear-tip sparkles.
    private static let accentPixels: [(Int, Int, Int, Int)] = [
        (9, 9, 2, 2),       // open mouth / tongue
        (2, 1, 1, 1),       // ear tip glow L
        (17, 1, 1, 1),      // ear tip glow R
        (1, 5, 1, 1),       // cheek glow L
        (18, 5, 1, 1),      // cheek glow R
    ]

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let unit = min(size.width, size.height) / Self.grid
            for (x, y, w, h) in Self.bodyPixels {
                ctx.fill(rect(x: x, y: y, w: w, h: h, unit: unit), with: .color(LP.Colors.ink))
            }
            for (x, y, w, h) in Self.eyePixels {
                ctx.fill(rect(x: x, y: y, w: w, h: h, unit: unit), with: .color(LP.Colors.paperCool))
            }
            for (x, y, w, h) in Self.accentPixels {
                ctx.fill(rect(x: x, y: y, w: w, h: h, unit: unit), with: .color(LP.Colors.coral))
            }
        }
        .accessibilityHidden(true)
    }

    private func rect(x: Int, y: Int, w: Int, h: Int, unit: CGFloat) -> Path {
        Path(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: CGFloat(w) * unit, height: CGFloat(h) * unit))
    }
}

#Preview {
    PixelPet()
        .frame(width: 160, height: 160)
        .padding(LP.Spacing.s5)
        .lpPaper(.app)
}

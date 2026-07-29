import CoreGraphics
import UIKit

/// Time-of-day lighting for the vector character.
///
/// The forest applies lighting to its sprites through `ForestMaterial.fsh`, but
/// that shader is a **pure per-pixel colour transform** — desaturate toward
/// luminance, darken, tint, lift — with no spatial component at all. For vector
/// content the same maths is better done on the CPU when the profile changes:
/// a fragment shader on shape nodes would force the character through an
/// offscreen pass, and that pass is exactly what costs the antialiasing (see
/// `docs/character-animation-port.md` G0 ②).
///
/// The arithmetic below must stay identical to the shader's, or Pibo will drift
/// out of step with the scene it stands in.
struct PiboCharacterLighting: Equatable {
    var saturation: CGFloat = 1
    var darkness: CGFloat = 0
    var tintRed: CGFloat = 1
    var tintGreen: CGFloat = 1
    var tintBlue: CGFloat = 1
    var tintAmount: CGFloat = 0
    var lift: CGFloat = 0

    static let neutral = PiboCharacterLighting()

    var isNeutral: Bool { self == .neutral }

    func applied(to color: UIColor) -> UIColor {
        guard !isNeutral else { return color }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return color }

        let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
        var r = luminance + (red - luminance) * saturation
        var g = luminance + (green - luminance) * saturation
        var b = luminance + (blue - luminance) * saturation

        let dim = 1 - darkness
        r *= dim; g *= dim; b *= dim

        r += (r * tintRed - r) * tintAmount
        g += (g * tintGreen - g) * tintAmount
        b += (b * tintBlue - b) * tintAmount

        return UIColor(
            red: min(max(r + lift, 0), 1),
            green: min(max(g + lift, 0), 1),
            blue: min(max(b + lift, 0), 1),
            alpha: alpha
        )
    }
}

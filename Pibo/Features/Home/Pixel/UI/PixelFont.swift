import CoreText
import Foundation
import os
import SwiftUI
import UIKit

// Fusion Pixel 12px (OFL-1.1), subset; see `Pibo/Resources/Fonts/README.md`. Only Home
// bubbles, the HUD and the growth sheets use it — body text, settings and health details
// stay in the system font.
//
// Ported from HarmonyPibo `pixel/ui/PixelFont.ets`. HarmonyOS registers the face through
// `UIContext.getFont()`; iOS registers it once with Core Text, which needs no Info.plist
// entry and keeps the file a plain resource.

enum PixelFont {
    /// HarmonyOS aliases the face to `PiboPixel` with `font.registerFont({ familyName })`.
    /// Core Text has no alias, so iOS asks for the name written inside the file. Swapping
    /// the font means updating this string (and HarmonyOS's constant) together.
    static let family = "Fusion Pixel 12px Prop zh-Hans"
    private static let emPx: CGFloat = 12
    private static var registered = false

    static func register() {
        guard !registered else { return }
        registered = true
        guard let url = Bundle.main.url(forResource: "pibo-pixel-12", withExtension: "otf")
            ?? Bundle.main.url(forResource: "pibo-pixel-12", withExtension: "otf", subdirectory: "Fonts")
        else {
            LPLog.day.error("pixel font missing from the bundle")
            return
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown"
            LPLog.day.error("pixel font registration failed: \(message, privacy: .public)")
        }
    }

    /// A size that lands on whole multiples of the font's 12 px grid, so glyph pixels stay
    /// square. `target` is the size the layout would like, in points.
    static func size(_ target: CGFloat) -> CGFloat {
        let scale = UIScreen.main.scale
        let physical = target * scale
        let multiple = max(1, (physical / emPx).rounded())
        return multiple * emPx / scale
    }

    static func font(_ target: CGFloat) -> Font {
        .custom(family, size: size(target))
    }
}

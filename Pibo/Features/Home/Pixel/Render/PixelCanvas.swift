import CoreGraphics
import SwiftUI

/// A static pixel picture (sheet previews, catalog thumbnails, HUD icons). The painter
/// draws into a logical frame once per `revision`; the canvas scales it by a whole number.
struct PixelCanvas: View {
    var logicalWidth: Int = 16
    var logicalHeight: Int = 16
    var mood: PixelMood = .day
    /// A picture with its own inks (the footprints' night strip); otherwise the mood's
    /// palette.
    var palette: [UInt8]?
    var revision: Int = 0
    /// Scale in device pixels instead of points, the way ArkUI's canvas does: a portrait
    /// shrunk into a 48 pt chip keeps its whole composition instead of being cropped.
    var fitPhysicalPixels = false
    var painter: (PixelFrame) -> Void

    var body: some View {
        GeometryReader { proxy in
            let unit = pixelUnit(proxy.size)
            let image = PixelImageRenderer.render(logicalWidth: logicalWidth,
                                                  logicalHeight: logicalHeight,
                                                  palette: palette ?? PixelPalette.rgb(mood),
                                                  paint: painter)
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: CGFloat(logicalWidth) * unit,
                               height: CGFloat(logicalHeight) * unit)
                } else {
                    Color.clear
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }

    /// Points per logical pixel.
    private func pixelUnit(_ size: CGSize) -> CGFloat {
        guard logicalWidth > 0, logicalHeight > 0 else { return 1 }
        if fitPhysicalPixels {
            let display = UIScreen.main.scale
            let scale = max(1, min(Int(size.width * display) / logicalWidth,
                                    Int(size.height * display) / logicalHeight))
            return CGFloat(scale) / display
        }
        let scale = max(1, min(Int(size.width) / logicalWidth, Int(size.height) / logicalHeight))
        return CGFloat(scale)
    }
}

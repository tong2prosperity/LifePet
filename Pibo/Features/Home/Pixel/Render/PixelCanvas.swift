import CoreGraphics
import SwiftUI

/// Turns a palette-indexed `PixelFrame` into a `CGImage` at its logical size. Scaling is
/// done by the view with nearest-neighbour sampling, so the picture stays crisp.
///
/// Ported from HarmonyPibo `pixel/ui/PixelCanvas.ets`; the ArkTS side writes straight into
/// an `ImageData`, iOS builds a bitmap context of the same size.
final class PixelImageRenderer {
    private var buffer: [UInt8] = []
    private var context: CGContext?
    private var size: (width: Int, height: Int) = (0, 0)
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    func image(for frame: PixelFrame, palette: [UInt8]) -> CGImage? {
        if context == nil || size.width != frame.width || size.height != frame.height {
            size = (frame.width, frame.height)
            buffer = [UInt8](repeating: 0, count: frame.width * frame.height * 4)
            context = CGContext(data: nil, width: frame.width, height: frame.height,
                                bitsPerComponent: 8, bytesPerRow: frame.width * 4,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let context, let data = context.data else { return nil }
        frame.writeRGBA(palette, into: &buffer)
        data.copyMemory(from: buffer, byteCount: buffer.count)
        return context.makeImage()
    }

    /// A picture drawn once, for thumbnails and sheet previews.
    static func render(logicalWidth: Int, logicalHeight: Int, palette: [UInt8],
                       paint: (PixelFrame) -> Void) -> CGImage? {
        let frame = PixelFrame(logicalWidth, logicalHeight)
        paint(frame)
        return PixelImageRenderer().image(for: frame, palette: palette)
    }
}

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
    var painter: (PixelFrame) -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = max(1, min(Int(proxy.size.width) / max(1, logicalWidth),
                                   Int(proxy.size.height) / max(1, logicalHeight)))
            let image = PixelImageRenderer.render(logicalWidth: logicalWidth,
                                                  logicalHeight: logicalHeight,
                                                  palette: palette ?? PixelPalette.rgb(mood),
                                                  paint: painter)
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: CGFloat(logicalWidth * scale),
                               height: CGFloat(logicalHeight * scale))
                } else {
                    Color.clear
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

import CoreGraphics
import Foundation

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

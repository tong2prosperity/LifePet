import CoreGraphics
import UIKit

/// Decision 048: common objects answer taps only on their painted pixels, so a
/// PNG's transparent corners (the hammock's frame, the observer's padding)
/// never steal taps from Pibo or the forest. Masks are downsampled once per
/// image and cached.
final class ForestAlphaHitMask {
    private let width: Int
    private let height: Int
    private let alpha: [UInt8]

    private static var cache: [String: ForestAlphaHitMask] = [:]

    static func mask(named name: String) -> ForestAlphaHitMask? {
        if let cached = cache[name] { return cached }
        guard let image = UIImage(named: name)?.cgImage else { return nil }
        let mask = ForestAlphaHitMask(image: image, maxDimension: 128)
        cache[name] = mask
        return mask
    }

    init(image: CGImage, maxDimension: Int) {
        let scale = min(1, CGFloat(maxDimension) / CGFloat(max(image.width, image.height)))
        let w = max(1, Int(CGFloat(image.width) * scale))
        let h = max(1, Int(CGFloat(image.height) * scale))
        width = w
        height = h
        var buffer = [UInt8](repeating: 0, count: w * h)
        buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        alpha = buffer
    }

    /// `unitPoint` is (0,0) bottom-left … (1,1) top-right, as in SpriteKit.
    /// A small search radius keeps thin painted edges comfortably tappable.
    func contains(unitPoint: CGPoint, threshold: UInt8 = 24, radius: Int = 2) -> Bool {
        guard (0...1).contains(unitPoint.x), (0...1).contains(unitPoint.y) else { return false }
        let cx = min(width - 1, Int(unitPoint.x * CGFloat(width)))
        // Bitmap rows run top-down in memory for this context.
        let cy = min(height - 1, Int((1 - unitPoint.y) * CGFloat(height)))
        for y in max(0, cy - radius)...min(height - 1, cy + radius) {
            for x in max(0, cx - radius)...min(width - 1, cx + radius) where alpha[y * width + x] > threshold {
                return true
            }
        }
        return false
    }
}

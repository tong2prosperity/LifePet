import CoreGraphics
import Foundation
import ImageIO
import os

// Turns a meal's sticker PNG into the few inks the forest mat draws (decision 065).
// Decoding is done once per photo and kept for the run; a missing or unreadable file
// gives "" and the mat draws a bowl instead.
//
// Ported from HarmonyPibo `services/day/MealStickerPixels.ets`.

/// Decoded side before averaging down to the sticker's cells.
nonisolated private let decodeSize = 24

@MainActor
final class MealStickerPixels {
    private var cache: [String: String] = [:]
    private var pending: Set<String> = []

    /// The inks for `id` if decoded already, else nil (and starts decoding).
    func peek(_ id: String, _ pngPath: String = "", data: Data? = nil, onReady: @escaping () -> Void) -> String? {
        if let known = cache[id] { return known }
        if !pending.contains(id) {
            pending.insert(id)
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let inks: String
                if let data, !data.isEmpty {
                    inks = MealStickerPixels.decode(data: data)
                } else {
                    inks = MealStickerPixels.decode(pngPath)
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.cache[id] = inks
                    self.pending.remove(id)
                    onReady()
                }
            }
        }
        return nil
    }

    nonisolated private static func decode(data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            LPLog.day.warning("meal sticker data unreadable")
            return ""
        }
        return renderInks(image)
    }

    nonisolated private static func decode(_ pngPath: String) -> String {
        if pngPath.isEmpty { return "" }
        let url = URL(fileURLWithPath: pngPath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            LPLog.day.warning("meal sticker unreadable")
            return ""
        }
        return renderInks(image)
    }

    nonisolated private static func renderInks(_ image: CGImage) -> String {
        let longest = max(1, max(image.width, image.height))
        let w = max(1, Int((Double(image.width) * Double(decodeSize) / Double(longest)).rounded()))
        let h = max(1, Int((Double(image.height) * Double(decodeSize) / Double(longest)).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: decodeSize, height: decodeSize,
                                      bitsPerComponent: 8, bytesPerRow: decodeSize * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return "" }
        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: decodeSize, height: decodeSize))
        // Centre the photo's shape in a transparent square, so a wide plate stays wide.
        let ox = (decodeSize - w) / 2
        let oy = (decodeSize - h) / 2
        context.draw(image, in: CGRect(x: ox, y: oy, width: w, height: h))
        let bytes = data.bindMemory(to: UInt8.self, capacity: decodeSize * decodeSize * 4)
        let square = [UInt8](UnsafeBufferPointer(start: bytes, count: decodeSize * decodeSize * 4))
        // CGContext's origin is bottom-left; the mat reads top-down.
        var flipped = [UInt8](repeating: 0, count: square.count)
        for y in 0..<decodeSize {
            let from = y * decodeSize * 4
            let to = (decodeSize - 1 - y) * decodeSize * 4
            flipped.replaceSubrange(to..<(to + decodeSize * 4), with: square[from..<(from + decodeSize * 4)])
        }
        return pixelStickerFromRGBA(flipped, decodeSize)
    }
}

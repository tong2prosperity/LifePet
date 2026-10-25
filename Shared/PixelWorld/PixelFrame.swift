import Foundation

/// A logical-resolution canvas of palette indices. Drawing never blends: each pixel holds
/// exactly one ink, which keeps the output inside the palette by construction.
///
/// Ported from HarmonyPibo `pixel/render/PixelFrame.ets`.
final class PixelFrame {
    let width: Int
    let height: Int
    var data: [UInt8]

    init(_ width: Int, _ height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.data = [UInt8](repeating: 0, count: self.width * self.height)
    }

    func clear(_ ink: PixelInk = .clear) {
        data = [UInt8](repeating: ink.rawValue, count: width * height)
    }

    /// Copies a same-sized frame, used to restore cached static layers each tick.
    func copyFrom(_ other: PixelFrame) {
        guard other.width == width, other.height == height else { return }
        data = other.data
    }

    func get(_ x: Double, _ y: Double) -> PixelInk {
        get(Int(x.rounded(.down)), Int(y.rounded(.down)))
    }

    func get(_ x: Int, _ y: Int) -> PixelInk {
        guard x >= 0, y >= 0, x < width, y < height else { return .clear }
        return PixelInk(rawValue: data[y * width + x]) ?? .clear
    }

    func set(_ x: Double, _ y: Double, _ ink: PixelInk) {
        set(Int(x.rounded(.down)), Int(y.rounded(.down)), ink)
    }

    func set(_ x: Int, _ y: Int, _ ink: PixelInk) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let raw = ink.rawValue
        guard raw > 0, raw < PixelInk.count else { return }
        data[y * width + x] = raw
    }

    func fillRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ ink: PixelInk) {
        fillRect(Int(x.rounded(.down)), Int(y.rounded(.down)), Int((x + w).rounded(.down)),
                 Int((y + h).rounded(.down)), ink)
    }

    func fillRect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ ink: PixelInk) {
        let left = max(0, x0)
        let top = max(0, y0)
        let right = min(width, x1)
        let bottom = min(height, y1)
        guard left < right, top < bottom else { return }
        let raw = ink.rawValue
        guard raw > 0, raw < PixelInk.count else { return }
        for py in top..<bottom {
            let row = py * width
            for px in left..<right { data[row + px] = raw }
        }
    }

    /// Ordered dither: `amount` 0 → all `inkA`, 1 → all `inkB`.
    func ditherPixel(_ x: Double, _ y: Double, _ inkA: PixelInk, _ inkB: PixelInk, _ amount: Double) {
        let px = Int(x.rounded(.down))
        let py = Int(y.rounded(.down))
        let threshold = (Double(Self.bayer4[(py & 3) * 4 + (px & 3)]) + 0.5) / 16
        set(px, py, amount > threshold ? inkB : inkA)
    }

    /// Vertical band that dithers from `inkA` at the top to `inkB` at the bottom.
    func ditherBand(_ y: Int, _ h: Int, _ inkA: PixelInk, _ inkB: PixelInk) {
        let rows = max(1, h)
        for row in 0..<rows {
            let amount = rows == 1 ? 1 : Double(row) / Double(rows - 1)
            for px in 0..<width { ditherPixel(Double(px), Double(y + row), inkA, inkB, amount) }
        }
    }

    /// Rows of glyphs (see `PixelPalette.glyphInk`). `flip` mirrors horizontally around the
    /// stamp.
    func stamp(_ rows: [String], _ x: Int, _ y: Int, flip: Bool = false) {
        for (row, line) in rows.enumerated() {
            let inks = Self.inksOf(line)
            for (col, ink) in inks.enumerated() where ink != .clear {
                let dx = flip ? inks.count - 1 - col : col
                set(x + dx, y + row, ink)
            }
        }
    }

    /// Expands palette indices into RGBA bytes; Clear stays fully transparent.
    func writeRGBA(_ palette: [UInt8], into out: inout [UInt8]) {
        let count = min(data.count, out.count / 4)
        for i in 0..<count {
            let ink = Int(data[i])
            let o = i * 4
            if ink == 0 {
                out[o] = 0
                out[o + 1] = 0
                out[o + 2] = 0
                out[o + 3] = 0
                continue
            }
            out[o] = palette[ink * 3]
            out[o + 1] = palette[ink * 3 + 1]
            out[o + 2] = palette[ink * 3 + 2]
            out[o + 3] = 255
        }
    }

    /// Same result as `writeRGBA` in one pass per pixel, for callers that keep a buffer.
    func writeRGBA(_ palette: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        writeRGBA(palette, into: &out)
        return out
    }

    /// Rebuilds `areas` from the whole frame, after a full write.
    func noteCycled(_ areas: PixelCycleAreas) {
        areas.clear()
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                let ink = Int(data[row + x])
                if ink >= PixelInk.cycleFirst { areas.note(PixelPalette.cycleFamily(ink), x, y) }
            }
        }
    }

    private static let bayer4: [Int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

    private static var rowInks: [String: [PixelInk]] = [:]
    private static let rowInksLimit = 4096

    private static func inksOf(_ line: String) -> [PixelInk] {
        if let cached = rowInks[line] { return cached }
        let inks = line.map { PixelPalette.glyphInk($0) }
        if rowInks.count >= rowInksLimit { rowInks.removeAll(keepingCapacity: true) }
        rowInks[line] = inks
        return inks
    }
}

/// Where each cycling family was last written on the image, as [left, top, right, bottom)
/// per family (empty when right <= left). A beat then recolours only the families that
/// stepped, inside their own boxes, instead of scanning the frame.
final class PixelCycleAreas {
    var boxes = [Int](repeating: 0, count: PixelPalette.cycleFamilies * 4)

    func clear() {
        for i in boxes.indices { boxes[i] = 0 }
    }

    func isEmpty(_ family: Int) -> Bool {
        let b = family * 4
        return boxes[b + 2] <= boxes[b]
    }

    func note(_ family: Int, _ x: Int, _ y: Int) {
        guard family >= 0, family < PixelPalette.cycleFamilies else { return }
        let b = family * 4
        if boxes[b + 2] <= boxes[b] {
            boxes[b] = x
            boxes[b + 1] = y
            boxes[b + 2] = x + 1
            boxes[b + 3] = y + 1
            return
        }
        if x < boxes[b] { boxes[b] = x }
        if y < boxes[b + 1] { boxes[b + 1] = y }
        if x + 1 > boxes[b + 2] { boxes[b + 2] = x + 1 }
        if y + 1 > boxes[b + 3] { boxes[b + 3] = y + 1 }
    }

    /// Bit per family with any pixels on the image.
    func visible() -> Int {
        var mask = 0
        for f in 0..<PixelPalette.cycleFamilies where !isEmpty(f) { mask |= 1 << f }
        return mask
    }
}

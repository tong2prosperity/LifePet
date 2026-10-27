import Foundation

// A meal's food sticker as a few pixels (decision 065): the photo's cut-out averaged down
// to a tiny square and each cell snapped to the nearest ink, so the mat in the forest
// stays inside the palette. Transparent cells stay Clear and keep the cut-out's shape.
//
// Ported from HarmonyPibo `pixel/render/PixelSticker.ets`.

// Inks a plate of food can land on: warm browns, reds, greens, creams, a few greys.
nonisolated private let FOOD_INKS: [PixelInk] = [
    .scarf, .scarfShade, .berry, .blush, .flowerB, .fire, .fireCore, .flowerA, .boMid, .acorn, .acornCap,
    .woodLight, .woodMid, .woodDark, .autumnLeaf, .autumnDeep, .autumnLight, .leafLight, .leafMid, .leafDark,
    .grassTip, .moss, .cloth, .clothShade, .signFace, .bodyLight, .stoneLight, .stone, .stoneDark, .line,
    .water, .waterLight,
]

/// `rgba` is `size`×`size` pixels, straight alpha. Returns `PIXEL_STICKER_CELLS²` inks as a
/// string, one char per cell (ink + 48), row by row.
nonisolated func pixelStickerFromRGBA(_ rgba: [UInt8], _ size: Int) -> String {
    let day = PixelPalette.rgb(.day)
    let cells = PIXEL_STICKER_CELLS
    let block = Double(size) / Double(cells)
    var out = ""
    for cy in 0..<cells {
        for cx in 0..<cells {
            var r = 0.0
            var g = 0.0
            var b = 0.0
            var a = 0.0
            var n = 0
            let yFrom = Int((Double(cy) * block).rounded(.down))
            let yTo = Int((Double(cy + 1) * block).rounded(.down))
            let xFrom = Int((Double(cx) * block).rounded(.down))
            let xTo = Int((Double(cx + 1) * block).rounded(.down))
            for y in yFrom..<max(yFrom, yTo) {
                for x in xFrom..<max(xFrom, xTo) {
                    let i = (y * size + x) * 4
                    guard i + 3 < rgba.count else { continue }
                    let alpha = Double(rgba[i + 3])
                    r += Double(rgba[i]) * alpha
                    g += Double(rgba[i + 1]) * alpha
                    b += Double(rgba[i + 2]) * alpha
                    a += alpha
                    n += 1
                }
            }
            if n == 0 || a / Double(n) < 110 {
                out.append(Character(UnicodeScalar(48 + Int(PixelInk.clear.rawValue))!))
                continue
            }
            let ink = nearestInk(day, r / a, g / a, b / a)
            out.append(Character(UnicodeScalar(48 + Int(ink))!))
        }
    }
    return out
}

nonisolated private func nearestInk(_ rgb: [UInt8], _ r: Double, _ g: Double, _ b: Double) -> UInt8 {
    var best = PixelInk.cloth.rawValue
    var bestD = Double.greatestFiniteMagnitude
    for ink in FOOD_INKS {
        let index = Int(ink.rawValue) * 3
        guard index + 2 < rgb.count else { continue }
        // Weighted towards green the way eyes are, so greens and browns do not swap.
        let dr = Double(rgb[index]) - r
        let dg = Double(rgb[index + 1]) - g
        let db = Double(rgb[index + 2]) - b
        let d = dr * dr * 0.3 + dg * dg * 0.59 + db * db * 0.11
        if d < bestD {
            bestD = d
            best = ink.rawValue
        }
    }
    return best
}

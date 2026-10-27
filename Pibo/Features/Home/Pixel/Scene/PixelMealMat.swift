import Foundation
import PiboCore

// The picnic mat at the clearing's edge (decision 065). Core says how many of today's food
// stickers it holds; this draws the checked cloth and each sticker standing on it, newest
// on the left, as its own few pixels inside a white rim.
//
// Ported from HarmonyPibo `pixel/scene/PixelMealMat.ets`.

// The two sticker helpers below live in ArkTS `pixel/render/PixelSticker.ets`; the mat is
// the only reader here, so they are kept beside it until that file is ported.

/// Cells a side; the mat draws a white rim and an outline round it.
nonisolated let PIXEL_STICKER_CELLS: Int = 6

/// The ink in cell (x, y) of an encoded sticker, Clear outside it. Cells are one character
/// each: the ink's raw value plus 48, row by row.
func pixelStickerInk(_ inks: String, _ x: Int, _ y: Int) -> PixelInk {
    let cells = PIXEL_STICKER_CELLS
    if x < 0 || y < 0 || x >= cells || y >= cells { return .clear }
    let scalars = Array(inks.unicodeScalars)
    let index = y * cells + x
    if index >= scalars.count { return .clear }
    let code = Int(scalars[index].value) - 48
    return code < 0 ? .clear : (PixelInk(rawValue: UInt8(clamping: code)) ?? .clear)
}

/// A sticker's footprint: its cells, the white rim and the outline round both.
private let STICKER_SIZE: Int = PIXEL_STICKER_CELLS + 4
private let STICKER_GAP: Int = 11
// A bowl, for a meal saved without a cut-out (or one that could not be read).
private let BOWL: [String] = ["......", ".f.F..", "hhhhhh", "hhhhhh", ".hhhh.", "..HH.."]

private func bowlInk(_ x: Int, _ y: Int) -> PixelInk {
    guard BOWL.indices.contains(y) else { return .clear }
    let row = Array(BOWL[y])
    guard row.indices.contains(x) else { return .clear }
    switch row[x] {
    case "f": return .flowerA
    case "F": return .berry
    case "h": return .cloth
    case "H": return .clothShade
    default: return .clear
    }
}

private func cellInk(_ inks: String, _ x: Int, _ y: Int) -> PixelInk {
    inks.count == PIXEL_STICKER_CELLS * PIXEL_STICKER_CELLS ? pixelStickerInk(inks, x, y) : bowlInk(x, y)
}

/// Where sticker `index` stands: its top-left.
private func stickerOrigin(_ mat: PixelPlaceBox, _ index: Int) -> [Int] {
    [mat.x + 2 + index * STICKER_GAP, mat.y]
}

private func drawSticker(_ frame: PixelFrame, _ inks: String, _ x: Int, _ y: Int) {
    let cells = PIXEL_STICKER_CELLS
    func filled(_ cx: Int, _ cy: Int) -> Bool {
        cellInk(inks, cx, cy) != .clear
    }
    func near(_ cx: Int, _ cy: Int, _ reach: Int) -> Bool {
        for dy in (-reach)...reach {
            for dx in (-reach)...reach {
                if abs(dx) + abs(dy) <= reach && filled(cx + dx, cy + dy) { return true }
            }
        }
        return false
    }
    PixelArt.drawShadow(frame, cx: Double(x) + Double(STICKER_SIZE) / 2,
                        y: Double(y + STICKER_SIZE + 1), halfW: 4)
    let top = y
    // Cells sit two in from the corner: a white rim one cell out, an outline one further.
    for cy in (-2)..<(cells + 2) {
        for cx in (-2)..<(cells + 2) {
            var ink: PixelInk = .clear
            if filled(cx, cy) { ink = cellInk(inks, cx, cy) }
            else if near(cx, cy, 1) { ink = .bodyLight }
            else if near(cx, cy, 2) { ink = .line }
            if ink != .clear { frame.set(x + 2 + cx, top + 2 + cy, ink) }
        }
    }
}

/// The cloth and today's stickers, newest first; `fresh` lets the newest wink now and
/// then while Pibo has not sniffed it yet.
func drawPixelMealMat(_ frame: PixelFrame, _ layout: PixelForestLayout, _ stickers: [String],
                      _ fresh: Bool, _ timeMs: Double) {
    let mat = pixelMealMatBox(layout)
    let clothTop = mat.y + 8
    // A checked cloth seen at a slant: each row a little wider than the one behind it.
    for row in 0..<5 {
        let inset = 4 - row
        for col in inset..<(mat.w - inset) {
            let check = ((col - inset) / 3 + row) % 2 == 0
            var ink: PixelInk = check ? .scarf : .cloth
            if row == 4 { ink = check ? .scarfShade : .clothShade }
            frame.set(mat.x + col, clothTop + row, ink)
        }
    }
    // Fringe at the front edge.
    var col = 1
    while col < mat.w - 1 {
        frame.set(mat.x + col, clothTop + 5, .clothShade)
        col += 2
    }
    for (index, inks) in stickers.enumerated() {
        let at = stickerOrigin(mat, index)
        drawSticker(frame, inks, at[0], at[1])
        // The newest still-new sticker winks a glint in its corner.
        if fresh && index == 0 && PixelMath.floor(timeMs / 600) % 5 == 0 {
            frame.set(at[0] + STICKER_SIZE - 2, at[1] + 1, .glow)
        }
    }
}

/// Tap targets for the stickers on the mat (PixelHotspot.MealSticker + index).
func pixelMealStickerBoxes(_ layout: PixelForestLayout, _ count: Int) -> [PixelPlaceBox] {
    let mat = pixelMealMatBox(layout)
    var boxes: [PixelPlaceBox] = []
    for i in 0..<count {
        let at = stickerOrigin(mat, i)
        var box = PixelPlaceBox()
        box.place = PixelHotspot.mealSticker.rawValue + i
        box.x = at[0]
        box.y = at[1]
        box.w = STICKER_SIZE
        box.h = STICKER_SIZE
        boxes.append(box)
    }
    return boxes
}

/// The mat's bottom, for drawing it behind or in front of Pibo.
func pixelMealMatBottom(_ layout: PixelForestLayout) -> Int {
    let mat = pixelMealMatBox(layout)
    return mat.y + mat.h
}

import Foundation

// Shared finishing tools for the pixel world (decision 058 polish): every object is drawn
// like a sticker — its own colours inside one soft dark outline — and stands on a soft
// shadow, so props read as one set instead of loose icons on the grass.
//
// Ported from HarmonyPibo `pixel/render/PixelArt.ets`.

enum PixelArt {
    private static var scratchFrames: [Int: PixelFrame] = [:]

    private static func scratch(_ w: Int, _ h: Int) -> PixelFrame {
        let key = w * 4096 + h
        if let frame = scratchFrames[key] {
            frame.clear(.clear)
            return frame
        }
        let frame = PixelFrame(w, h)
        scratchFrames[key] = frame
        return frame
    }

    /// Draws `paint` into a w×h scratch (its own origin at 1,1) and copies it to (x, y)
    /// with a 1px outline around every painted pixel that touches empty space. `outline`
    /// `.clear` skips the outline (used for soft things like smoke).
    static func drawSticker(_ frame: PixelFrame, x: Double, y: Double, w: Double, h: Double,
                            outline: PixelInk = .line, paint: (PixelFrame) -> Void) {
        let sw = max(1, Int(w.rounded(.down)) + 2)
        let sh = max(1, Int(h.rounded(.down)) + 2)
        let art = scratch(sw, sh)
        paint(art)
        let ox = Int(x.rounded()) - 1
        let oy = Int(y.rounded()) - 1
        let data = art.data
        for py in 0..<sh {
            for px in 0..<sw {
                let ink = data[py * sw + px]
                if ink != 0 {
                    frame.set(ox + px, oy + py, PixelInk(rawValue: ink) ?? .clear)
                    continue
                }
                if outline == .clear { continue }
                let touches = (px > 0 && data[py * sw + px - 1] != 0)
                    || (px < sw - 1 && data[py * sw + px + 1] != 0)
                    || (py > 0 && data[(py - 1) * sw + px] != 0)
                    || (py < sh - 1 && data[(py + 1) * sw + px] != 0)
                if touches { frame.set(ox + px, oy + py, outline) }
            }
        }
    }

    /// A soft oval shadow on the ground, centred at cx with its top row at y.
    static func drawShadow(_ frame: PixelFrame, cx: Double, y: Double, halfW: Double) {
        let half = max(1, Int(halfW.rounded()))
        let x = Int(cx.rounded())
        for dx in -half...half {
            let edge = Double(abs(dx)) / Double(half)
            if edge < 0.85 {
                frame.set(x + dx, Int(y), .groundShadow)
            } else {
                frame.ditherPixel(Double(x + dx), y, frame.get(x + dx, Int(y)), .groundShadow, 0.5)
            }
            let below = Int(y) + 1
            if edge < 0.6 {
                frame.set(x + dx, below, .groundShadow)
            } else if edge < 0.8 {
                frame.ditherPixel(Double(x + dx), y + 1, frame.get(x + dx, below), .groundShadow, 0.5)
            }
        }
    }

    /// A deterministic 0..1 hash of a grid cell, for seeded scatter.
    static func hash(_ x: Int, _ y: Int, _ seed: Int) -> Double {
        var h = UInt32(bitPattern: Int32(truncatingIfNeeded: x)) &* 374_761_393
        h = h &+ UInt32(bitPattern: Int32(truncatingIfNeeded: y)) &* 668_265_263
        h = h &+ UInt32(bitPattern: Int32(truncatingIfNeeded: seed)) &* 2_147_483_647
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h = h ^ (h >> 16)
        return Double(h) / 4_294_967_296
    }

    /// A row that blends `inkA` into `inkB` with horizontal brush streaks instead of a
    /// checker: runs of 2–8 pixels, each one ink, picked so `amount` of the row is `inkB`.
    static func drawStreakRow(_ frame: PixelFrame, y: Int, _ inkA: PixelInk, _ inkB: PixelInk,
                              amount: Double, seed: Int) {
        var x = -Int(hash(y, 0, seed) * 6)
        var run = 0
        while x < frame.width {
            let len = 2 + Int(hash(y, run, seed + 1) * 7)
            let ink = hash(y, run, seed + 2) < amount ? inkB : inkA
            for i in 0..<len { frame.set(x + i, y, ink) }
            x += len
            run += 1
        }
    }

    /// Smooth value noise in 0..1 with cells of `cell` pixels; pure and seeded.
    static func noise(_ x: Double, _ y: Double, cell: Double, seed: Int) -> Double {
        let gx = x / cell
        let gy = y / cell
        let x0 = Int(gx.rounded(.down))
        let y0 = Int(gy.rounded(.down))
        let tx = gx - Double(x0)
        let ty = gy - Double(y0)
        let sx = tx * tx * (3 - 2 * tx)
        let sy = ty * ty * (3 - 2 * ty)
        let a = hash(x0, y0, seed)
        let b = hash(x0 + 1, y0, seed)
        let c = hash(x0, y0 + 1, seed)
        let d = hash(x0 + 1, y0 + 1, seed)
        let top = a + (b - a) * sx
        let bottom = c + (d - c) * sx
        return top + (bottom - top) * sy
    }

    /// A blob of foliage: lit from the upper left, a darker underside and a few leaf clumps
    /// breaking the rim so it never reads as a plain disc. `inks` is [dark, mid, light].
    static func drawFoliage(_ frame: PixelFrame, cx: Int, cy: Int, rx: Int, ry: Int,
                            inks: [PixelInk], seed: Int) {
        guard rx > 0, ry > 0, inks.count >= 3 else { return }
        for dy in (-ry - 1)...(ry + 1) {
            for dx in (-rx - 1)...(rx + 1) {
                let nx = Double(dx) / Double(rx)
                let ny = Double(dy) / Double(ry)
                let d = nx * nx + ny * ny
                // Lumpy rim from noise: clumps poke out, notches bite in.
                let rim = 1 + (noise(Double(cx + dx), Double(cy + dy), cell: 3, seed: seed) - 0.5) * 0.55
                if d > rim { continue }
                let lit = (nx + 0.45) * (nx + 0.45) + (ny + 0.55) * (ny + 0.55)
                var ink = inks[1]
                if ny > 0.35 || (ny > 0.05 && nx > 0.45) { ink = inks[0] }
                if lit < 0.42 {
                    frame.set(cx + dx, cy + dy, inks[2])
                } else if lit < 0.66 && ink == inks[1] {
                    frame.ditherPixel(Double(cx + dx), Double(cy + dy), inks[1], inks[2], 0.4)
                } else {
                    frame.set(cx + dx, cy + dy, ink)
                }
            }
        }
        // Leaf flecks: lighter specks in the lit half, dark ones in the shade.
        let flecks = Int((Double(rx * ry) / 6).rounded())
        for i in 0..<max(0, flecks) {
            let fx = Int(hash(i, 1, seed) * Double(rx * 2 - 1)) - rx + 1
            let fy = Int(hash(i, 2, seed) * Double(ry * 2 - 1)) - ry + 1
            if Double(fx * fx) / Double(rx * rx) + Double(fy * fy) / Double(ry * ry) > 0.7 { continue }
            frame.set(cx + fx, cy + fy, fy < 0 ? inks[2] : inks[0])
        }
    }
}

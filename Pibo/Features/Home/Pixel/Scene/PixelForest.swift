import Foundation
import PiboCore

// The forest is generated from a seed and the frame size, so every device draws the same
// world and a wider phone simply sees more of it. Static layers render once per
// (seed, size, mood); only weather and small life are redrawn each frame.
//
// Ported from HarmonyPibo `pixel/scene/PixelForest.ets`.

/// ArkTS number helpers the port needs to stay pixel-identical: `Math.round` sends halves
/// up (Swift's `.rounded()` sends them away from zero), and inks are plain numbers there,
/// so art adds to them.
enum PixelMath {
    static func round(_ value: Double) -> Int {
        Int((value + 0.5).rounded(.down))
    }

    static func floor(_ value: Double) -> Int {
        Int(value.rounded(.down))
    }

    /// The ink `offset` steps after `ink` in the palette (`PixelInk.StarA + i % 3`).
    static func ink(_ ink: PixelInk, _ offset: Int) -> PixelInk {
        PixelInk(rawValue: UInt8(clamping: ink.index + offset)) ?? ink
    }
}

struct PixelForestLayout: Equatable {
    var width: Int = 0
    var height: Int = 0
    var horizonY: Int = 0 // where the far hills meet the sky
    var treeBaseY: Int = 0 // bottom of the tree line
    var groundY: Int = 0 // Pibo's feet
}

/// What the cached background depends on besides mood (decision 058): the scene Pibo
/// is in, the season and whether snow lies on the ground. Defaults draw the clearing.
struct PixelWorldLook {
    /// Raw scene id: `PiboCoreDayScene`, or `PIXEL_TRAIL_SCENE` for the trail.
    var scene: Int = 0
    /// Raw `PiboCoreDaySeason`.
    var season: Int = 1
    var snow: Bool = false
    /// Wind step, 0 or 1: the treeline's crowns lean a pixel and back (two cached copies).
    var wind: Int = 0
    /// For the trail only: the scene the view pans away from (on the trail's right) and the
    /// one it pans to (on its left), so the paths meet at both seams.
    var trailFrom: Int = 0
    var trailTo: Int = 0

    init(scene: PiboCoreDayScene = .clearing, season: PiboCoreDaySeason = .summer, snow: Bool = false,
         wind: Int = 0, trailFrom: PiboCoreDayScene = .clearing, trailTo: PiboCoreDayScene = .clearing) {
        self.scene = Int(scene.rawValue)
        self.season = Int(season.rawValue)
        self.snow = snow
        self.wind = wind
        self.trailFrom = Int(trailFrom.rawValue)
        self.trailTo = Int(trailTo.rawValue)
    }

    func key() -> String {
        "\(scene):\(season):\(snow ? 1 : 0):\(wind)"
    }
}

func pixelForestLayout(_ width: Int, _ height: Int) -> PixelForestLayout {
    var layout = PixelForestLayout()
    layout.width = width
    layout.height = height
    layout.horizonY = PixelMath.round(Double(height) * 0.38)
    layout.treeBaseY = PixelMath.round(Double(height) * 0.55)
    layout.groundY = PixelMath.round(Double(height) * 0.70)
    return layout
}

private let FLOWER: [String] = [".f.", "fuf", ".g."]
private let FLOWER_B: [String] = [".F.", "FuF", ".g."]
private let TUFTS: [[String]] = [
    ["E...E", ".g.g.", ".gGg."],
    [".E.", "gEg", "GgG"],
    ["E.E.E", "g.g.g", "GgGgG"],
    ["..E..", "E.g.E", "gGgGg"]
]
private let CLUSTER_A: [String] = [".f..F", "fuf.F", ".g.FuF", ".g..g."]
private let CLUSTER_B: [String] = ["..y..", ".yuy.", "..g.y", "..gyuy", "...g."]
private let PEBBLE_A: [String] = [".LL", "qqQ"]
private let PEBBLE_B: [String] = ["Lq", "qQ"]

/// Mood-aware ground inks a path or tuft may sit on.
private func isGrass(_ ink: PixelInk) -> Bool {
    ink == .groundMid || ink == .groundLight || ink == .groundDark
}

private func drawSky(_ frame: PixelFrame, _ layout: PixelForestLayout) {
    // Colour bands joined by horizontal brush streaks, the way hand-made pixel skies do it:
    // near each seam, longer runs of the next colour reach further in.
    let seamA = PixelMath.round(Double(layout.horizonY) * 0.42)
    let seamB = PixelMath.round(Double(layout.horizonY) * 0.8)
    let reach = 6
    for y in 0..<layout.treeBaseY {
        if abs(y - seamA) <= reach {
            PixelArt.drawStreakRow(frame, y: y, .skyTop, .skyMid,
                                   amount: (Double(y - seamA) + Double(reach) + 0.5) / Double(reach * 2 + 1),
                                   seed: 17)
        } else if abs(y - seamB) <= reach {
            PixelArt.drawStreakRow(frame, y: y, .skyMid, .skyLow,
                                   amount: (Double(y - seamB) + Double(reach) + 0.5) / Double(reach * 2 + 1),
                                   seed: 29)
        } else {
            frame.fillRect(0, y, frame.width, y + 1, y < seamA ? .skyTop : (y < seamB ? .skyMid : .skyLow))
        }
    }
}

private func drawDisc(_ frame: PixelFrame, _ cx: Int, _ cy: Int, _ r: Int, _ ink: PixelInk) {
    for y in (-r)...r {
        for x in (-r)...r {
            if Double(x * x + y * y) <= Double(r * r) + Double(r) * 0.6 { frame.set(cx + x, cy + y, ink) }
        }
    }
}

// A soft halo: dithered ring of `ink` fading out from radius r to r + spread.
private func drawHalo(_ frame: PixelFrame, _ cx: Int, _ cy: Int, _ r: Int, _ spread: Int, _ ink: PixelInk) {
    for y in (-r - spread)...(r + spread) {
        for x in (-r - spread)...(r + spread) {
            let d = Double(x * x + y * y).squareRoot()
            if d <= Double(r) || d > Double(r + spread) { continue }
            frame.ditherPixel(Double(cx + x), Double(cy + y), frame.get(cx + x, cy + y), ink,
                              0.5 * (1 - (d - Double(r)) / Double(spread)))
        }
    }
}

private func drawSkyLights(_ frame: PixelFrame, _ layout: PixelForestLayout, _ mood: PixelMood,
                           _ rng: PixelRandom) {
    if mood == .night {
        for i in 0..<PixelMath.round(Double(frame.width) * 0.3) {
            let sx = rng.int(0, frame.width - 1)
            let sy = rng.int(0, layout.horizonY - 6)
            // Most stars twinkle on their own beat (cycling inks); the bright ones hold steady.
            frame.set(sx, sy, i % 9 == 0 ? .glow : PixelMath.ink(.starA, i % 3))
            // A few bright stars get a small cross.
            if i % 9 == 0 {
                frame.set(sx - 1, sy, .skyLow)
                frame.set(sx + 1, sy, .skyLow)
                frame.set(sx, sy - 1, .skyLow)
                frame.set(sx, sy + 1, .skyLow)
            }
        }
        let mx = PixelMath.round(Double(frame.width) * 0.76)
        let my = PixelMath.round(Double(layout.horizonY) * 0.62)
        drawHalo(frame, mx, my, 7, 3, .skyLow)
        drawDisc(frame, mx, my, 6, .sun)
        drawDisc(frame, mx + 3, my - 2, 5, .skyTop)
        frame.set(mx - 3, my + 1, .cloudShade)
        frame.set(mx - 2, my + 3, .cloudShade)
        return
    }
    if mood == .rain { return }
    let dusk = mood == .dusk
    let sx = PixelMath.round(Double(frame.width) * 0.74)
    let sy = dusk ? PixelMath.round(Double(layout.horizonY) * 0.95)
        : PixelMath.round(Double(layout.horizonY) * 0.6)
    if dusk { drawHalo(frame, sx, sy, 8, 14, .sun) }
    drawDisc(frame, sx, sy, 8, .sun)
    frame.fillRect(sx - 3, sy - 6, sx + 1, sy - 5, .glow)
}

// A cumulus: overlapping puffs with a lit top and a flat, shaded underside.
private func drawCloud(_ frame: PixelFrame, _ cx: Int, _ cy: Int, _ w: Int, _ rng: PixelRandom,
                       _ heavy: Bool) {
    let puffs = max(3, PixelMath.round(Double(w) / 7))
    let bottom = cy + 3
    for i in 0..<puffs {
        let px = PixelMath.round(Double(cx) - Double(w) / 2
                                 + (Double(i) + 0.5) * (Double(w) / Double(puffs)))
        let middle = 1 - abs(Double(i) - Double(puffs - 1) / 2) / Double(puffs)
        let r = PixelMath.round(3 + middle * 4 + Double(rng.int(0, 2)))
        let py = bottom - r + 1
        for y in (-r)...r {
            for x in (-r)...r {
                if x * x + y * y > r * r || py + y > bottom { continue }
                let shade = Double(y) > Double(r) * 0.25 || (py + y) > bottom - 2
                let ink: PixelInk = heavy ? (shade ? .rain : .cloudShade)
                    : (shade ? .cloudShade : .cloudLight)
                frame.set(px + x, py + y, ink)
            }
        }
    }
}

private func drawClouds(_ frame: PixelFrame, _ layout: PixelForestLayout, _ mood: PixelMood,
                        _ rng: PixelRandom) {
    if mood == .night { return }
    if mood == .rain {
        // A low ceiling of heavy cloud.
        var x = -6
        while x < frame.width + 10 {
            drawCloud(frame, x, PixelMath.round(Double(layout.horizonY) * 0.55) + rng.int(-4, 4), 22, rng,
                      true)
            x += 12
        }
        return
    }
    let rows: [Double] = [0.62, 0.8, 0.95]
    for (index, row) in rows.enumerated() {
        let cx = PixelMath.round(rng.range(0.1, 0.9) * Double(frame.width))
        drawCloud(frame, cx, PixelMath.round(Double(layout.horizonY) * row),
                  18 + index * 6 + rng.int(0, 8), rng, false)
    }
}

// A row of soft hills: summed sines with seeded phases, with a lit rim on the sun side.
private func drawHills(_ frame: PixelFrame, _ baseY: Int, _ amplitude: Double, _ ink: PixelInk,
                       _ rng: PixelRandom, _ bottomY: Int, _ rim: PixelInk = .clear) {
    let p1 = rng.range(0, Double.pi * 2)
    let p2 = rng.range(0, Double.pi * 2)
    var previous = -1
    for x in 0..<frame.width {
        let top = PixelMath.round(Double(baseY)
                                  - amplitude * (0.6 * sin(Double(x) / 23 + p1) + 0.4 * sin(Double(x) / 9.5 + p2)))
        frame.fillRect(x, top, x + 1, bottomY, ink)
        // Slopes rising to the right catch the light.
        if rim != .clear && previous >= 0 && top <= previous { frame.set(x, top, rim) }
        previous = top
    }
}

// Far misty pines along a ridge line: tiny triangles in one ink.
private func drawMistPines(_ frame: PixelFrame, _ baseY: Int, _ ink: PixelInk, _ rng: PixelRandom) {
    // Clumps and gaps, not a fence: noise decides where the far wood is thick.
    var x = rng.int(0, 4)
    let seed = rng.int(0, 9999)
    while x < frame.width {
        let thick = PixelArt.noise(Double(x), 0, cell: 14, seed: seed)
        if thick > 0.38 {
            let h = 3 + PixelMath.round(thick * 6) + rng.int(0, 2)
            for row in 0..<h {
                let half = row / 2
                let left = x - half
                frame.fillRect(left, baseY - h + row, left + half * 2 + 1, baseY - h + row + 1, ink)
            }
        }
        x += thick > 0.6 ? rng.int(2, 4) : rng.int(4, 8)
    }
}

// A pine: stacked tiers, each a little wider, lit on the left, shaded on the right.
private func drawPine(_ frame: PixelFrame, _ cx: Int, _ baseY: Int, _ h: Int, _ snow: Bool,
                      _ inks: [PixelInk]) {
    let tiers = max(3, PixelMath.round(Double(h) / 7))
    let tierH = PixelMath.round(Double(h) / Double(tiers)) + 2
    frame.fillRect(cx - 1, baseY - 4, cx + 1, baseY, .trunk)
    for t in 0..<tiers {
        let top = baseY - h + PixelMath.round(Double(t) * Double(h - 4) / Double(tiers))
        let maxHalf = 2 + PixelMath.round(Double(t + 1) * Double(h) / (Double(tiers) * 2.6))
        for row in 0..<tierH {
            let half = max(0, PixelMath.round(Double(maxHalf) * Double(row + 1) / Double(tierH)))
            for dx in (-half)...half {
                var ink = inks[1]
                if Double(dx) < -Double(half) * 0.35 { ink = inks[2] }
                if Double(dx) > Double(half) * 0.4 || row == tierH - 1 { ink = inks[0] }
                if snow && row < 2 && dx <= 0 { ink = .snow }
                frame.set(cx + dx, top + row, ink)
            }
        }
    }
}

private func foliageInks(_ autumn: Bool) -> [PixelInk] {
    autumn ? [.autumnDeep, .autumnLeaf, .autumnLight] : [.treeDark, .treeMid, .treeLight]
}

// A broadleaf tree: a trunk and two or three foliage clumps.
private func drawBroadleaf(_ frame: PixelFrame, _ cx: Int, _ baseY: Int, _ r: Int, _ autumn: Bool,
                           _ snow: Bool, _ seed: Int, _ wind: Int = 0) {
    let trunkTop = baseY - r - 2
    frame.fillRect(cx - 1, trunkTop, cx + 2, baseY, .trunk)
    frame.set(cx + 1, trunkTop + 3, .woodDark)
    let inks = foliageInks(autumn)
    let cy = baseY - r - PixelMath.round(Double(r) * 0.9)
    PixelArt.drawFoliage(frame, cx: cx - PixelMath.round(Double(r) * 0.55),
                         cy: cy + PixelMath.round(Double(r) * 0.35),
                         rx: PixelMath.round(Double(r) * 0.7), ry: PixelMath.round(Double(r) * 0.6),
                         inks: inks, seed: seed + 1)
    PixelArt.drawFoliage(frame, cx: cx + PixelMath.round(Double(r) * 0.55),
                         cy: cy + PixelMath.round(Double(r) * 0.4),
                         rx: PixelMath.round(Double(r) * 0.65), ry: PixelMath.round(Double(r) * 0.55),
                         inks: inks, seed: seed + 2)
    PixelArt.drawFoliage(frame, cx: cx + wind, cy: cy, rx: r,
                         ry: PixelMath.round(Double(r) * 0.8), inks: inks, seed: seed)
    if snow {
        for dx in (-r + 2)..<(r - 1) {
            let ny = max(0, 1 - Double(dx * dx) / Double(r * r)).squareRoot() * Double(r) * 0.8
            if (dx & 3) != 3 { frame.set(cx + wind + dx, cy - PixelMath.round(ny) + 1, .snow) }
        }
    }
}

private func drawTreeLine(_ frame: PixelFrame, _ layout: PixelForestLayout, _ rng: PixelRandom,
                          _ world: PixelWorldLook = PixelWorldLook()) {
    let base = layout.treeBaseY
    let lower = world.scene == 2 ? 8 : 0
    // Back mass so gaps never show sky through the forest.
    for x in 0..<frame.width {
        let top = base - 18 + lower
            + PixelMath.round(sin(Double(x) / 5) * 2 + sin(Double(x) / 13) * 3)
        frame.fillRect(x, top, x + 1, base, .pineDark)
    }
    // A separate stream keeps the clearing's own trees identical across seasons.
    let tint = PixelRandom(9091)
    let autumn = world.season == 2
    let pines: [PixelInk] = [.pineDark, .pineMid, .pineLight]
    // Back row: pines.
    var x = -rng.int(0, 6)
    while x < frame.width + 8 {
        drawPine(frame, x, base - 6 + lower, rng.int(18, 28) - lower, world.snow, pines)
        x += rng.int(7, 12)
    }
    // Front row: broadleaf clumps with the odd pine between them.
    x = -rng.int(0, 10)
    var index = 0
    while x < frame.width + 12 {
        if rng.next() < 0.28 {
            drawPine(frame, x, base, rng.int(24, 34) - lower, world.snow, pines)
            x += rng.int(8, 12)
        } else {
            let r = rng.int(8, 12) - (lower > 0 ? 2 : 0)
            // Every other crown leans with the wind, so the line ripples instead of sliding.
            drawBroadleaf(frame, x, base + 1, r, autumn && tint.next() < 0.6, world.snow,
                          311 + index * 17, index % 2 == 0 ? world.wind : 0)
            x += rng.int(12, 18)
        }
        index += 1
    }
    // The wood's shadow falls on the meadow edge.
    for y in base..<(base + 3) {
        for px in 0..<frame.width {
            frame.ditherPixel(Double(px), Double(y), .groundShadow, .groundDark,
                              Double(y - base) / 3)
        }
    }
}

// Snow on the ground: light ground becomes snow, mid ground mostly snow shade.
private func snowGround(_ frame: PixelFrame, _ layout: PixelForestLayout) {
    for y in layout.treeBaseY..<frame.height {
        for x in 0..<frame.width {
            let ink = frame.get(x, y)
            if ink == .groundLight || ink == .pathLight || ink == .grassTip {
                frame.set(x, y, .snow)
            } else if ink == .groundMid || ink == .pathMid {
                frame.set(x, y, (x * 3 + y) % 7 == 0 ? .groundMid : .snowShade)
            } else if ink == .leafMid || ink == .flowerA || ink == .flowerB {
                frame.set(x, y, .snow)
            }
        }
    }
}

// The hill scene's far range: taller, layered ridges with snowy peaks in winter.
private func drawRidges(_ frame: PixelFrame, _ layout: PixelForestLayout, _ world: PixelWorldLook) {
    for x in 0..<frame.width {
        let peak = PixelMath.round(Double(layout.horizonY) - 10
                                   - 16 * abs(sin(Double(x) / 31 + 0.7)) - 5 * sin(Double(x) / 11))
        let sine = sin(Double(x) / 31 + 0.7)
        let sign: Double = sine > 0 ? 1 : (sine < 0 ? -1 : 0)
        let slope = cos(Double(x) / 31 + 0.7) * sign
        for y in peak..<(layout.horizonY + 6) {
            var ink: PixelInk = .hillFar
            if slope > 0 && y < peak + 2 { ink = .hillNear }
            if (world.snow || world.season == 3) && y < peak + 3 { ink = .snow }
            frame.set(x, y, ink)
        }
    }
}

// The dirt path: a ribbon whose centre follows `points` ([x, y] pairs), lit on its upper
// edge, shaded on the lower one, with pebbles. Only grass is painted over.
private func drawPath(_ frame: PixelFrame, _ points: [[Int]], _ width: Double, _ seed: Int) {
    for i in 0..<(points.count - 1) {
        let a = points[i]
        let b = points[i + 1]
        let steps = max(1, Int((Double(max(abs(b[0] - a[0]), abs(b[1] - a[1])))).rounded(.up)))
        for s in 0...steps {
            let t = Double(s) / Double(steps)
            let e = t * t * (3 - 2 * t)
            let x = PixelMath.round(Double(a[0]) + Double(b[0] - a[0]) * t)
            let y = PixelMath.round(Double(a[1]) + Double(b[1] - a[1]) * e)
            let half = max(2, PixelMath.round(width / 2 + sin(Double(x + y) / 7) * 0.8))
            for dy in (-half)...half {
                for dx in (-half - 1)...(half + 1) {
                    if Double(dx * dx) / Double((half + 1) * (half + 1))
                        + Double(dy * dy) / Double(half * half) > 1 { continue }
                    let px = x + dx
                    let py = y + dy
                    let under = frame.get(px, py)
                    if !isGrass(under) && under != .pathMid && under != .pathLight
                        && under != .grassTip && under != .groundShadow { continue }
                    var ink: PixelInk = .pathMid
                    if dy == -half { ink = .pathLight }
                    if dy >= half - 1 { ink = .pathDark }
                    if ink == .pathMid && PixelArt.noise(Double(px), Double(py), cell: 2, seed: seed) > 0.72 {
                        ink = .pathLight
                    }
                    if under == .pathLight && ink == .pathDark { continue }
                    frame.set(px, py, ink)
                }
            }
        }
    }
}

/// Not a place Pibo stays: the stretch of woodland trail the view pans along between two
/// scenes (2026-10-21). Drawn by drawPixelForestStatic like the others.
let PIXEL_TRAIL_SCENE: Int = 3

// The trail runs from where the next scene's path leaves its right edge (or the middle
// of the ground, if it does not) to where the last scene's path came in on the left.
private func trailPath(_ layout: PixelForestLayout, _ world: PixelWorldLook) -> [[Int]] {
    let w = layout.width
    let g = layout.groundY
    let right = pathFor(layout, world.trailFrom)[0][1]
    let to = pathFor(layout, world.trailTo)
    let end = to[to.count - 1]
    let left = end[0] >= w ? end[1] : g + 10
    return [[-4, left],
            [PixelMath.round(Double(w) * 0.3),
             PixelMath.round(Double(left) * 0.6 + Double(right) * 0.4) - 3],
            [PixelMath.round(Double(w) * 0.65),
             PixelMath.round(Double(left) * 0.3 + Double(right) * 0.7) + 3],
            [w + 4, right]]
}

private func pathFor(_ layout: PixelForestLayout, _ scene: Int) -> [[Int]] {
    let w = layout.width
    let g = layout.groundY
    // Each path starts at the forest edge Pibo walks through and ends in the open ground.
    switch scene {
    case 1:
        return [[-4, g + 6], [PixelMath.round(Double(w) * 0.22), g + 4],
                [PixelMath.round(Double(w) * 0.5), g + 8],
                [PixelMath.round(Double(w) * 0.78), g + 2], [w + 4, g - 2]]
    case 2:
        return [[-4, g + 22], [PixelMath.round(Double(w) * 0.24), g + 16],
                [PixelMath.round(Double(w) * 0.46), g + 6],
                [PixelMath.round(Double(w) * 0.62), g - 10],
                [PixelMath.round(Double(w) * 0.74), g - 22]]
    default:
        return [[-4, g + 26], [PixelMath.round(Double(w) * 0.24), g + 22],
                [PixelMath.round(Double(w) * 0.42), g + 10],
                [PixelMath.round(Double(w) * 0.5), g + 4]]
    }
}

private func drawGround(_ frame: PixelFrame, _ layout: PixelForestLayout, _ rng: PixelRandom,
                        _ scene: Int, _ world: PixelWorldLook = PixelWorldLook()) {
    let top = layout.treeBaseY
    let seed = 71 + scene * 13
    // Meadow: soft light and dark patches from noise, dithered at their edges.
    for y in top..<frame.height {
        for x in 0..<frame.width {
            let n = PixelArt.noise(Double(x), Double(y) * 1.6, cell: 16, seed: seed) * 0.75
                + PixelArt.noise(Double(x), Double(y) * 1.6, cell: 5, seed: seed + 1) * 0.25
            if n < 0.32 {
                frame.ditherPixel(Double(x), Double(y), .groundMid, .groundDark,
                                  min(0.85, (0.32 - n) * 5))
            } else if n > 0.64 {
                frame.ditherPixel(Double(x), Double(y), .groundMid, .groundLight,
                                  min(0.9, (n - 0.64) * 5))
            } else {
                frame.set(x, y, .groundMid)
            }
        }
    }
    // Lit clearing around where Pibo stands.
    let cx = Double(frame.width) / 2
    for y in (layout.groundY - 10)..<(layout.groundY + 9) {
        let ry = Double(y - layout.groundY + 1) / 9.5
        let half = PixelMath.round(Double(frame.width) * 0.34 * max(0, 1 - ry * ry).squareRoot())
        var px = PixelMath.round(cx - Double(half))
        while Double(px) < cx + Double(half) {
            let edge = abs(Double(px) - cx) / Double(max(1, half))
            frame.ditherPixel(Double(px), Double(y), .groundLight, frame.get(px, y), edge * edge)
            px += 1
        }
    }
    // The foreground falls into shade toward the bottom edge.
    for y in (frame.height - 34)..<frame.height {
        let amount = Double(y - (frame.height - 34)) / 34
        for x in 0..<frame.width {
            if frame.get(x, y) == .groundLight { frame.set(x, y, .groundMid) }
            frame.ditherPixel(Double(x), Double(y), frame.get(x, y), .groundDark, amount * 0.8)
        }
    }
    drawPath(frame, scene == PIXEL_TRAIL_SCENE ? trailPath(layout, world) : pathFor(layout, scene), 6,
             seed + 5)
    // Grass tufts with bright tips, flower clusters and pebbles, never on the path.
    for _ in 0..<PixelMath.round(Double(frame.width) * 0.5) {
        let tx = rng.int(0, frame.width - 5)
        let ty = rng.int(top + 5, frame.height - 4)
        if abs(Double(tx) - cx) < 20 && abs(Double(ty - layout.groundY)) < 7 { continue }
        if !isGrass(frame.get(tx + 2, ty + 2)) { continue }
        frame.stamp(TUFTS[rng.int(0, TUFTS.count - 1)], tx, ty)
    }
    for _ in 0..<PixelMath.round(Double(frame.width) * 0.05) {
        let fx = rng.int(2, frame.width - 7)
        let fy = rng.int(top + 8, frame.height - 22)
        if abs(Double(fx) - cx) < 24 && abs(Double(fy - layout.groundY)) < 10 { continue }
        if !isGrass(frame.get(fx + 2, fy + 2)) { continue }
        let pick = rng.next()
        frame.stamp(pick < 0.4 ? CLUSTER_A : (pick < 0.7 ? CLUSTER_B : (pick < 0.85 ? FLOWER : FLOWER_B)),
                    fx, fy)
    }
    for _ in 0..<PixelMath.round(Double(frame.width) * 0.06) {
        let px = rng.int(1, frame.width - 4)
        let py = rng.int(top + 6, frame.height - 6)
        frame.stamp(rng.next() < 0.5 ? PEBBLE_A : PEBBLE_B, px, py)
    }
}

// A dark row of bushes and grass along the bottom edge frames the meadow like a stage.
private func drawForeground(_ frame: PixelFrame, _ layout: PixelForestLayout, _ rng: PixelRandom,
                            _ world: PixelWorldLook) {
    let bottom = frame.height
    let inks: [PixelInk] = [.pineDark, .treeDark, .treeMid]
    var x = -rng.int(2, 8)
    var index = 0
    while x < frame.width + 10 {
        let corner = x < 14 || x > frame.width - 16
        let r = corner ? rng.int(10, 13) : rng.int(6, 9)
        PixelArt.drawFoliage(frame, cx: x, cy: bottom + 1, rx: r + 2, ry: r, inks: inks,
                             seed: 900 + index * 7)
        // Berries on some, a snow cap in winter.
        if rng.next() < 0.4 && !world.snow {
            frame.set(x - 2, bottom - r + 1, .berry)
            frame.set(x + 2, bottom - r + 3, .berry)
        }
        if world.snow {
            for dx in (-r + 2)..<(r - 1) {
                let top = PixelMath.round(Double(bottom + 1)
                                          - Double(r) * max(0, 1 - Double(dx * dx) / Double((r + 2) * (r + 2))).squareRoot())
                if (dx & 3) != 3 { frame.set(x + dx, top + 1, .snow) }
            }
        }
        x += rng.int(r + 6, r + 14)
        index += 1
    }
    // Tall dark blades between the bushes.
    for _ in 0..<PixelMath.round(Double(frame.width) / 6) {
        let bx = rng.int(0, frame.width - 1)
        let h = rng.int(5, 11)
        let lean = rng.next() < 0.5 ? -1 : 1
        for k in 0..<h {
            frame.set(bx + (Double(k) > Double(h) * 0.6 ? lean : 0), bottom - 1 - k,
                      k > h - 3 ? .treeMid : .pineDark)
        }
    }
}

func drawPixelForestStatic(_ frame: PixelFrame, _ layout: PixelForestLayout, _ seed: Int,
                           _ mood: PixelMood, _ world: PixelWorldLook = PixelWorldLook()) {
    // Each scene is its own seeded place; the clearing keeps the original seed.
    let rng = PixelRandom(seed + world.scene * 7919)
    frame.clear(.skyMid)
    drawSky(frame, layout)
    drawSkyLights(frame, layout, mood, rng)
    drawClouds(frame, layout, mood, rng)
    if world.scene == 2 {
        drawRidges(frame, layout, world)
    }
    drawHills(frame, layout.horizonY + 2, 7, .hillFar, rng, layout.treeBaseY)
    drawMistPines(frame, layout.horizonY + 10, .hillFar, rng)
    drawHills(frame, layout.horizonY + 14, 5, .hillNear, rng, layout.treeBaseY)
    drawTreeLine(frame, layout, rng, world)
    drawGround(frame, layout, rng, world.scene, world)
    if world.season == 0 && !world.snow {
        // Spring: the grass is full of small flowers.
        let bloom = PixelRandom(seed ^ 0x5151)
        for _ in 0..<PixelMath.round(Double(frame.width) * 0.14) {
            let fx = bloom.int(2, frame.width - 3)
            let fy = bloom.int(layout.treeBaseY + 6, frame.height - 6)
            if isGrass(frame.get(fx, fy)) { frame.set(fx, fy, bloom.next() < 0.5 ? .flowerB : .flowerA) }
        }
    }
    if world.snow { snowGround(frame, layout) }
    drawForeground(frame, layout, PixelRandom(seed ^ 0x0F0F), world)
}

// Weather and small life, redrawn every frame on top of the static layers.
func drawPixelForestLife(_ frame: PixelFrame, _ layout: PixelForestLayout, _ seed: Int,
                         _ mood: PixelMood, _ raining: Bool, _ timeMs: Double,
                         _ fireflies: Bool = true) {
    let frameIndex = PixelMath.floor(max(0, timeMs) / 100)
    if raining {
        let rng = PixelRandom(seed ^ 0x5A17)
        let drops = PixelMath.round(Double(frame.width * frame.height) / 260)
        for _ in 0..<drops {
            let x0 = rng.int(0, frame.width + 40)
            let y0 = rng.int(0, frame.height)
            let speed = rng.int(5, 8)
            let y = (y0 + frameIndex * speed) % (frame.height + 8) - 4
            let x = (x0 - PixelMath.floor(Double(y) / 3)) % (frame.width + 40)
            frame.set(x, y, .rain)
            frame.set(x, y + 1, .rain)
            frame.set(x - 1, y + 2, .rain)
        }
        return
    }
    if fireflies && (mood == .night || mood == .dusk) {
        let rng = PixelRandom(seed ^ 0xF1F1)
        let count = mood == .night ? 9 : 4
        for _ in 0..<count {
            let bx = rng.int(4, frame.width - 4)
            let by = rng.int(layout.treeBaseY - 20, layout.groundY + 30)
            let phase = rng.int(0, 40)
            let f = frameIndex + phase
            if (f % 40) > 30 { continue } // fireflies blink off for a moment
            let x = bx + PixelMath.round(sin(Double(f) / 7) * 3)
            let y = by + PixelMath.round(cos(Double(f) / 9) * 2)
            frame.set(x, y, .glow)
        }
    }
}

func pixelMoodFor(_ hour: Int, _ raining: Bool) -> PixelMood {
    if raining { return .rain }
    if hour < 0 { return .day }
    if hour >= 20 || hour < 5 { return .night }
    if hour >= 17 || hour < 7 { return .dusk }
    return .day
}

import Foundation

// Light on things (2026-10-21, decision 065's pixel finish). Nothing here blends: a lit
// pixel steps up to the next lighter ink of its own ramp, dithered by distance, so the
// palette stays closed and a pool of firelight still reads as pixel art.
//
// Ported from HarmonyPibo `pixel/effects/PixelLight.ets`.

/// One light: where it is and how far it reaches, in logical pixels.
struct PixelLightSource {
    var x: Int = 0
    var y: Int = 0
    var radius: Int = 0
}

func pixelLightSource(_ x: Int, _ y: Int, _ radius: Int) -> PixelLightSource {
    PixelLightSource(x: x, y: y, radius: max(1, radius))
}

// Each ink's next step towards the light; inks that are their own step are left alone
// (outlines, eyes, sky, the lights themselves).
private let LIGHTER_PAIRS: [[PixelInk]] = [
    [.groundShadow, .groundDark], [.groundDark, .groundMid],
    [.groundMid, .groundLight], [.groundLight, .grassTip],
    [.leafDark, .leafMid], [.leafMid, .leafLight],
    [.treeDark, .treeMid], [.treeMid, .treeLight],
    [.pineDark, .pineMid], [.pineMid, .pineLight],
    [.stoneDark, .stone], [.stone, .stoneLight],
    [.woodDark, .woodMid], [.woodMid, .woodLight], [.trunk, .woodMid],
    [.bodyShade, .bodyMid], [.bodyMid, .bodyLight],
    [.muzzleShade, .muzzle],
    [.pathDark, .pathMid], [.pathMid, .pathLight],
    [.waterDeep, .water], [.water, .waterLight],
    [.moss, .leafMid], [.clothShade, .cloth], [.scarfShade, .scarf],
    [.snowShade, .snow], [.autumnDeep, .autumnLeaf],
    [.autumnLeaf, .autumnLight], [.acornCap, .acorn]
]

private let LIGHTER: [PixelInk] = {
    var table = PixelInk.allCases
    for pair in LIGHTER_PAIRS { table[pair[0].index] = pair[1] }
    return table
}()

/// Lights the frame around each source: one step lighter towards the edge of its reach,
/// two steps near the middle, dithered in between.
func applyPixelLight(_ frame: PixelFrame, _ lights: [PixelLightSource]) {
    for light in lights {
        let r = light.radius
        for dy in (-r)...r {
            for dx in (-r)...r {
                // Light spreads wider than tall: the ground is seen at a slant.
                let d = (Double(dx * dx) + Double(dy * dy) * 2.2).squareRoot() / Double(r)
                if d >= 1 { continue }
                let x = light.x + dx
                let y = light.y + dy
                let ink = frame.get(x, y)
                let one = LIGHTER[ink.index]
                if one == ink { continue }
                let a = 1 - d
                if a > 0.6 {
                    frame.ditherPixel(Double(x), Double(y), one, LIGHTER[one.index], (a - 0.6) / 0.4)
                } else {
                    frame.ditherPixel(Double(x), Double(y), ink, one, a / 0.6)
                }
            }
        }
    }
}

// What a thing standing on the far bank looks like in the water: light things a light
// streak, everything else a dark shape. Clear means it does not show in the water.
private let REFLECTION: [PixelInk] = {
    var table = [PixelInk](repeating: .clear, count: PixelInk.count)
    let light: [PixelInk] = [.bodyLight, .bodyMid, .muzzle, .leafLight, .glow, .sun, .snow,
                             .woodLight, .stoneLight, .cloth, .flowerA, .flowerB, .fire, .fireCore,
                             .signFace, .grassTip]
    let dark: [PixelInk] = [.outline, .line, .bodyShade, .muzzleShade, .leafMid, .leafDark,
                            .trunk, .woodMid, .woodDark, .stone, .stoneDark, .acornCap, .acorn,
                            .moss, .clothShade, .scarf, .scarfShade, .eye, .treeDark, .treeMid]
    for ink in light { table[ink.index] = .waterLight }
    for ink in dark { table[ink.index] = .waterDeep }
    return table
}()

private let REFLECT_ROWS: Int = 12

private func isWater(_ ink: PixelInk) -> Bool {
    ink == .water || ink == .waterDeep || ink == .waterLight
        || ink == .waterFlowA || ink == .waterFlowB || ink == .waterFlowC
}

/// The creek mirrors what stands on its far bank (Pibo, reeds, the log) below the sandy
/// lip, wobbling a pixel with the flow and fading out with depth. Only water is written.
func applyPixelReflection(_ frame: PixelFrame, _ layout: PixelForestLayout, _ timeMs: Double) {
    let wave = PixelMath.floor(max(0, timeMs) / 260) % 4
    for x in 0..<frame.width {
        let top = pixelCreekTop(layout, x)
        for k in 0..<REFLECT_ROWS {
            // Deeper rows break up: every other pixel, then fewer.
            if k >= 5 && (x + k) % 2 == 1 { continue }
            if k >= 9 && (x + k) % 4 != 0 { continue }
            let y = top + 1 + k
            let shift = ((y + wave) & 2) == 0 ? 0 : 1
            let mirrored = REFLECTION[frame.get(x + shift, top - 3 - k).index]
            if mirrored == .clear || !isWater(frame.get(x, y)) { continue }
            frame.set(x, y, mirrored)
        }
    }
}

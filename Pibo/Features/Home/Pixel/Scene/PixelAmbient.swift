import Foundation
import PiboCore

// The forest's small life (decision 058). Core says which kinds are around for the
// season, hour and weather; this file draws them as pure functions of time, so a frame
// can be redrawn at any moment and tests can pin it.
//
// Ported from HarmonyPibo `pixel/scene/PixelAmbient.ets`; the mask is Core's
// `PiboCoreAmbient` bits, which match the ArkTS `PIBO_AMBIENT_*` constants.

struct PixelAmbientAnchors {
    /// The knot hole a squirrel peeks out of, if the scene has a big tree.
    var treeHole: [Int] = []
    /// Centre of water a fish can jump from.
    var water: [Int] = []
    /// Where butterflies hang around.
    var flowers: [[Int]] = []
    /// A tap on the tree sends the squirrel out at once.
    var squirrelPokedAt: Double = -1
    /// A tap on the water makes a fish jump at once.
    var fishPokedAt: Double = -1
}

private let CLOUD_A: [String] = ["..wwww...", ".wwwwwww.", "wwwwwwwwm", ".mmmmmmm."]
private let CLOUD_B: [String] = ["...ww..", ".wwwww.", "wwwwwwm", ".mmmmm."]
private let BIRD_UP: [String] = ["o...o", ".o.o.", "..o.."]
private let BIRD_DOWN: [String] = [".....", ".ooo.", "o.o.o"]
private let BUTTERFLY_OPEN: [String] = ["f.f", ".o.", "f.f"]
private let BUTTERFLY_SHUT: [String] = [".f.", ".o.", ".f."]
private let SQUIRREL: [String] = ["h.h..", "hhhH.", "heHhh", ".hhhh", "..hHh"]
private let FISH: [String] = [".xx.", "xxXx", ".xx."]

private func cycle(_ timeMs: Double, _ periodMs: Double, _ offsetMs: Double) -> Double {
    ((timeMs + offsetMs).truncatingRemainder(dividingBy: periodMs) + periodMs)
        .truncatingRemainder(dividingBy: periodMs)
}

private func drawClouds(_ frame: PixelFrame, _ layout: PixelForestLayout, _ timeMs: Double) {
    for i in 0..<3 {
        let span = frame.width + 30
        let speed = 1400 + i * 500
        let x = PixelMath.floor(cycle(timeMs, Double(speed * span), Double(i * 9000)) / Double(speed)) - 15
        let y = PixelMath.round(Double(layout.horizonY) * (0.18 + Double(i) * 0.17))
        frame.stamp(i % 2 == 0 ? CLOUD_A : CLOUD_B, x, y)
    }
}

private func drawBirds(_ frame: PixelFrame, _ layout: PixelForestLayout, _ timeMs: Double) {
    // A small flock crosses every so often, flapping in steps.
    let period = 37000.0
    let flight = 9000.0
    let t = cycle(timeMs, period, 4000)
    if t > flight { return }
    let progress = t / flight
    let flap = PixelMath.floor(timeMs / 250) % 2 == 0
    for i in 0..<3 {
        let x = PixelMath.round(Double(frame.width) + 10 - progress * (Double(frame.width) + 30)) + i * 7
        let y = PixelMath.round(Double(layout.horizonY) * 0.42) + (i % 2) * 4
            + PixelMath.round(sin(progress * 6 + Double(i)) * 2)
        frame.stamp(flap ? BIRD_UP : BIRD_DOWN, x, y)
    }
}

private func drawButterflies(_ frame: PixelFrame, _ anchors: PixelAmbientAnchors, _ timeMs: Double) {
    for (i, spot) in anchors.flowers.prefix(2).enumerated() {
        let t = timeMs / 1000 + Double(i) * 3.1
        let x = PixelMath.round(Double(spot[0]) + sin(t * 0.9) * 12 + sin(t * 2.3) * 3)
        let y = PixelMath.round(Double(spot[1]) - 10 + sin(t * 1.7) * 5)
        let open = PixelMath.floor(timeMs / 160 + Double(i)) % 2 == 0
        frame.stamp(open ? BUTTERFLY_OPEN : BUTTERFLY_SHUT, x, y)
    }
}

private func drawFalling(_ frame: PixelFrame, _ layout: PixelForestLayout, _ timeMs: Double,
                         _ count: Int, _ periodMs: Double, _ seed: Int, _ inks: [PixelInk],
                         _ size: Int) {
    let rng = PixelRandom(seed)
    let top = layout.treeBaseY - 24
    let bottom = layout.groundY + 60
    for i in 0..<count {
        let x0 = rng.int(0, frame.width - 1)
        let offset = rng.int(0, PixelMath.floor(periodMs))
        let local = cycle(timeMs, periodMs, Double(offset)) / periodMs
        let sway = PixelMath.round(sin(local * Double.pi * 4 + Double(i)) * 4)
        let x = x0 + sway + PixelMath.round(local * 10)
        let y = PixelMath.round(Double(top) + local * Double(bottom - top))
        let ink = inks[i % inks.count]
        frame.set(x, y, ink)
        if size > 1 {
            frame.set(x + (PixelMath.floor(local * 20) % 2 == 0 ? 1 : -1), y, ink)
        }
    }
}

private func drawSnowfall(_ frame: PixelFrame, _ timeMs: Double) {
    let rng = PixelRandom(0x5A0F)
    let flakes = PixelMath.round(Double(frame.width * frame.height) / 700)
    let frameIndex = PixelMath.floor(timeMs / 100)
    for i in 0..<flakes {
        let x0 = rng.int(0, frame.width)
        let y0 = rng.int(0, frame.height)
        let speed = rng.int(1, 2)
        let y = (y0 + frameIndex * speed) % (frame.height + 4) - 2
        let x = x0 + PixelMath.round(sin(Double(frameIndex + i * 7) / 9) * 2)
        frame.set(x, y, .snow)
    }
}

private func drawFog(_ frame: PixelFrame, _ layout: PixelForestLayout, _ timeMs: Double) {
    // A drifting veil over the tree line, thinning toward the clearing.
    let drift = PixelMath.floor(timeMs / 600)
    let top = layout.treeBaseY - 26
    for y in top..<(layout.treeBaseY + 12) {
        let density = 1 - Double(abs(y - (layout.treeBaseY - 6))) / 20
        if density <= 0 { continue }
        for x in 0..<frame.width {
            let band = sin(Double(x + drift) / 17 + Double(y) / 5) * 0.5 + 0.5
            if ((x + y) & 1) == 0 && band * density > 0.35 { frame.set(x, y, .skyLow) }
        }
    }
}

private func drawSquirrel(_ frame: PixelFrame, _ anchors: PixelAmbientAnchors, _ timeMs: Double) {
    if anchors.treeHole.count < 2 { return }
    let poked = anchors.squirrelPokedAt >= 0 && timeMs - anchors.squirrelPokedAt < 4000
    let t = poked ? timeMs - anchors.squirrelPokedAt : cycle(timeMs, 31000, 12000)
    if t > 4000 { return }
    // Peeks out, looks around, ducks back.
    let out = t < 400 ? 1 : (t > 3600 ? 1 : 3)
    let flip = PixelMath.floor(t / 900) % 2 == 1
    frame.stamp(Array(SQUIRREL.prefix(out + 2)), anchors.treeHole[0] - 2, anchors.treeHole[1] - out,
                flip: flip)
}

private func drawFish(_ frame: PixelFrame, _ anchors: PixelAmbientAnchors, _ timeMs: Double) {
    if anchors.water.count < 2 { return }
    let poked = anchors.fishPokedAt >= 0 && timeMs - anchors.fishPokedAt < 1600
    let t = poked ? timeMs - anchors.fishPokedAt : cycle(timeMs, 17000, 3000)
    let jump = 1200.0
    let x0 = anchors.water[0]
    let y0 = anchors.water[1]
    if t < jump {
        let p = t / jump
        let x = PixelMath.round(Double(x0) - 6 + p * 12)
        let y = PixelMath.round(Double(y0) - sin(p * Double.pi) * 9)
        frame.stamp(FISH, x - 2, y - 1, flip: p > 0.5)
    } else if t < jump + 700 {
        let r = 1 + PixelMath.floor((t - jump) / 140)
        frame.fillRect(x0 + 6 - r, y0, x0 + 6 - r + r * 2 + 1, y0 + 1, .waterLight)
    }
}

private func drawRainbow(_ frame: PixelFrame, _ layout: PixelForestLayout) {
    let inks: [PixelInk] = [.scarf, .fire, .fireCore, .leafLight, .waterLight, .flowerB]
    let ox = PixelMath.round(Double(frame.width) * 0.32)
    let oy = layout.treeBaseY + 10
    let outer = PixelMath.round(Double(frame.width) * 0.55)
    for band in 0..<inks.count {
        let r = outer - band
        for x in (ox - r)...(ox + r) {
            let y = PixelMath.round(Double(oy)
                                    - Double(max(0, r * r - (x - ox) * (x - ox))).squareRoot())
            // Half-transparent: every other pixel, only over the sky.
            if y < layout.treeBaseY - 12 && ((x + band) & 1) == 0 { frame.set(x, y, inks[band]) }
        }
    }
}

/// Sky-side life, drawn behind the scene's places and Pibo.
func drawPixelAmbientBack(_ frame: PixelFrame, _ layout: PixelForestLayout, _ mask: PiboCoreAmbient,
                          _ anchors: PixelAmbientAnchors, _ timeMs: Double) {
    if mask.contains(.rainbow) { drawRainbow(frame, layout) }
    if mask.contains(.clouds) { drawClouds(frame, layout, timeMs) }
    if mask.contains(.birds) { drawBirds(frame, layout, timeMs) }
    if mask.contains(.fog) { drawFog(frame, layout, timeMs) }
}

/// Life that moves in front of the scene: falling things, butterflies, the squirrel and fish.
func drawPixelAmbientFront(_ frame: PixelFrame, _ layout: PixelForestLayout, _ mask: PiboCoreAmbient,
                           _ anchors: PixelAmbientAnchors, _ timeMs: Double) {
    if mask.contains(.squirrel) || anchors.squirrelPokedAt >= 0 {
        drawSquirrel(frame, anchors, timeMs)
    }
    if mask.contains(.fish) || anchors.fishPokedAt >= 0 {
        drawFish(frame, anchors, timeMs)
    }
    if mask.contains(.butterflies) { drawButterflies(frame, anchors, timeMs) }
    if mask.contains(.fallingLeaves) {
        drawFalling(frame, layout, timeMs, 7, 9000, 0x1EAF,
                    [.autumnLeaf, .autumnDeep, .fireCore], 2)
    }
    if mask.contains(.petals) {
        drawFalling(frame, layout, timeMs, 8, 11000, 0x9E7A, [.flowerB, .bodyLight], 1)
    }
    if mask.contains(.snowfall) { drawSnowfall(frame, timeMs) }
}

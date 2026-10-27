import Foundation

// Season two, "小溪那边" (decision 059): the bridge Pibo builds plank by plank over the
// creek, the older pod in the moss on the far bank and, from the clearing, its light far
// off in the trees blinking with the antenna. Core says how far things have got; this
// file only places and draws them.
//
// Ported from HarmonyPibo `pixel/scene/PixelSeasonTwo.ets`.

let PIXEL_SEASON_OLD_POD: Int = 203
let PIXEL_SEASON_BRIDGE: Int = 204

struct PixelSeasonTwoLook {
    /// Bridge planks laid, 0–5.
    var planks: Int = 0
    /// Pibo has crossed and found the old pod.
    var oldPodFound: Bool = false
    /// The old pod's lamp works again: it blinks with the antenna.
    var oldPodLit: Bool = false
    /// The light across the creek has been seen (from the clearing at night).
    var farLight: Bool = false
    var timeMs: Double = 0
    var night: Bool = false
    var snow: Bool = false
    var poked: Int = -1
    var pokeAge: Int = -1
}

struct PixelSeasonTwoBox {
    var id: Int = 0
    var x: Int = 0
    var y: Int = 0
    var w: Int = 0
    var h: Int = 0
    var base: Int = 0
}

private let PLANKS: Int = 5
private let BRIDGE_W: Int = 13
private let OLD_POD_W: Int = 26
private let OLD_POD_H: Int = 16

private func box(_ id: Int, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ base: Int) -> PixelSeasonTwoBox {
    var b = PixelSeasonTwoBox()
    b.id = id
    b.x = x
    b.y = y
    b.w = w
    b.h = h
    b.base = base
    return b
}

private func bridgeBox(_ layout: PixelForestLayout) -> PixelSeasonTwoBox {
    let band = pixelCreekBand(layout)
    let x = pixelBridgeX(layout) - BRIDGE_W / 2
    return box(PIXEL_SEASON_BRIDGE, x, band[0] - 2, BRIDGE_W, band[1] - band[0] + 4, band[0] - 2)
}

/// The old pod sits on the far bank, just below where the bridge comes down.
private func oldPodBox(_ layout: PixelForestLayout) -> PixelSeasonTwoBox {
    let band = pixelCreekBand(layout)
    let base = band[1] + 34
    let x = pixelBridgeX(layout) - 8
    return box(PIXEL_SEASON_OLD_POD, x, base - OLD_POD_H, OLD_POD_W, OLD_POD_H, base)
}

/// Where the old pod's lamp shines from, once it works again.
func pixelOldPodLamp(_ layout: PixelForestLayout) -> [Int] {
    let b = oldPodBox(layout)
    return [b.x + 5, b.y - 4]
}

/// The creek's story things on screen now, for drawing and tapping.
func pixelSeasonTwoBoxes(_ layout: PixelForestLayout, _ look: PixelSeasonTwoLook) -> [PixelSeasonTwoBox] {
    var boxes: [PixelSeasonTwoBox] = []
    if look.planks > 0 { boxes.append(bridgeBox(layout)) }
    if look.oldPodFound { boxes.append(oldPodBox(layout)) }
    return boxes
}

/// Where Pibo kneels to nail the next plank, at the end of what is built so far.
func pixelBridgeWorkSpot(_ layout: PixelForestLayout, _ planks: Int) -> [Int] {
    let band = pixelCreekBand(layout)
    let reach = PixelMath.round(Double(band[1] - band[0] + 2) * Double(max(0, min(PLANKS, planks)))
                                / Double(PLANKS))
    return [pixelBridgeX(layout) - 10, band[0] - 2 + min(reach, 4)]
}

/// In front of the old pod's door.
func pixelOldPodSpot(_ layout: PixelForestLayout) -> [Int] {
    let b = oldPodBox(layout)
    return [b.x - 6, b.base + 2]
}

/// Far off in the trees behind the clearing, across the creek.
func pixelFarLightPoint(_ layout: PixelForestLayout) -> [Int] {
    [PixelMath.round(Double(layout.width) * 0.83), layout.treeBaseY - 12]
}

/// Shared with the antenna: the two lights blink on the same beat.
func pixelSeasonBlink(_ timeMs: Double, _ night: Bool) -> Bool {
    night ? PixelMath.floor(timeMs / 900) % 2 == 0 : PixelMath.floor(timeMs / 1800) % 3 == 0
}

// --- Bridge ----------------------------------------------------------------------------

private func drawBridge(_ frame: PixelFrame, _ layout: PixelForestLayout, _ look: PixelSeasonTwoLook) {
    let b = bridgeBox(layout)
    let span = b.h
    let laid = PixelMath.round(Double(span) * Double(max(0, min(PLANKS, look.planks))) / Double(PLANKS))
    // Posts at the near bank, and at the far bank once it reaches across.
    func post(_ x: Int, _ y: Int) {
        frame.fillRect(x, y - 4, x + 2, y + 1, .woodDark)
        frame.set(x, y - 4, .woodLight)
    }
    for row in 0..<laid {
        let y = b.y + row
        let board = row % 3
        for dx in 0..<BRIDGE_W {
            var ink: PixelInk = board == 0 ? .woodLight : (board == 1 ? .woodMid : .woodDark)
            if (dx == 1 || dx == BRIDGE_W - 2) && board == 1 { ink = .stoneDark }
            if look.snow && board == 0 { ink = .snow }
            frame.set(b.x + dx, y, ink)
        }
    }
    // The rope rails along both sides of what is laid.
    for row in 0..<laid where row % 2 == 0 {
        frame.set(b.x - 1, b.y + row, .line)
        frame.set(b.x + BRIDGE_W, b.y + row, .line)
    }
    post(b.x - 2, b.y + 1)
    post(b.x + BRIDGE_W, b.y + 1)
    if look.planks >= PLANKS {
        post(b.x - 2, b.y + span)
        post(b.x + BRIDGE_W, b.y + span)
    }
}

// --- The old pod -------------------------------------------------------------------------

private func wobble(_ look: PixelSeasonTwoLook, _ id: Int) -> Int {
    if look.poked != id || look.pokeAge < 0 || look.pokeAge > 600 { return 0 }
    return PixelMath.round(sin(Double(look.pokeAge) / 60) * 1.2)
}

private func drawOldPod(_ frame: PixelFrame, _ b: PixelSeasonTwoBox, _ look: PixelSeasonTwoLook) {
    let dx = wobble(look, PIXEL_SEASON_OLD_POD)
    PixelArt.drawShadow(frame, cx: Double(b.x) + Double(OLD_POD_W) / 2, y: Double(b.base),
                        halfW: Double(PixelMath.round(Double(OLD_POD_W) * 0.6)))
    let tilt = -0.28
    let rx = Double(OLD_POD_W) * 0.47
    let ry = Double(OLD_POD_H) * 0.42
    PixelArt.drawSticker(frame, x: Double(b.x + dx), y: Double(b.y), w: Double(OLD_POD_W),
                         h: Double(OLD_POD_H)) { t in
        // Older than Pibo's: tipped the other way, weathered, half grown over with moss.
        let cx = Double(OLD_POD_W) / 2
        let cy = Double(OLD_POD_H) / 2 + 0.5
        for y in 0..<OLD_POD_H {
            for x in 0..<OLD_POD_W {
                let px = Double(x) + 0.5 - cx
                let py = Double(y) + 0.5 - cy
                let u = (px * cos(tilt) + py * sin(tilt)) / rx
                let v = (-px * sin(tilt) + py * cos(tilt)) / ry
                if u * u + v * v > 1 { continue }
                var ink: PixelInk = .stoneDark
                if v < -0.4 && u > -0.3 { ink = .stone }
                if v > 0.5 { ink = .line }
                if (x * 7 + y * 3) % 11 == 0 { ink = .stone }
                // Moss over the top and down the left side.
                if v < -0.55 || (u < -0.6 && (x + y) % 2 == 0) || (v < -0.2 && (x * 5 + y) % 7 == 0) {
                    ink = .moss
                }
                if look.snow && v < -0.6 { ink = .snow }
                t.set(1 + x, 1 + y, ink)
            }
        }
        // A round, rimmed porthole, dark until the lamp works again, and the hatch beside it.
        t.stamp([".OOOO.", "OQWWQO", "OWWWWO", "OWWWWO", "OQWWQO", ".OOOO."], 14, 4)
        if look.oldPodLit { t.stamp(["yu", "uy"], 16, 6) }
        t.stamp(["OOOO", "O..O", "O..O", "O.yO", "OOOO"], 6, 6)
    }
    // Two stubby landing legs, the way Pibo's pod has them.
    frame.fillRect(b.x + 5 + dx, b.base - 1, b.x + 7 + dx, b.base + 1, .line)
    frame.fillRect(b.x + OLD_POD_W - 6 + dx, b.base - 2, b.x + OLD_POD_W - 4 + dx, b.base, .line)
    // Its lamp on a bent mast at the left shoulder.
    let lx = b.x + 6 + dx
    let ly = b.y + 3
    for k in 0..<6 { frame.set(lx + (k > 4 ? -1 : 0), ly - k, .stoneDark) }
    if look.oldPodLit {
        let on = pixelSeasonBlink(look.timeMs, look.night)
        frame.fillRect(lx - 2, ly - 8, lx + 1, ly - 6, on ? .glow : .sun)
        if on && look.night {
            frame.set(lx - 3, ly - 8, .sun)
            frame.set(lx + 1, ly - 7, .sun)
            frame.set(lx - 1, ly - 9, .sun)
        }
    } else {
        frame.fillRect(lx - 2, ly - 8, lx + 1, ly - 6, .stoneDark)
    }
}

/// Draws the bridge (always under Pibo) and the old pod by depth, in the creek scene.
func drawPixelSeasonTwo(_ frame: PixelFrame, _ layout: PixelForestLayout, _ look: PixelSeasonTwoLook,
                        _ feetY: Int, _ front: Bool) {
    let at = "\(layout.width)x\(layout.height)@\(layout.groundY)"
    if !front && look.planks > 0 {
        memo.draw(frame, key: "bridge|\(at)|\(look.planks)\(look.snow ? "s" : "")") { target in
            drawBridge(target, layout, look)
        }
    }
    if look.oldPodFound {
        let pod = oldPodBox(layout)
        if (pod.base > feetY) != front { return }
        let lit = look.oldPodLit
            ? "l\(pixelSeasonBlink(look.timeMs, look.night) ? 1 : 0)\(look.night ? "n" : "")" : ""
        memo.draw(frame, key: "oldPod|\(at)|\(look.snow ? "s" : "")\(wobble(look, PIXEL_SEASON_OLD_POD))\(lit)") { target in
            drawOldPod(target, pod, look)
        }
    }
}

private let memo = PixelMemo(capacity: 16)

/// From the clearing: the light far off in the trees, blinking with the antenna. Only
/// readable at night; by day it is a faint glint.
func drawPixelFarLight(_ frame: PixelFrame, _ layout: PixelForestLayout, _ look: PixelSeasonTwoLook) {
    if !look.farLight { return }
    let p = pixelFarLightPoint(layout)
    let on = pixelSeasonBlink(look.timeMs, look.night)
    if !on { return }
    if look.night {
        frame.set(p[0], p[1], .glow)
        frame.set(p[0] + 1, p[1], .glow)
        frame.set(p[0] - 1, p[1], .sun)
        frame.set(p[0] + 2, p[1], .sun)
        frame.set(p[0], p[1] - 1, .sun)
        frame.set(p[0] + 1, p[1] + 1, .sun)
    } else {
        frame.set(p[0], p[1], .sun)
    }
}

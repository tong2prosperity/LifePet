import Foundation

// The story's things in the clearing (decision 059, season one "落脚"): the pod Pibo
// landed in, the seed it planted and the mailbox letters arrive in. Which of them exist
// and how far the seed has grown come from Core; this file only places and draws them.
//
// Ported from HarmonyPibo `pixel/scene/PixelSeason.ets`.

let PIXEL_SEASON_POD: Int = 200
let PIXEL_SEASON_SPROUT: Int = 201
let PIXEL_SEASON_MAILBOX: Int = 202

struct PixelSeasonLook {
    /// The antenna is straight once the lost screw is back.
    var podFixed: Bool = false
    /// Core's sprout stage: 0 not planted, 1 mound … 5 sapling.
    var sprout: Int = 0
    /// 0 no mailbox yet, 1 empty, 2 a letter waiting (flag up).
    var mailbox: Int = 0
    var timeMs: Double = 0
    var night: Bool = false
    var snow: Bool = false
    /// The thing tapped last and how long ago, for its little wobble.
    var poked: Int = -1
    var pokeAge: Int = -1
}

struct PixelSeasonBox {
    var id: Int = 0
    var x: Int = 0
    var y: Int = 0
    var w: Int = 0
    var h: Int = 0
    /// Ground line, for drawing in front of or behind Pibo.
    var base: Int = 0
}

// Big enough for Pibo to curl up inside: about its own size.
private let POD_W: Int = 30
private let POD_H: Int = 18
private let POD_RX: Double = Double(POD_W) * 0.48
private let POD_RY: Double = Double(POD_H) * 0.42
/// The antenna's column, near the hull's right shoulder.
private let ANTENNA_X: Int = 21
private let SPROUT_W: Int = 11
private let SPROUT_H: [Int] = [0, 4, 7, 8, 11, 16]

private func seasonBox(_ id: Int, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ base: Int) -> PixelSeasonBox {
    var box = PixelSeasonBox()
    box.id = id
    box.x = x
    box.y = y
    box.w = w
    box.h = h
    box.base = base
    return box
}

/// Front left of the clearing, between the pond and the moss nest: the pod, the
/// mailbox on its right; the seed further right, past the campfire.
private func podBox(_ layout: PixelForestLayout) -> PixelSeasonBox {
    let x = PixelMath.round(Double(layout.width) * 0.21)
    let base = layout.groundY + 50
    return seasonBox(PIXEL_SEASON_POD, x, base - POD_H, POD_W, POD_H, base)
}

private func mailboxBox(_ layout: PixelForestLayout) -> PixelSeasonBox {
    let pod = podBox(layout)
    return seasonBox(PIXEL_SEASON_MAILBOX, pod.x + POD_W + 2, pod.base - 12, 6, 12, pod.base + 1)
}

private func sproutBox(_ layout: PixelForestLayout, _ stage: Int) -> PixelSeasonBox {
    let base = layout.groundY + 40
    let h = SPROUT_H[max(0, min(5, stage))]
    return seasonBox(PIXEL_SEASON_SPROUT, PixelMath.round(Double(layout.width) * 0.6) - 5, base - h,
                     SPROUT_W, h, base)
}

/// The story things on screen now, for drawing and tapping.
func pixelSeasonBoxes(_ layout: PixelForestLayout, _ look: PixelSeasonLook) -> [PixelSeasonBox] {
    var boxes: [PixelSeasonBox] = [podBox(layout)]
    if look.sprout > 0 { boxes.append(sproutBox(layout, look.sprout)) }
    if look.mailbox > 0 { boxes.append(mailboxBox(layout)) }
    return boxes
}

/// Where Pibo's feet go to work at a story thing: beside the pod's door, kneeling by
/// the seed, in front of the mailbox, and on the pod's roof to fix the antenna.
func pixelSeasonSpot(_ layout: PixelForestLayout, _ id: Int) -> [Int] {
    switch id {
    case PIXEL_SEASON_SPROUT:
        let box = sproutBox(layout, 1)
        return [box.x - 7, box.base]
    case PIXEL_SEASON_MAILBOX:
        let box = mailboxBox(layout)
        return [box.x + 12, box.base - 2]
    default:
        // Just behind the pod, so it stands at its pod with the hull in front of its feet.
        let box = podBox(layout)
        return [box.x + POD_W / 2, box.y + 4]
    }
}

/// Where Pibo stands to reach the antenna: right of it, so its body never hides the
/// antenna standing up. It reaches back to the left.
func pixelSeasonAntennaSpot(_ layout: PixelForestLayout) -> [Int] {
    let box = podBox(layout)
    return [box.x + POD_W + 13, box.base - 1]
}

/// The antenna's tip, where Pibo reaches to and the report goes.
func pixelSeasonAntennaTip(_ layout: PixelForestLayout) -> [Int] {
    let box = podBox(layout)
    return [box.x + ANTENNA_X, box.y + 1 + podHullTop(ANTENNA_X - 1) - 8]
}

private let POD_TILT: Double = 0.36

private func podInside(_ x: Int, _ y: Int) -> Bool {
    let px = Double(x) + 0.5 - Double(POD_W) / 2
    let py = Double(y) + 0.5 - (Double(POD_H) / 2 + 0.5)
    let u = (px * cos(POD_TILT) + py * sin(POD_TILT)) / POD_RX
    let v = (-px * sin(POD_TILT) + py * cos(POD_TILT)) / POD_RY
    return u * u + v * v <= 1
}

/// The first hull row in a column, so the antenna stands on the hull, not above it.
private func podHullTop(_ x: Int) -> Int {
    for y in 0..<POD_H {
        if podInside(x, y) { return y }
    }
    return 0
}

private func wobble(_ look: PixelSeasonLook, _ id: Int) -> Int {
    if look.poked != id || look.pokeAge < 0 || look.pokeAge > 600 { return 0 }
    return PixelMath.round(sin(Double(look.pokeAge) / 60) * 1.2)
}

// --- Pod -----------------------------------------------------------------------------

private func drawPod(_ frame: PixelFrame, _ box: PixelSeasonBox, _ look: PixelSeasonLook) {
    let dx = wobble(look, PIXEL_SEASON_POD)
    PixelArt.drawShadow(frame, cx: Double(box.x) + Double(POD_W) / 2 + 1, y: Double(box.base),
                        halfW: Double(PixelMath.round(Double(POD_W) * 0.55)))
    PixelArt.drawSticker(frame, x: Double(box.x + dx), y: Double(box.y), w: Double(POD_W),
                         h: Double(POD_H)) { t in
        // A capsule tipped forward: an ellipse turned by ~20°, lit from the upper left.
        let cx = Double(POD_W) / 2
        let cy = Double(POD_H) / 2 + 0.5
        let cosT = cos(POD_TILT)
        let sinT = sin(POD_TILT)
        for y in 0..<POD_H {
            for x in 0..<POD_W {
                let px = Double(x) + 0.5 - cx
                let py = Double(y) + 0.5 - cy
                let u = (px * cosT + py * sinT) / POD_RX
                let v = (-px * sinT + py * cosT) / POD_RY
                let d = u * u + v * v
                if d > 1 { continue }
                var ink: PixelInk = .stone
                if v < -0.45 && u < 0.3 { ink = .stoneLight }
                if v > 0.45 || (u > 0.55 && v > 0) { ink = .stoneDark }
                // A band of rivets round the middle.
                if abs(v - 0.1) < 0.12 { ink = (x % 3 == 0) ? .stoneLight : .stoneDark }
                if look.snow && v < -0.55 { ink = .snow }
                t.set(1 + x, 1 + y, ink)
            }
        }
        // Porthole on the left, the half-open door on the right.
        t.stamp([".QQQ.", "QZZzQ", "QZzzQ", "QzzzQ", ".QQQ."], 6, 4)
        t.set(8, 5, .cloudLight)
        for y in 5..<15 { t.set(19 + (y - 5) / 3, y, .line) }
        for y in 6..<14 {
            t.set(20 + (y - 5) / 3, y, .eye)
            t.set(21 + (y - 5) / 3, y, .eye)
        }
    }
    // Half sunk in a ring of dug-up dirt.
    for x in (-1)...(POD_W + 1) {
        let edge = Double(abs(x - POD_W / 2)) / (Double(POD_W) / 2 + 1)
        frame.set(box.x + x, box.base - 1, edge > 0.85 ? .pathMid : .pathDark)
        if edge < 0.8 {
            frame.set(box.x + x, box.base - 2, (x % 4 == 1) ? .pathMid : .pathDark)
        }
        if edge < 0.6 && x % 3 == 0 { frame.set(box.x + x, box.base - 3, .pathMid) }
    }
    // The antenna: bent over until the screw is back, then straight with a light at the tip.
    let ax = box.x + ANTENNA_X + dx
    let ay = box.y + 1 + podHullTop(ANTENNA_X - 1)
    if look.podFixed {
        // Two pixels wide with a lit face, and a 2×2 lamp on top: readable at phone size.
        for k in 1...6 {
            frame.set(ax, ay - k, .stoneLight)
            frame.set(ax + 1, ay - k, .stoneDark)
        }
        // The same beat as the old pod's lamp across the creek (season two).
        let blink = pixelSeasonBlink(look.timeMs, look.night)
        frame.fillRect(ax, ay - 8, ax + 2, ay - 6, blink ? .glow : .sun)
        if blink && look.night {
            frame.fillRect(ax - 1, ay - 8, ax, ay - 6, .sun)
            frame.fillRect(ax + 2, ay - 8, ax + 3, ay - 6, .sun)
            frame.fillRect(ax, ay - 9, ax + 2, ay - 8, .sun)
        }
    } else {
        // Bent over to the right, drooping.
        let bent: [[Int]] = [[0, 1], [0, 2], [0, 3], [1, 4], [2, 4], [3, 4], [4, 3], [4, 2]]
        for p in bent {
            frame.set(ax + p[0], ay - p[1], .stoneDark)
            frame.set(ax + p[0] + 1, ay - p[1], .stone)
        }
        frame.set(ax + 5, ay - 1, .stoneDark)
    }
}

/// The pod alone, for a picture outside the stage (the settings panel's header). `base` is
/// the ground line under it.
func drawPixelPodAt(_ frame: PixelFrame, _ x: Int, _ base: Int, _ look: PixelSeasonLook) {
    var box = PixelSeasonBox()
    box.id = PIXEL_SEASON_POD
    box.x = x
    box.y = base - POD_H
    box.w = POD_W
    box.h = POD_H
    box.base = base
    drawPod(frame, box, look)
}

/// Where the fixed antenna's lamp sits for a pod drawn by drawPixelPodAt.
func pixelPodTipAt(_ x: Int, _ base: Int) -> [Int] {
    [x + ANTENNA_X, base - POD_H + 1 + podHullTop(ANTENNA_X - 1) - 8]
}

// --- Sprout --------------------------------------------------------------------------

private let SPROUT_ART: [[String]] = [
    [],
    ["..TTTT..", ".TUUUUT.", "UUUUUUUU", "VVVVVVVV"],
    ["....l...", "...lg...", "....G...", "....G...", ".TUUUUT.", "UUUUUUUU", "VVVVVVVV"],
    [".ll..gg.", "lllggggg", "..l.G.g.", "....G...", "....G...", ".TUUUUT.", "UUUUUUUU", "VVVVVVVV"],
    ["....l...", "...llg..", "...lgg..", ".ll.Ggg.", "lllgGggg", "..l.G.g.", "....G...", "....G...",
     ".TUUUUT.", "UUUUUUUU", "VVVVVVVV"]
]

private func drawSprout(_ frame: PixelFrame, _ box: PixelSeasonBox, _ look: PixelSeasonLook) {
    let stage = max(1, min(5, look.sprout))
    let sway = wobble(look, PIXEL_SEASON_SPROUT)
    PixelArt.drawShadow(frame, cx: Double(box.x) + Double(SPROUT_W) / 2, y: Double(box.base),
                        halfW: Double(stage >= 5 ? 6 : 4))
    if stage < 5 {
        let art = SPROUT_ART[stage]
        let top = box.base - art.count
        PixelArt.drawSticker(frame, x: Double(box.x + 1 + sway), y: Double(top), w: 8,
                             h: Double(art.count)) { t in
            t.stamp(art, 1, 1)
            if look.snow { t.set(4, 1, .snow) }
        }
        return
    }
    // A sapling: a thin trunk and its first little crown.
    PixelArt.drawSticker(frame, x: Double(box.x), y: Double(box.y), w: Double(SPROUT_W),
                         h: Double(SPROUT_H[5])) { t in
        for k in 0..<8 {
            t.set(6 + (Double(k) > 5 ? sway : 0), 15 - k, k < 2 ? .woodDark : .trunk)
        }
        t.set(7, 10, .leafMid)
        t.set(8, 9, .leafLight)
        PixelArt.drawFoliage(t, cx: 6 + sway, cy: 5, rx: 4, ry: 3,
                             inks: [.leafDark, .leafMid, .leafLight], seed: 59)
        if look.snow {
            t.set(5 + sway, 2, .snow)
            t.set(6 + sway, 2, .snow)
            t.set(7 + sway, 2, .snow)
        }
    }
    frame.stamp([".TUUUUT.", "UUUUUUUU", "VVVVVVVV"], box.x + 2, box.base - 3)
}

// --- Mailbox -------------------------------------------------------------------------

private func drawMailbox(_ frame: PixelFrame, _ box: PixelSeasonBox, _ look: PixelSeasonLook) {
    let dy = wobble(look, PIXEL_SEASON_MAILBOX)
    PixelArt.drawShadow(frame, cx: Double(box.x) + 3, y: Double(box.base - 1), halfW: 3)
    PixelArt.drawSticker(frame, x: Double(box.x), y: Double(box.y + dy), w: 6, h: 12) { t in
        t.stamp([".dddd.", "dMMMMd", "MOOOOM", "MMMMMM", ".DDDD."], 1, 1)
        for k in 6..<12 {
            t.set(3, k + 1, .woodDark)
            t.set(4, k + 1, .woodMid)
        }
        if look.snow { t.stamp([".iiii."], 1, 1) }
    }
    // The flag: up when a letter is waiting.
    let fx = box.x + 6
    if look.mailbox >= 2 {
        for k in 0..<5 { frame.set(fx, box.y + dy + 4 - k, .woodDark) }
        frame.fillRect(fx + 1, box.y + dy, fx + 3, box.y + dy + 2, .berry)
    } else {
        frame.fillRect(fx, box.y + dy + 3, fx + 3, box.y + dy + 4, .woodDark)
        frame.set(fx + 2, box.y + dy + 2, .berry)
    }
}

/// Draws the story things whose ground line is behind Pibo's feet (`front` false) or in
/// front of them (`front` true), so Pibo can walk round them.
func drawPixelSeason(_ frame: PixelFrame, _ layout: PixelForestLayout, _ look: PixelSeasonLook,
                     _ feetY: Int, _ front: Bool) {
    for box in pixelSeasonBoxes(layout, look) {
        if (box.base > feetY) != front { continue }
        memo.draw(frame, key: "s\(box.id)@\(box.x),\(box.y),\(box.base)|\(seasonLook(box.id, look))") { target in
            switch box.id {
            case PIXEL_SEASON_POD: drawPod(target, box, look)
            case PIXEL_SEASON_SPROUT: drawSprout(target, box, look)
            default: drawMailbox(target, box, look)
            }
        }
    }
}

nonisolated(unsafe) private let memo = PixelMemo(capacity: 16)

/// Everything one story thing's picture depends on besides where it stands.
private func seasonLook(_ id: Int, _ look: PixelSeasonLook) -> String {
    let base = "\(look.snow ? "s" : "")\(wobble(look, id))"
    switch id {
    case PIXEL_SEASON_POD:
        let lit = look.podFixed
            ? "f\(pixelSeasonBlink(look.timeMs, look.night) ? 1 : 0)\(look.night ? "n" : "")" : ""
        return "\(base)|\(lit)"
    case PIXEL_SEASON_SPROUT: return "\(base)|\(look.sprout)"
    default: return "\(base)|\(look.mailbox)"
    }
}

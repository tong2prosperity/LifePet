import Foundation

// Decorations around the clearing (decision 057). Core owns which ones exist, their cost
// and level gates; this file owns where each one stands and how it looks. Health-driven
// details (flowers, windmill speed, moon lamp) arrive as Core's body-cue answers.
//
// Ported from HarmonyPibo `pixel/scene/PixelDecor.ets`.

/// Core decor ids 0–9, plus the two legacy ornaments, the scene's own hotspots and (from
/// 18) the creek's and the hill's own pieces (decision 065), whose Core ids 10–12 were
/// already taken here: map with pixelDecorFromCore / pixelDecorToCore.
enum PixelDecorID: Int, CaseIterable {
    case mushroomStool = 0
    case nameSign = 1
    case stonePile = 2
    case flowerBed = 3
    case windmill = 4
    case moonLamp = 5
    case pond = 6
    case swing = 7
    case campfire = 8
    case tent = 9
    case hammock = 10
    case observer = 11
    case grass = 12
    case cake = 13
    // Shared-first markers (056 timeline): 14 + TimelineFirst raw value.
    case firstPat = 14
    case firstBo = 15
    case firstHammock = 16
    case firstMeal = 17
    case boat = 18
    case kite = 19
    case telescope = 20
}

/// The pixel id for a Core decor id, or −1.
func pixelDecorFromCore(_ core: Int) -> Int {
    if core >= PixelDecorID.mushroomStool.rawValue && core <= PixelDecorID.tent.rawValue { return core }
    if core >= 10 && core <= 12 { return PixelDecorID.boat.rawValue + core - 10 }
    return -1
}

/// The Core decor id for a pixel id, or −1 (ornaments, hotspots and markers have none).
func pixelDecorToCore(_ id: Int) -> Int {
    if id >= PixelDecorID.mushroomStool.rawValue && id <= PixelDecorID.tent.rawValue { return id }
    if id >= PixelDecorID.boat.rawValue && id <= PixelDecorID.telescope.rawValue {
        return id - PixelDecorID.boat.rawValue + 10
    }
    return -1
}

private let FIRST_MARKER_BASE: Int = PixelDecorID.firstPat.rawValue

struct PixelDecorScene {
    /// Raw `PixelDecorID` values Core says are owned.
    var owned: [Int] = []
    var hammock: Bool = false
    var observer: Bool = false
    var grass: Bool = true
    var cake: Bool = false
    var flowers: Int = 0
    var footprints: Int = 0
    var windmillSpeed: Int = 0
    var moonLamp: Int = 0
    var stones: Int = 1
    var dayCount: Int = 1
    var sleepingInHammock: Bool = false
    /// Pibo is on the swing: the seat follows Pibo's sway instead of idling (decision 058).
    var swingBusy: Bool = false
    var swingSway: Int = 0
    /// A tap spins the windmill hard for a moment.
    var windmillBoost: Bool = false
    /// Core's beetle trace: how many are out, the white dot, resting on the leaf.
    var beetles: Int = 0
    var beetleSpot: Bool = false
    var beetleOnLeaf: Bool = false
    /// Core's TimelineFirst bits that get a marker.
    var firstMarkers: Int = 0
    /// Pibo is flying the kite: only the stake stays on the ground (drawPixelKiteFlight
    /// draws the kite up in the sky, on a string from `kiteHand`).
    var kiteFlying: Bool = false
    var kiteHand: [Int] = [0, 0]
    var mood: PixelMood = .day
    var timeMs: Double = 0
}

struct PixelDecorBox {
    var id: PixelDecorID = .grass
    var x: Int = 0
    var y: Int = 0
    var w: Int = 0
    var h: Int = 0
}

private struct Slot {
    let fx: Double
    let dy: Int
    let w: Int
    let h: Int
    let back: Bool
}

// x as a fraction of width from the centre, y from Pibo's ground line (feet). `back`
// items stand behind Pibo. Width/height are the art's bounding box for hit testing.
private let SLOTS: [Slot] = [
    Slot(fx: -0.2, dy: 4, w: 11, h: 9, back: false), // mushroom stool
    Slot(fx: 0.2, dy: 2, w: 15, h: 15, back: false), // name sign
    Slot(fx: -0.33, dy: 3, w: 15, h: 11, back: false), // stone pile
    Slot(fx: 0.26, dy: 20, w: 21, h: 9, back: false), // flower bed
    Slot(fx: -0.27, dy: -12, w: 15, h: 28, back: true), // windmill
    Slot(fx: 0.43, dy: 0, w: 7, h: 21, back: false), // moon lamp
    Slot(fx: -0.26, dy: 24, w: 27, h: 10, back: false), // pond
    Slot(fx: 0.41, dy: -14, w: 19, h: 23, back: true), // swing
    Slot(fx: -0.02, dy: 34, w: 13, h: 11, back: false), // campfire
    Slot(fx: -0.4, dy: -12, w: 25, h: 19, back: true), // tent
    Slot(fx: 0.25, dy: -12, w: 29, h: 16, back: true), // hammock
    Slot(fx: 0.34, dy: 6, w: 9, h: 16, back: false), // observer
    Slot(fx: -0.43, dy: 18, w: 9, h: 7, back: false), // grass tuft
    Slot(fx: 0.13, dy: 2, w: 9, h: 9, back: false), // anniversary cake
    Slot(fx: -0.36, dy: 46, w: 5, h: 8, back: false), // first pat
    Slot(fx: -0.12, dy: 48, w: 5, h: 8, back: false), // first bo
    Slot(fx: 0.12, dy: 48, w: 5, h: 8, back: false), // first hammock night
    Slot(fx: 0.36, dy: 46, w: 5, h: 8, back: false), // first meal
    // Decision 065: the creek's and the hill's own pieces, in their own scene's coordinates.
    Slot(fx: -0.03, dy: 25, w: 31, h: 11, back: false), // boat, moored on the creek
    Slot(fx: -0.2, dy: 0, w: 15, h: 14, back: false), // kite and its stake, on the hill
    Slot(fx: 0.2, dy: -30, w: 15, h: 22, back: false) // telescope, on the hilltop
]

/// Top-left of a decoration's art in the clearing, for places that stand next to it.
func pixelDecorOrigin(_ layout: PixelForestLayout, _ id: PixelDecorID) -> [Int] {
    slotOrigin(layout, id)
}

private func slotOrigin(_ layout: PixelForestLayout, _ id: PixelDecorID) -> [Int] {
    let slot = SLOTS[id.rawValue]
    let cx = PixelMath.round(Double(layout.width) / 2 + slot.fx * Double(layout.width))
    let bottom = layout.groundY + slot.dy
    return [cx - slot.w / 2, bottom - slot.h]
}

private func present(_ scene: PixelDecorScene, _ id: PixelDecorID) -> Bool {
    switch id {
    case .hammock: return scene.hammock
    case .observer: return scene.observer
    case .grass: return scene.grass
    case .cake: return scene.cake
    case .firstPat, .firstBo, .firstHammock, .firstMeal:
        return ((scene.firstMarkers >> (id.rawValue - FIRST_MARKER_BASE)) & 1) == 1
    default: return scene.owned.contains(id.rawValue)
    }
}

// --- Art (decision 058 polish) ---------------------------------------------------------------
// Each piece is painted into a sticker (see PixelArt): its own three-step shading inside one
// soft outline, standing on a soft shadow. Stamps carry no shadow rows of their own.

private let STOOL: [String] = [
    "...ccccc...",
    ".ccwcccccc.",
    "cwwcccwcccC",
    "cccccccwcCC",
    "CCCCCCCCCCC",
    "..JjjjjJ...",
    "...jjjJ....",
    "...jjjJ....",
    "..jjjjjJ..."
]
private let STONE_BIG: [String] = [".LLq.", "Lqqqq", "qqqqQ", "qqqQQ", ".QQQ."]
private let STONE_SMALL: [String] = [".Lq.", "LqqQ", "qqQQ"]
private let MOON_LAMP_HEAD: [String] = ["..HHH..", ".HHHHH.", "D.....D", "D.yuy.D", "D.yyy.D",
                                        "D.yyy.D", ".DDDDD."]
private let MOON_LAMP_OFF: [String] = ["..HHH..", ".HHHHH.", "D.....D", "D.LqL.D", "D.qqq.D",
                                       "D.qqQ.D", ".DDDDD."]
private let MOON_LAMP_DIM: [String] = ["..HHH..", ".HHHHH.", "D.....D", "D.KkK.D", "D.KKK.D",
                                       "D.KKK.D", ".DDDDD."]
private let CAKE: [String] = ["....x....", "....y....", "..jjjjj..", ".jfjfjfj.", ".jjjjjjj.",
                              ".hhhhhhh.", ".jjjjjjj.", ".hhhhhhh.", ".HHHHHHH."]
private let OBSERVER: [String] = [
    "..QQQQQ..",
    ".QLLLLqQ.",
    "QL.....qQ",
    "QL.y.y.qQ",
    "QL..y..qQ",
    "QL.y.y.qQ",
    "Qq.....QQ",
    ".QqqqqQQ.",
    "..QQQQQ..",
    "....M....",
    "....M....",
    "...dMD...",
    "..d.M.D..",
    ".d..M..D.",
    "d...M...D",
    "D...D...D"
]
private let LOGS: [String] = [".D.......D.", "..MddddMD..", ".MdDMdDMdD.", "dDMdDMdDMdD"]
private let RING: [String] = [".LqQ.....LqQ.", "qqQ.......qqQ"]
// 7 and 8 are flickering inks: the flame's body trades core and glow between shape changes.
private let FLAME_A: [String] = ["....x....", "...x7x...", "..x78Xx..", ".xX8u87x.", ".x7y8yXx.",
                                 "..xX7Xx.."]
private let FLAME_B: [String] = ["...x.....", "...xx.x..", "..x7Xxx..", ".x78u8Xx.", ".xXy8y7x.",
                                 "..x7XXx.."]
private let TUFT_A: [String] = ["E.G.E.G.E", ".gGgGgGg.", "..GgGgG.."]
private let TUFT_B: [String] = [".E.G.E.G.", "E.gGgGg.E", "..GgGgG.."]
private let FROG: [String] = ["l.l", "lel", "lll"]
private let LILY: [String] = [".gggG", "gglgG", ".GGG."]
private let MARKER_POST: [String] = ["..M..", "..M..", "..D..", "..D.."]
private let MARKER_HEADS: [[String]] = [
    [".b.b.", "bbbbb", ".bbb.", "..b.."], // first pat: a heart
    ["...gg", ".gglg", "gglg.", ".gG.."], // first bo: a leaf
    [".KK..", "KK...", "KK...", ".KK.."], // first hammock night: a moon
    ["f.F.f", "hhhhh", ".hhh.", "....."] // first meal: a bowl
]
private let BEETLE: [String] = [".ee.", "eeee", "e..e"]
private let BEETLE_SPOT: [String] = [".ee.", "ewee", "e..e"]
private let BEETLE_STEP: [String] = [".ee.", "eeee", ".ee."]
private let BEETLE_SPOT_STEP: [String] = [".ee.", "ewee", ".ee."]
private let FALLEN_LEAF: [String] = ["...gggg..", ".gglggggG", "gggggggG.", ".GGGGG..."]
private let WILD_FLOWER_A: [String] = [".f.", "fuf", ".g."]
private let WILD_FLOWER_B: [String] = [".F.", "FuF", ".g."]
private let BED_FLOWER_A: [String] = [".f.", "fuf", "gf.", ".gl"]
private let BED_FLOWER_B: [String] = [".F.", "FuF", "lFg", ".g."]
private let BED_FLOWER_C: [String] = [".6.", "6u6", ".6g", "lg."]
private let KITE: [String] = ["...c...", "..cjc..", ".ccjcC.", "cjjjjjC", ".ccjCC.", "..cjC..",
                              "...C..."]
private let KITE_SPOOL: [String] = [".DD.", "dMMD", ".DD."]

private func nightish(_ mood: PixelMood) -> Bool {
    mood == .night || mood == .dusk
}

// The time steps each piece moves on. Drawing and the memo key both read them, so a piece
// is only repainted when its picture can actually change.
private func windmillPhase(_ scene: PixelDecorScene) -> Int {
    // Blades turn faster the more active minutes today (Core's windmill tier).
    let periods: [Int] = [0, 900, 450, 220]
    let period = scene.windmillBoost ? 110 : periods[max(0, min(3, scene.windmillSpeed))]
    return period > 0 ? PixelMath.floor(scene.timeMs / Double(period)) % 2 : 0
}

private func pondRipple(_ scene: PixelDecorScene) -> Int {
    PixelMath.floor(scene.timeMs / 700) % 4
}

private func frogUp(_ scene: PixelDecorScene) -> Bool {
    PixelMath.floor(scene.timeMs / 5000) % 3 != 2
}

private func swingSway(_ scene: PixelDecorScene) -> Int {
    scene.swingBusy ? scene.swingSway : PixelMath.round(sin(scene.timeMs / 900) * 1.5)
}

private func flameA(_ scene: PixelDecorScene) -> Bool {
    PixelMath.floor(scene.timeMs / 200) % 2 == 0
}

private func emberA(_ scene: PixelDecorScene) -> Bool {
    PixelMath.floor(scene.timeMs / 350) % 3 == 0
}

private func emberB(_ scene: PixelDecorScene) -> Bool {
    PixelMath.floor(scene.timeMs / 470) % 4 == 1
}

private func tuftA(_ scene: PixelDecorScene) -> Bool {
    PixelMath.floor(scene.timeMs / 800) % 2 == 0
}

private func boatBob(_ scene: PixelDecorScene) -> Int {
    PixelMath.floor(scene.timeMs / 900) % 2
}

private func kiteDrift(_ timeMs: Double) -> [Int] {
    // A slow figure of eight, two pixels each way, and a tail that flicks every other step.
    let step = PixelMath.floor(timeMs / 300)
    let path: [[Int]] = [[0, 0], [1, -1], [2, -1], [1, 0], [0, 1], [-1, 1], [-2, 0], [-1, -1]]
    let at = path[step % path.count]
    return [at[0], at[1], step % 2]
}

private func drawBoat(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    // A little rowboat: lit gunwale, a red stripe, the hull narrowing to the keel, an oar
    // resting across. It rides the water a pixel up and down.
    let top = y + boatBob(scene)
    let last = 28
    let rows: [[Int]] = [[0, last, PixelInk.woodLight.index], [0, last, PixelInk.woodMid.index],
                         [1, last - 1, PixelInk.scarf.index], [2, last - 2, PixelInk.woodMid.index],
                         [4, last - 4, PixelInk.woodDark.index], [7, last - 7, PixelInk.woodDark.index]]
    for (r, row) in rows.enumerated() {
        for col in row[0]...row[1] {
            var ink = PixelInk(rawValue: UInt8(clamping: row[2])) ?? .woodMid
            if r == 2 && (col == row[0] || col == row[1]) { ink = .scarfShade }
            if r == 0 && (col == 0 || col == last) { ink = .woodDark }
            // Planks: a seam every seventh board on the hull.
            if r == 3 && col % 7 == 3 { ink = .woodDark }
            frame.set(x + col, top + 2 + r, ink)
        }
    }
    frame.set(x + 1, top + 1, .woodDark)
    frame.set(x + last - 1, top + 1, .woodDark)
    // An oar resting across the stern, its blade in the water.
    for i in 0..<6 {
        frame.set(x + last - 8 + i, top + i - 1 + (i > 4 ? 1 : 0), .woodDark)
    }
    frame.fillRect(x + last - 3, top + 5, x + last, top + 6, .woodMid)
}

private func drawKiteGround(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    // The stake and its spool; the kite leans against it until Pibo takes it up.
    frame.fillRect(x + 10, y + 3, x + 11, y + 12, .woodMid)
    frame.fillRect(x + 11, y + 3, x + 12, y + 12, .woodDark)
    frame.stamp(KITE_SPOOL, x + 9, y + 6)
    if scene.kiteFlying { return }
    frame.stamp(KITE, x, y)
    // The tail curls down the grass.
    frame.set(x + 3, y + 7, .clothShade)
    frame.set(x + 4, y + 8, .blush)
    frame.set(x + 4, y + 9, .clothShade)
    frame.set(x + 5, y + 10, .flowerA)
    frame.set(x + 6, y + 11, .clothShade)
    frame.set(x + 7, y + 11, .clothShade)
}

private func drawTelescope(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    // Brass-and-steel tube pointing up to the right on a wooden tripod.
    for i in 0..<10 {
        let tx = x + 1 + i
        let ty = y + 7 - PixelMath.floor(Double(i) * 0.6)
        frame.set(tx, ty, i < 2 ? .line : .stoneLight)
        frame.set(tx, ty + 1, i < 2 ? .line : .stone)
        frame.set(tx, ty + 2, .stoneDark)
    }
    // The wide end, and a glint in its glass after dark.
    frame.fillRect(x + 11, y, x + 13, y + 4, .stoneDark)
    frame.set(x + 11, y, .stoneLight)
    if nightish(scene.mood) { frame.set(x + 12, y + 1, .glow) }
    frame.fillRect(x + 5, y + 6, x + 7, y + 8, .woodDark)
    // Legs tall enough to bring the eyepiece up to Pibo's eye.
    for r in 0..<12 {
        frame.set(x + 5 - PixelMath.floor(Double(r) * 0.4), y + 8 + r, .woodMid)
        frame.set(x + 6, y + 8 + r, .woodDark)
        frame.set(x + 7 + PixelMath.floor(Double(r) * 0.4), y + 8 + r, .woodMid)
    }
}

/// The kite up in the sky on its string while Pibo flies it (after everything else).
func drawPixelKiteFlight(_ frame: PixelFrame, _ scene: PixelDecorScene) {
    if !scene.kiteFlying { return }
    let drift = kiteDrift(scene.timeMs)
    let hx = scene.kiteHand[0]
    let hy = scene.kiteHand[1]
    let kx = hx - 26 + drift[0]
    let ky = hy - 58 + drift[1]
    // The string sags a little on its way up.
    let steps = 40
    for i in 1..<steps {
        let t = Double(i) / Double(steps)
        let sx = PixelMath.round(Double(hx) + Double(kx + 3 - hx) * t)
        let sy = PixelMath.round(Double(hy) + Double(ky + 6 - hy) * t + sin(t * Double.pi) * 5)
        frame.set(sx, sy, .clothShade)
    }
    frame.stamp(KITE, kx, ky)
    let flick = drift[2]
    let tail: [[Int]] = [[3, 7], [4 + flick, 8], [4, 9], [5 + flick, 10], [5, 11], [6 + flick, 12]]
    for (i, p) in tail.enumerated() {
        frame.set(kx + p[0], ky + p[1], i % 3 == 2 ? .blush : (i == 4 ? .flowerA : .clothShade))
    }
}

private func drawWindmill(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    // A wooden tower, lit on the left, planks every third row, a door and a red cap.
    for row in 9..<28 {
        let half = 2 + (row - 9) / 6
        for dx in (-half)...half {
            var ink: PixelInk = dx < 0 ? .woodLight : .woodMid
            if dx == half { ink = .woodDark }
            if row % 3 == 0 { ink = dx < 0 ? .woodMid : .woodDark }
            frame.set(x + 7 + dx, y + row, ink)
        }
    }
    frame.fillRect(x + 6, y + 24, x + 9, y + 28, .line)
    frame.set(x + 7, y + 15, .line)
    frame.fillRect(x + 4, y + 7, x + 11, y + 9, .scarf)
    frame.fillRect(x + 5, y + 6, x + 10, y + 7, .scarf)
    frame.fillRect(x + 8, y + 8, x + 11, y + 9, .scarfShade)
    let phase = windmillPhase(scene)
    let hubX = x + 7
    let hubY = y + 6
    let arms: [[Int]] = phase == 0 ? [[1, 0], [-1, 0], [0, 1], [0, -1]]
        : [[1, 1], [-1, -1], [1, -1], [-1, 1]]
    for arm in arms {
        let len = phase == 0 ? 6 : 5
        for r in 1...len {
            let px = hubX + arm[0] * r
            let py = hubY + arm[1] * r
            frame.set(px, py, .woodDark)
            if r > 1 {
                // The sail sits on one side of each arm, so the wheel reads as turning one way.
                let sx = px + (arm[1] != 0 ? -arm[1] : 0) + (phase == 1 ? arm[1] : 0)
                let sy = py + (arm[0] != 0 ? arm[0] : 0) - (phase == 1 ? arm[0] : 0)
                frame.set(sx, sy, r % 2 == 0 ? .cloth : .clothShade)
            }
        }
    }
    frame.set(hubX, hubY, .acornCap)
}

private func drawPond(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    let w = 27
    let h = 10
    for row in 0..<h {
        let ny = (Double(row) + 0.5 - Double(h) / 2) / (Double(h) / 2)
        let half = PixelMath.round(max(0, 1 - ny * ny).squareRoot() * (Double(w) / 2))
        let left = x + w / 2 - half
        for col in 0..<(half * 2) {
            let rim = col < 2 || col >= half * 2 - 2 || row == 0 || row == h - 1
            var ink: PixelInk = .water
            if row >= h - 4 { ink = .waterDeep }
            if row == 1 { ink = .waterLight }
            if rim {
                ink = Double(row) < Double(h) / 2
                    ? (col % 3 == 0 ? .stoneLight : .stone) : .stoneDark
            }
            frame.set(left + col, y + row, ink)
        }
    }
    let ripple = pondRipple(scene)
    frame.fillRect(x + 7 + ripple, y + 4, x + 10 + ripple, y + 5, .waterLight)
    frame.fillRect(x + 14 - ripple, y + 6, x + 16 - ripple, y + 7, .waterLight)
    // The frog sits on its pad most of the time and ducks under now and then.
    frame.stamp(LILY, x + 17, y + 4)
    frame.set(x + 6, y + 6, .flowerB)
    frame.stamp(["gG"], x + 5, y + 7)
    if frogUp(scene) { frame.stamp(FROG, x + 18, y + 1) }
}

private func drawSwing(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    // A-frame posts and a crossbar, lit on the left.
    for row in 1..<23 {
        let lean = row / 8
        frame.set(x + 1 + lean, y + row, .woodLight)
        frame.set(x + 2 + lean, y + row, .woodMid)
        frame.set(x + 16 - lean, y + row, .woodMid)
        frame.set(x + 17 - lean, y + row, .woodDark)
    }
    frame.fillRect(x, y, x + 19, y + 1, .woodLight)
    frame.fillRect(x, y + 1, x + 19, y + 2, .woodDark)
    let sway = swingSway(scene)
    for row in 2..<16 {
        let dx = PixelMath.round(Double(sway * row) / 14)
        frame.set(x + 5 + dx, y + row, .clothShade)
        frame.set(x + 13 + dx, y + row, .clothShade)
    }
    frame.fillRect(x + 4 + sway, y + 16, x + 15 + sway, y + 17, .woodLight)
    frame.fillRect(x + 4 + sway, y + 17, x + 15 + sway, y + 18, .woodDark)
}

private func drawHammock(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    for px in [x, x + 27] {
        frame.fillRect(px, y, px + 1, y + 16, .woodLight)
        frame.fillRect(px + 1, y, px + 2, y + 16, .woodDark)
        frame.fillRect(px - 1, y, px + 3, y + 1, .woodMid)
    }
    for col in 2..<27 {
        let sag = PixelMath.round(sin((Double(col - 2) / 24) * Double.pi) * 5)
        let stripe = (col - 2) / 3 % 2 == 0
        if col < 5 || col > 23 {
            frame.set(x + col, y + 2 + PixelMath.round(Double(sag) * 0.8), .clothShade)
            continue
        }
        frame.set(x + col, y + 3 + sag, stripe ? .scarf : .cloth)
        frame.set(x + col, y + 4 + sag, stripe ? .scarfShade : .clothShade)
    }
    if scene.sleepingInHammock { frame.fillRect(x + 9, y + 3, x + 20, y + 6, .bodyLight) }
}

private func drawFlowerBed(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    // A plank planter: soil on top, two boards with nail heads.
    frame.fillRect(x, y + 4, x + 21, y + 5, .acornCap)
    frame.fillRect(x, y + 5, x + 21, y + 7, .woodLight)
    frame.fillRect(x, y + 7, x + 21, y + 9, .woodMid)
    frame.fillRect(x, y + 8, x + 21, y + 9, .woodDark)
    for nx in [1, 10, 19] { frame.set(x + nx, y + 6, .woodDark) }
    // One bloom per thousand steps today, filling the bed left to right.
    let count = min(12, scene.flowers)
    let kinds: [[String]] = [BED_FLOWER_A, BED_FLOWER_B, BED_FLOWER_C]
    for i in 0..<6 {
        let fx = x + 1 + i * 3 + (i % 2)
        if i * 2 < count { frame.stamp(kinds[i % 3], fx, y) }
        else { frame.stamp([".g.", "lg."], fx, y + 2) }
        if i * 2 + 1 < count {
            frame.set(fx + 2, y + 1, i % 2 == 0 ? .flowerB : .flowerA)
        }
    }
}

private func drawMoonLamp(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    // Last night's sleep sets the brightness; an off lamp shows grey glass.
    frame.stamp(scene.moonLamp <= 0 ? MOON_LAMP_OFF
                    : (scene.moonLamp == 1 ? MOON_LAMP_DIM : MOON_LAMP_HEAD), x, y)
    frame.fillRect(x + 3, y + 7, x + 4, y + 20, .woodMid)
    frame.set(x + 2, y + 7, .woodDark)
    frame.fillRect(x + 1, y + 19, x + 6, y + 21, .woodDark)
    frame.fillRect(x + 2, y + 19, x + 4, y + 20, .woodLight)
}

// Glow is light on whatever is around the lamp, so it goes on after the sticker.
private func drawMoonLampGlow(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    if scene.moonLamp < 2 || !nightish(scene.mood) { return }
    let cx = x + 3
    let cy = y + 4
    for dy in (-9)...9 {
        for dx in (-9)...9 {
            let d = dx * dx + dy * dy
            if d < 16 || d > 81 { continue }
            frame.ditherPixel(Double(cx + dx), Double(cy + dy), frame.get(cx + dx, cy + dy), .glow,
                              0.32 * (1 - Double(d) / 81))
        }
    }
}

private func drawCampfire(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    frame.stamp(RING, x, y + 9)
    frame.stamp(LOGS, x + 1, y + 7)
    if !nightish(scene.mood) {
        frame.stamp(["..2..", ".2.2.", "..2.."], x + 4, y + 3)
        return
    }
    frame.stamp(flameA(scene) ? FLAME_A : FLAME_B, x + 2, y + 1)
}

private func drawCampfireGlow(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    if !nightish(scene.mood) { return }
    let cx = x + 6
    let cy = y + 9
    for dy in (-5)...6 {
        for dx in (-14)...14 {
            let d = Double(dx * dx) / 196 + Double(dy * dy) / 36
            if d > 1 || (abs(dx) < 7 && dy < 3 && dy > -9) { continue }
            frame.ditherPixel(Double(cx + dx), Double(cy + dy), frame.get(cx + dx, cy + dy), .glow,
                              0.28 * (1 - d))
        }
    }
    if emberA(scene) { frame.set(cx - 1, y - 2, .fireCore) }
    if emberB(scene) { frame.set(cx + 2, y - 4, .fire) }
}

private func drawTent(_ frame: PixelFrame, _ x: Int, _ y: Int) {
    let apex = x + 12
    let top = y + 2
    let rows = 16
    for r in 0..<rows {
        let half = PixelMath.round(1 + Double(r) * 0.72)
        for dx in (-half)...half {
            var ink: PixelInk = dx <= 0 ? .cloth : .clothShade
            if abs(dx) == half { ink = dx < 0 ? .scarf : .scarfShade }
            if r == rows - 1 { ink = dx <= 0 ? .scarf : .scarfShade }
            // The open door: a dark triangle with the flap folded back on the left.
            let doorWidth = PixelMath.round(Double(r - 5) * 0.48)
            let door = r > 5 && abs(dx) <= doorWidth && r < rows - 1
            if door { ink = dx == -doorWidth ? .clothShade : .line }
            frame.set(apex + dx, top + r, ink)
        }
    }
    frame.fillRect(apex, y, apex + 1, y + 3, .woodDark)
    frame.stamp(["ccc", "cC."], apex + 1, y)
    // Guy ropes and pegs.
    frame.set(x, y + rows + 1, .woodDark)
    frame.set(x + 24, y + rows + 1, .woodDark)
}

private func drawNameSign(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    drawPixelBoard(frame, x, y, 15, 9, 0)
    frame.fillRect(x + 6, y + 9, x + 7, y + 15, .woodMid)
    frame.fillRect(x + 7, y + 9, x + 8, y + 15, .woodDark)
    let text = "\(max(1, min(999, scene.dayCount)))"
    drawPixelText(frame, text, x + 8 - pixelTextWidth(text) / 2, y + 2, .woodDark, .clear)
}

private func drawStonePile(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    // Core's stone count: one more each time Pibo tells a step of the stone thread.
    let positions: [[Int]] = [[0, 6, 1], [5, 6, 1], [10, 7, 0], [2, 2, 1], [7, 3, 0], [4, -1, 0],
                              [10, 3, 0], [-1, 3, 0]]
    let count = max(1, min(positions.count, scene.stones))
    for i in 0..<count {
        frame.stamp(positions[i][2] == 1 ? STONE_BIG : STONE_SMALL, x + positions[i][0] + 1,
                    y + positions[i][1])
    }
}

private func drawGrass(_ frame: PixelFrame, _ x: Int, _ y: Int, _ scene: PixelDecorScene) {
    frame.stamp(tuftA(scene) ? TUFT_A : TUFT_B, x, y + 3)
    frame.stamp(["..E..", ".gGg."], x + 2, y + 1)
}

/// A painted wooden board: wood frame, cream face, shaded bottom. `point` −1/+1 cuts an
/// arrow tip on that side; 0 keeps it square.
func drawPixelBoard(_ frame: PixelFrame, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ point: Int) {
    let tip = point == 0 ? 0 : Int((Double(h) / 2).rounded(.up))
    let mid = Double(h - 1) / 2
    for row in 0..<h {
        for col in 0..<w {
            let fromTip = point > 0 ? w - 1 - col : col
            if tip > 0 && fromTip < tip
                && abs(Double(row) - mid) > Double(fromTip) + 0.5 { continue }
            let edge = row == 0 || row == h - 1 || (point <= 0 && col == w - 1)
                || (point >= 0 && col == 0)
                || (tip > 0 && fromTip < tip && abs(Double(row) - mid) > Double(fromTip) - 0.6)
            var ink: PixelInk = .signFace
            if row == h - 2 { ink = .clothShade }
            if edge { ink = row == 0 ? .woodLight : (row == h - 1 ? .woodDark : .woodMid) }
            frame.set(x + col, y + row, ink)
        }
    }
}

private func drawFootprints(_ frame: PixelFrame, _ layout: PixelForestLayout,
                            _ scene: PixelDecorScene) {
    // A winding path from the bottom edge toward Pibo; Core says how many segments today.
    let segments = max(0, min(15, scene.footprints))
    let startX = Double(layout.width) * 0.18
    let startY = Double(layout.height) - 6
    let endX = Double(layout.width) * 0.5 - 14
    let endY = Double(layout.groundY) + 6
    for i in 0..<segments {
        let t = (Double(i) + 0.5) / 15
        let px = PixelMath.round(startX + (endX - startX) * t + sin(t * Double.pi * 3) * 8)
        let py = PixelMath.round(startY + (endY - startY) * t)
        let side = i % 2 == 0 ? -1 : 1
        frame.fillRect(px + side, py, px + side + 2, py + 1, .groundShadow)
        frame.set(px + side, py - 1, .groundShadow)
    }
}

private func drawWildFlowers(_ frame: PixelFrame, _ layout: PixelForestLayout,
                             _ scene: PixelDecorScene) {
    let count = max(0, min(12, scene.flowers))
    let rng = PixelRandom(4817)
    for i in 0..<12 {
        let side = i % 2 == 0 ? -1 : 1
        let x = PixelMath.round(Double(layout.width) / 2
                                + Double(side) * rng.range(22, Double(layout.width) * 0.46))
        let y = PixelMath.round(Double(layout.groundY) + rng.range(8, 46))
        if i < count { frame.stamp(i % 3 == 0 ? WILD_FLOWER_B : WILD_FLOWER_A, x, y) }
    }
}

private func drawOne(_ frame: PixelFrame, _ layout: PixelForestLayout, _ scene: PixelDecorScene,
                     _ id: PixelDecorID) {
    let origin = slotOrigin(layout, id)
    drawOneAt(frame, scene, id, origin[0], origin[1])
}

private func paintOne(_ frame: PixelFrame, _ scene: PixelDecorScene, _ id: PixelDecorID,
                      _ x: Int, _ y: Int) {
    switch id {
    case .mushroomStool: frame.stamp(STOOL, x, y)
    case .nameSign: drawNameSign(frame, x, y, scene)
    case .stonePile: drawStonePile(frame, x, y, scene)
    case .flowerBed: drawFlowerBed(frame, x, y, scene)
    case .windmill: drawWindmill(frame, x, y, scene)
    case .moonLamp: drawMoonLamp(frame, x, y, scene)
    case .pond: drawPond(frame, x, y, scene)
    case .swing: drawSwing(frame, x, y, scene)
    case .campfire: drawCampfire(frame, x, y, scene)
    case .tent: drawTent(frame, x, y)
    case .hammock: drawHammock(frame, x, y, scene)
    case .observer: frame.stamp(OBSERVER, x, y)
    case .cake: frame.stamp(CAKE, x, y)
    case .boat: drawBoat(frame, x, y, scene)
    case .kite: drawKiteGround(frame, x, y, scene)
    case .telescope: drawTelescope(frame, x, y, scene)
    case .firstPat, .firstBo, .firstHammock, .firstMeal:
        frame.stamp(MARKER_HEADS[id.rawValue - FIRST_MARKER_BASE], x, y)
        frame.stamp(MARKER_POST, x, y + 4)
    default: break
    }
}

// Shadow half-widths per piece; 0 casts none (the grass tuft, the pond, hanging things).
private let SHADOWS: [Int] = [5, 4, 7, 10, 6, 3, 0, 9, 7, 12, 0, 4, 0, 4, 2, 2, 2, 2, 0, 3, 5]

// Caches are main-thread only, like ArkTS's single UI thread.
private let memo = PixelMemo(capacity: 48)

/// Everything a piece's picture depends on besides where it stands.
private func decorLook(_ scene: PixelDecorScene, _ id: PixelDecorID) -> String {
    let night = nightish(scene.mood) ? "n" : "d"
    switch id {
    case .nameSign: return "\(scene.dayCount)"
    case .stonePile: return "\(scene.stones)"
    case .flowerBed: return "\(scene.flowers)"
    case .windmill: return "\(windmillPhase(scene))"
    case .moonLamp: return "\(scene.moonLamp)\(night)"
    case .pond: return "\(pondRipple(scene))\(frogUp(scene) ? "f" : "")"
    case .swing: return "\(swingSway(scene))"
    case .campfire:
        return "\(night)\(flameA(scene) ? "a" : "b")\(emberA(scene) ? 1 : 0)\(emberB(scene) ? 1 : 0)"
    case .hammock: return scene.sleepingInHammock ? "z" : ""
    case .grass: return tuftA(scene) ? "a" : "b"
    case .boat: return "\(boatBob(scene))"
    case .kite: return scene.kiteFlying ? "f" : ""
    case .telescope: return night
    default: return ""
    }
}

private func drawOneAt(_ frame: PixelFrame, _ scene: PixelDecorScene, _ id: PixelDecorID,
                       _ x: Int, _ y: Int) {
    memo.draw(frame, key: "d\(id.rawValue)@\(x),\(y)|\(decorLook(scene, id))") { target in
        paintOneAt(target, scene, id, x, y)
    }
}

private func paintOneAt(_ frame: PixelFrame, _ scene: PixelDecorScene, _ id: PixelDecorID,
                        _ x: Int, _ y: Int) {
    if id == .grass {
        drawGrass(frame, x, y, scene)
        return
    }
    let slot = SLOTS[id.rawValue]
    let shadow = SHADOWS[id.rawValue]
    if shadow > 0 {
        PixelArt.drawShadow(frame, cx: Double(x) + Double(slot.w) / 2,
                            y: Double(y + slot.h - 1), halfW: Double(shadow))
    }
    PixelArt.drawSticker(frame, x: Double(x), y: Double(y), w: Double(slot.w), h: Double(slot.h)) { target in
        paintOne(target, scene, id, 1, 1)
    }
    if id == .moonLamp { drawMoonLampGlow(frame, x, y, scene) }
    if id == .campfire { drawCampfireGlow(frame, x, y, scene) }
}

// The beetle from Pibo's story, near Pibo's feet. It crawls a few pixels back and forth in
// stepped motion; once Pibo leaves them a leaf, the pair rests on it.
private func drawBeetles(_ frame: PixelFrame, _ layout: PixelForestLayout, _ scene: PixelDecorScene) {
    if scene.beetles <= 0 { return }
    let cx = PixelMath.round(Double(layout.width) / 2)
    let groundY = layout.groundY
    let step = PixelMath.floor(scene.timeMs / 450)
    let legs = step % 2 == 0
    let body = scene.beetleSpot ? (legs ? BEETLE_SPOT : BEETLE_SPOT_STEP)
        : (legs ? BEETLE : BEETLE_STEP)
    if scene.beetleOnLeaf {
        let leafX = cx + 14
        let leafY = groundY + 6
        frame.stamp(FALLEN_LEAF, leafX, leafY)
        frame.stamp(body, leafX + 1, leafY - 2)
        if scene.beetles > 1 { frame.stamp(BEETLE, leafX + 5, leafY - 2, flip: step % 6 < 3) }
        return
    }
    // Triangle wave over 12 steps: 0..6..0 pixels.
    let phase = step % 12
    let drift = phase <= 6 ? phase : 12 - phase
    frame.stamp(body, cx + 15 + drift, groundY + 6, flip: phase > 6)
    if scene.beetles > 1 { frame.stamp(BEETLE, cx + 22 + drift, groundY + 9, flip: phase > 6) }
}

private let BACK_ORDER: [PixelDecorID] = [.tent, .windmill, .hammock, .swing]
private let FRONT_ORDER: [PixelDecorID] = [.moonLamp, .stonePile, .mushroomStool, .nameSign,
                                           .observer, .cake, .pond, .flowerBed, .grass, .campfire,
                                           .firstPat, .firstBo, .firstHammock, .firstMeal,
                                           .telescope, .kite, .boat]

private func slotBottom(_ layout: PixelForestLayout, _ id: PixelDecorID) -> Int {
    layout.groundY + SLOTS[id.rawValue].dy
}

/// Everything that stands behind Pibo: the back row, and front items whose bottom is not
/// below Pibo's feet (decision 058: Pibo walks, so depth follows its feet line).
func drawPixelDecorBack(_ frame: PixelFrame, _ layout: PixelForestLayout, _ scene: PixelDecorScene,
                        _ feetY: Int? = nil) {
    let feet = feetY ?? layout.groundY
    drawFootprints(frame, layout, scene)
    if !scene.owned.contains(PixelDecorID.flowerBed.rawValue) {
        drawWildFlowers(frame, layout, scene)
    }
    for id in BACK_ORDER where present(scene, id) {
        drawOne(frame, layout, scene, id)
    }
    for id in FRONT_ORDER where present(scene, id) && slotBottom(layout, id) <= feet {
        drawOne(frame, layout, scene, id)
    }
}

/// Everything below Pibo's feet line, drawn over Pibo.
func drawPixelDecorFront(_ frame: PixelFrame, _ layout: PixelForestLayout, _ scene: PixelDecorScene,
                         _ feetY: Int? = nil) {
    let feet = feetY ?? layout.groundY
    for id in FRONT_ORDER where present(scene, id) && slotBottom(layout, id) > feet {
        drawOne(frame, layout, scene, id)
    }
    drawBeetles(frame, layout, scene)
}

/// Lights the clearing's lit pieces cast after dark, as [x, y, radius]: the campfire
/// (breathing with its flicker) and a full moon lamp.
func pixelDecorLights(_ layout: PixelForestLayout, _ scene: PixelDecorScene) -> [[Int]] {
    if !nightish(scene.mood) { return [] }
    var lights: [[Int]] = []
    if present(scene, .campfire) {
        let o = slotOrigin(layout, .campfire)
        lights.append([o[0] + 6, o[1] + 9, flameA(scene) ? 24 : 23])
    }
    if present(scene, .moonLamp) && scene.moonLamp >= 2 {
        let o = slotOrigin(layout, .moonLamp)
        lights.append([o[0] + 3, o[1] + 6, 13])
    }
    return lights
}

/// Tap targets in logical pixels, padded for fingers.
func pixelDecorHitBoxes(_ layout: PixelForestLayout, _ scene: PixelDecorScene) -> [PixelDecorBox] {
    var boxes: [PixelDecorBox] = []
    for raw in PixelDecorID.mushroomStool.rawValue...PixelDecorID.telescope.rawValue {
        guard let id = PixelDecorID(rawValue: raw) else { continue }
        if !present(scene, id) { continue }
        let origin = slotOrigin(layout, id)
        let slot = SLOTS[raw]
        var box = PixelDecorBox()
        box.id = id
        box.x = origin[0] - 3
        box.y = origin[1] - 3
        box.w = slot.w + 6
        box.h = slot.h + 6
        boxes.append(box)
    }
    return boxes
}

/// Where a decoration's art sits, for camera-free previews in the catalog sheet.
func pixelDecorSize(_ id: PixelDecorID) -> [Int] {
    let slot = SLOTS[id.rawValue]
    return [slot.w, slot.h]
}

/// Draws one decoration with its top-left at (x, y) — the catalog's thumbnails.
func drawPixelDecorAt(_ frame: PixelFrame, _ id: PixelDecorID, _ x: Int, _ y: Int,
                      _ scene: PixelDecorScene) {
    drawOneAt(frame, scene, id, x, y)
}

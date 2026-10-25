import Foundation

// The shapes Pibo takes (decision 061). Every form is made of Pibo itself — the same
// white body with grey shading — and keeps its two eyes and the bo leaf on top, so you
// can always tell it is Pibo. Forms are drawn from simple shapes into a scratch frame,
// then stamped with one outline like every other prop, mirrored when facing left.
//
// Ported from HarmonyPibo `pixel/character/PiboPixelForms.ets`.

/// Decision 061: shapes Pibo can take (Core `PiboForm`). Declared here because the Swift
/// twin of `models/PiboDayValues.ets` does not exist yet; move it there when it does.
enum PiboForm: Int {
    case none = 0
    case stone = 1
    case mushroom = 2
    case bike = 3
    case fish = 4
    case sapling = 5
    case spring = 6
    case pillow = 7
    case lamp = 8
    case bowl = 9
    case sneaker = 10
}

/// How a form is drawn this frame.
final class PiboFormLook {
    var form: PiboForm = .none
    var timeMs: Double = 0
    /// -1 faces left; forms face right by default.
    var facing: Double = 0
    /// Getting about: wheels turn, the sneaker hops, the spring bounces.
    var moving: Bool = false
    /// Cannot change back: it wriggles and sweats.
    var stuck: Bool = false
    var night: Bool = false
    var reduceMotion: Bool = false
    // Decision 062: the badge stays on whatever it becomes.
    var badge: PiboPixelBadge = .none
    var badgeCracked: Bool = false
    var badgeLit: Bool = true
    /// Decision 065's hide in disguise: 1 is Pibo, face hidden except for a peek now and
    /// then; 2 a look-alike, which has no face, leaf or badge at all.
    var disguise: Int = 0
}

private func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }
private func jsRoundInt(_ x: Double) -> Int { Int(jsRound(x)) }
private func jsFloor(_ x: Double) -> Int { Int(x.rounded(.down)) }
private func jsCeil(_ x: Double) -> Int { Int(x.rounded(.up)) }

/// A disguised Pibo peeks (eyes open, leaf up) for a moment every few seconds.
private func peeking(_ look: PiboFormLook) -> Bool {
    return look.disguise == 1 && (look.reduceMotion || look.timeMs.truncatingRemainder(dividingBy: 4200) < 520)
}

private struct FormArt {
    var w: Int = 0
    var h: Int = 0
    var eyeX: Int = 0
    var eyeY: Int = 0
    var eyeSpacing: Int = 3
    var eyesClosed: Bool = false
    var leafX: Int = 0
    var leafY: Int = 0
    var leafLength: Int = 7
    var leafAngle: Double = 0.06
}

private enum FormScratch {
    static var frames: [String: PixelFrame] = [:]
}

private func scratch(_ w: Int, _ h: Int) -> PixelFrame {
    let key = "\(w)x\(h)"
    var frame = FormScratch.frames[key]
    if frame == nil {
        frame = PixelFrame(w, h)
        FormScratch.frames[key] = frame
    }
    frame!.clear(.clear)
    return frame!
}

// MARK: - Shapes

/// A filled oval; the lower part takes `shade`.
private func oval(_ t: PixelFrame, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double,
                  _ fill: PixelInk, _ shade: PixelInk, _ shadeFrom: Double = 0.45) {
    for y in jsFloor(cy - ry)...jsCeil(cy + ry) {
        for x in jsFloor(cx - rx)...jsCeil(cx + rx) {
            let dx = (Double(x) - cx) / (rx + 0.5)
            let dy = (Double(y) - cy) / (ry + 0.5)
            if dx * dx + dy * dy > 1 { continue }
            t.set(x, y, Double(y) - cy > ry * shadeFrom ? shade : fill)
        }
    }
}

private func ring(_ t: PixelFrame, _ cx: Int, _ cy: Int, _ r: Int, _ ink: PixelInk) {
    for y in (cy - r - 1)...(cy + r + 1) {
        for x in (cx - r - 1)...(cx + r + 1) {
            let dx = Double(x - cx)
            let dy = Double(y - cy)
            let d = (dx * dx + dy * dy).squareRoot()
            if d > Double(r) - 0.7 && d < Double(r) + 0.5 { t.set(x, y, ink) }
        }
    }
}

private func line(_ t: PixelFrame, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ ink: PixelInk) {
    let steps = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in 0...steps {
        let x = jsRoundInt(Double(x0) + Double(x1 - x0) * Double(i) / Double(steps))
        let y = jsRoundInt(Double(y0) + Double(y1 - y0) * Double(i) / Double(steps))
        t.set(x, y, ink)
    }
}

// MARK: - Forms

private func stone(_ t: PixelFrame, _ art: inout FormArt) {
    art.w = 24
    art.h = 13
    oval(t, 12, 7, 11, 5.5, .stone, .stoneDark, 0.35)
    t.fillRect(6, 3, 9, 4, .stoneLight)
    t.set(5, 4, .stoneLight)
    art.eyeX = 12
    art.eyeY = 7
    art.eyeSpacing = 4
    art.leafX = 12
    art.leafY = 2
    art.leafLength = 10
    art.leafAngle = 0.25
}

private func mushroom(_ t: PixelFrame, _ art: inout FormArt) {
    art.w = 26
    art.h = 25
    // White stem with grey shading on its right side.
    t.fillRect(8, 12, 19, 24, .bodyLight)
    t.fillRect(16, 12, 19, 24, .bodyMid)
    t.fillRect(9, 23, 18, 24, .bodyMid)
    // Red cap with white spots, grey gills underneath.
    oval(t, 13, 9, 12, 7.5, .scarf, .scarfShade, 0.6)
    t.fillRect(1, 12, 26, 13, .bodyMid)
    for y in 13..<18 { t.fillRect(0, y, 26, y + 1, .clear) }
    let spots: [[Int]] = [[6, 5], [16, 3], [11, 8], [20, 8], [3, 9]]
    for s in spots { t.fillRect(s[0], s[1], s[0] + 2, s[1] + 2, .bodyLight) }
    t.fillRect(8, 13, 19, 18, .bodyLight)
    t.fillRect(16, 13, 19, 18, .bodyMid)
    art.eyeX = 13
    art.eyeY = 17
    art.eyeSpacing = 3
    art.leafX = 13
    art.leafY = 2
    art.leafLength = 10
}

private func bike(_ t: PixelFrame, _ art: inout FormArt, _ look: PiboFormLook) {
    art.w = 34
    art.h = 22
    let turn = look.moving && !look.reduceMotion ? jsFloor(look.timeMs / 90) % 2 : 0
    let wheels: [[Int]] = [[7, 14], [27, 14]]
    for c in wheels {
        ring(t, c[0], c[1], 6, .line)
        ring(t, c[0], c[1], 5, .bodyShade)
        if turn == 0 {
            line(t, c[0] - 3, c[1], c[0] + 3, c[1], .bodyMid)
            line(t, c[0], c[1] - 3, c[0], c[1] + 3, .bodyMid)
        } else {
            line(t, c[0] - 2, c[1] - 2, c[0] + 2, c[1] + 2, .bodyMid)
            line(t, c[0] - 2, c[1] + 2, c[0] + 2, c[1] - 2, .bodyMid)
        }
        t.set(c[0], c[1], .bodyShade)
    }
    // Frame: rear hub, crank, saddle post, fork.
    line(t, 7, 14, 16, 14, .bodyShade)
    line(t, 16, 14, 13, 9, .bodyShade)
    line(t, 13, 9, 7, 14, .bodyShade)
    line(t, 16, 14, 24, 7, .bodyShade)
    line(t, 24, 5, 27, 14, .bodyShade)
    // Handlebar and bell.
    line(t, 24, 5, 26, 3, .bodyShade)
    t.fillRect(25, 3, 29, 4, .bodyShade)
    t.fillRect(28, 1, 30, 3, .sun)
    // Pedal.
    t.fillRect(15 + turn * 2, 15 - turn, 18 + turn * 2, 16 - turn, .bodyMid)
    // The saddle is Pibo's body.
    oval(t, 14, 5, 7, 4.5, .bodyLight, .bodyMid, 0.4)
    art.eyeX = 15
    art.eyeY = 5
    art.eyeSpacing = 3
    art.leafX = 13
    art.leafY = 1
    art.leafLength = 10
    art.leafAngle = look.moving ? -0.55 : 0.06
}

private func fish(_ t: PixelFrame, _ art: inout FormArt, _ look: PiboFormLook) {
    art.w = 31
    art.h = 16
    let wag = look.reduceMotion ? 0 : (jsFloor(look.timeMs / 220) % 2 == 0 ? -1 : 1)
    // Tail fans out away from the body.
    for x in 1...7 {
        let half = jsRoundInt(Double(8 - x) * 0.75) + 1
        for y in (8 - half + wag)...(8 + half + wag) {
            t.set(x, y, x <= 2 ? .bodyMid : .bodyLight)
        }
    }
    oval(t, 18, 8, 11, 6, .bodyLight, .bodyMid, 0.4)
    // A dorsal fin and a side fin.
    t.fillRect(15, 1, 19, 2, .bodyMid)
    t.fillRect(14, 2, 20, 3, .bodyMid)
    line(t, 15, 10, 17, 12, .bodyShade)
    // Mouth.
    t.set(29, 9, .bodyShade)
    art.eyeX = 23
    art.eyeY = 7
    art.eyeSpacing = 2
    art.leafX = 19
    art.leafY = 2
    art.leafLength = 9
    art.leafAngle = 0.35
}

private func sapling(_ t: PixelFrame, _ art: inout FormArt, _ look: PiboFormLook) {
    art.w = 28
    art.h = 32
    let sway = look.reduceMotion ? 0 : jsFloor(look.timeMs / 600) % 2
    // A white trunk, its arms up as two branches with a few leaves each.
    oval(t, 14, 21, 5, 10, .bodyLight, .bodyMid, 0.6)
    t.fillRect(17, 13, 19, 30, .bodyMid)
    line(t, 10, 17, 4, 9 + sway, .bodyMid)
    line(t, 18, 17, 24, 9 - sway, .bodyMid)
    let clusters: [[Int]] = [[2, 6 + sway], [22, 6 - sway], [6, 11], [19, 11]]
    for c in clusters {
        t.fillRect(c[0], c[1], c[0] + 4, c[1] + 3, .leafMid)
        t.fillRect(c[0] + 1, c[1], c[0] + 3, c[1] + 1, .leafLight)
        t.set(c[0] + 3, c[1] + 2, .leafDark)
    }
    // Roots.
    t.fillRect(8, 30, 11, 31, .bodyMid)
    t.fillRect(17, 30, 20, 31, .bodyMid)
    art.eyeX = 14
    art.eyeY = 18
    art.eyeSpacing = 2
    art.leafX = 14
    art.leafY = 11
    art.leafLength = 13
    art.leafAngle = sway == 0 ? 0.06 : -0.06
}

private func spring(_ t: PixelFrame, _ art: inout FormArt, _ look: PiboFormLook) {
    art.w = 18
    art.h = 28
    let phase = look.reduceMotion ? 0 : sin(look.timeMs / 140)
    let gap = jsRoundInt(3 + phase)
    let coils = 4
    let bottom = 26
    for k in 0..<coils {
        let y = bottom - k * gap
        line(t, 3, y, 14, y - 1, .bodyShade)
        line(t, 4, y - 1, 13, y - 2, .bodyMid)
    }
    let top = bottom - coils * gap
    oval(t, 9, Double(top - 3), 7, 5, .bodyLight, .bodyMid, 0.4)
    art.eyeX = 9
    art.eyeY = top - 3
    art.eyeSpacing = 3
    art.leafX = 9
    art.leafY = top - 8
    art.leafLength = 9
}

private func pillow(_ t: PixelFrame, _ art: inout FormArt) {
    art.w = 32
    art.h = 15
    oval(t, 16, 8, 15, 6, .bodyLight, .bodyMid, 0.5)
    t.fillRect(2, 4, 30, 12, .bodyLight)
    t.fillRect(2, 11, 30, 13, .bodyMid)
    // Pointed corners and a seam.
    let corners: [[Int]] = [[0, 2], [31, 2], [0, 13], [31, 13]]
    for c in corners { t.fillRect(c[0], c[1], c[0] + 1, c[1] + 1, .bodyMid) }
    t.fillRect(1, 3, 2, 4, .bodyLight)
    t.fillRect(30, 3, 31, 4, .bodyLight)
    t.fillRect(1, 12, 2, 13, .bodyMid)
    t.fillRect(30, 12, 31, 13, .bodyMid)
    art.eyeX = 16
    art.eyeY = 8
    art.eyeSpacing = 4
    art.eyesClosed = true
    art.leafX = 16
    art.leafY = 3
    art.leafLength = 10
    art.leafAngle = -1.0
}

private func lamp(_ t: PixelFrame, _ art: inout FormArt, _ look: PiboFormLook) {
    art.w = 18
    art.h = 27
    ring(t, 9, 3, 2, .woodDark)
    t.fillRect(4, 5, 15, 7, .woodDark)
    t.fillRect(5, 4, 14, 5, .woodMid)
    // The glass is Pibo, glowing.
    t.fillRect(4, 7, 15, 21, .glow)
    t.fillRect(6, 9, 13, 18, look.night ? .sun : .bodyLight)
    t.fillRect(12, 8, 14, 20, look.night ? .glow : .bodyMid)
    t.fillRect(3, 7, 4, 21, .woodDark)
    t.fillRect(15, 7, 16, 21, .woodDark)
    t.fillRect(4, 21, 15, 24, .woodDark)
    t.fillRect(5, 21, 14, 22, .woodMid)
    art.eyeX = 9
    art.eyeY = 14
    art.eyeSpacing = 3
    art.leafX = 13
    art.leafY = 4
    art.leafLength = 9
    art.leafAngle = 0.55
}

private func bowl(_ t: PixelFrame, _ art: inout FormArt) {
    art.w = 28
    art.h = 19
    // A mound of rice on top.
    oval(t, 14, 7, 10, 5, .snow, .snowShade, 0.5)
    // The bowl is Pibo: white, shaded below, a blue band near the foot.
    for y in 8...17 {
        let k = Double(y - 8) / 10
        let half = jsRoundInt(13 * max(0, 1 - k * k).squareRoot())
        for x in (14 - half)...(14 + half) {
            t.set(x, y, y >= 15 ? .bodyMid : .bodyLight)
        }
    }
    t.fillRect(1, 8, 28, 9, .bodyMid)
    t.fillRect(6, 15, 23, 16, .water)
    t.fillRect(10, 18, 19, 19, .bodyShade)
    art.eyeX = 14
    art.eyeY = 12
    art.eyeSpacing = 4
    art.leafX = 14
    art.leafY = 3
    art.leafLength = 9
}

private func sneaker(_ t: PixelFrame, _ art: inout FormArt) {
    art.w = 32
    art.h = 17
    // Upper: high at the heel, sloping down to the toe.
    for x in 2...29 {
        let top = x <= 11 ? 2 : jsRoundInt(2 + Double(x - 11) * 0.38)
        let end = x >= 27 ? 12 - (x - 27) : 12
        if top <= end {
            for y in top...end { t.set(x, y, y >= 11 ? .bodyMid : .bodyLight) }
        }
    }
    // The opening at the heel, the laces and a sole.
    t.fillRect(3, 2, 10, 4, .bodyShade)
    for x in [14, 17, 20] {
        let slope = jsRoundInt(2 + Double(x - 11) * 0.38)
        line(t, x, slope + 1, x + 1, slope + 3, .line)
    }
    t.fillRect(1, 13, 31, 15, .bodyShade)
    t.fillRect(2, 15, 30, 16, .bodyMid)
    art.eyeX = 23
    art.eyeY = 10
    art.eyeSpacing = 2
    art.leafX = 6
    art.leafY = 2
    art.leafLength = 11
    art.leafAngle = -0.2
}

private func paint(_ t: PixelFrame, _ art: inout FormArt, _ look: PiboFormLook) {
    switch look.form {
    case .stone: stone(t, &art)
    case .mushroom: mushroom(t, &art)
    case .bike: bike(t, &art, look)
    case .fish: fish(t, &art, look)
    case .sapling: sapling(t, &art, look)
    case .spring: spring(t, &art, look)
    case .pillow: pillow(t, &art)
    case .lamp: lamp(t, &art, look)
    case .bowl: bowl(t, &art)
    case .sneaker: sneaker(t, &art)
    default: break
    }
}

/// Width and height of a form, for hit areas and bubbles.
func piboFormSize(_ form: PiboForm) -> [Int] {
    let look = PiboFormLook()
    look.form = form
    var art = FormArt()
    paint(scratch(40, 40), &art, look)
    return [art.w, art.h]
}

/// How high the form is off the ground this frame: the sneaker hops, the spring bounces.
private func formLift(_ look: PiboFormLook) -> Int {
    if look.reduceMotion { return 0 }
    if look.form == .sneaker && look.moving {
        return abs(jsRoundInt(sin(look.timeMs / 160) * 3))
    }
    if look.form == .spring { return max(0, jsRoundInt(sin(look.timeMs / 140) * 4)) }
    return 0
}

// Decision 062: where the badge's top-left corner sits on each form (art coordinates), on
// a flat part of the thing and clear of the eyes and the leaf.
private let BADGE_SPOTS: [[Int]] = [[0, 0], [4, 6], [11, 19], [15, 11], [11, 6], [12, 21], [0, 0],
                                    [24, 7], [7, 21], [12, 14], [10, 9]]

private func badgeSpot(_ form: PiboForm, _ art: FormArt) -> [Int] {
    // The spring's head rides on its coils, so the badge follows the eyes.
    if form == .spring { return [art.eyeX + 3, art.eyeY - 1] }
    let index = form.rawValue
    if index >= 0 && index < BADGE_SPOTS.count { return BADGE_SPOTS[index] }
    return [art.eyeX, art.eyeY + 2]
}

/// Draws Pibo in `look.form`, standing on groundY and centred on cx.
func drawPiboForm(_ frame: PixelFrame, _ cx: Double, _ groundY: Double, _ look: PiboFormLook) {
    let t = scratch(40, 40)
    var art = FormArt()
    // Paint at (1, 1) so the outline has room.
    let inner = scratch(38, 38)
    paint(inner, &art, look)
    for y in 0..<art.h {
        for x in 0..<art.w { t.set(x + 1, y + 1, inner.get(x, y)) }
    }
    let face = look.disguise == 0 || peeking(look)
    if face {
        drawPiboPixelEyesAt(t, Double(art.eyeX + 1), Double(art.eyeY + 1), Double(art.eyeSpacing),
                            closed: art.eyesClosed, squeezed: look.stuck)
    }
    // Pinned where a badge would go on that thing; it mirrors with the form.
    let spot = badgeSpot(look.form, art)
    if look.disguise == 0 {
        drawPiboPixelBadgeAt(t, Double(spot[0] + 1), Double(spot[1] + 1), look.badge,
                             look.badgeCracked, look.badgeLit)
    }
    let flip = look.facing < 0
    let wriggle = look.stuck && !look.reduceMotion ? (jsFloor(look.timeMs / 140) % 2 == 0 ? -1 : 1) : 0
    let lift = formLift(look)
    let ox = jsRoundInt(cx - Double(art.w) / 2) - 1 + wriggle
    let oy = jsRoundInt(groundY - Double(art.h) - Double(lift)) - 1
    PixelArt.drawShadow(frame, cx: cx, y: groundY,
                        halfW: max(4, jsRound(Double(art.w) * 0.42 - Double(lift))))
    let sw = art.w + 2
    let sh = art.h + 2
    for py in 0..<sh {
        for px in 0..<sw {
            let ink = t.get(px, py)
            let dx = flip ? sw - 1 - px : px
            if ink != .clear {
                frame.set(ox + dx, oy + py, ink)
                continue
            }
            let touches = t.get(px - 1, py) != .clear || t.get(px + 1, py) != .clear
                || t.get(px, py - 1) != .clear || t.get(px, py + 1) != .clear
            if touches { frame.set(ox + dx, oy + py, .line) }
        }
    }
    // The leaf grows out of whatever it has become (a hiding Pibo tucks it in between peeks).
    if !face { return }
    let leafX = flip ? sw - 1 - (art.leafX + 1) : art.leafX + 1
    drawPiboPixelLeafAt(frame, Double(ox + leafX), Double(oy + art.leafY + 1), Double(art.leafLength),
                        flip ? -art.leafAngle : art.leafAngle)
    if look.stuck {
        // A sweat drop beside it.
        let side = flip ? ox - 2 : ox + sw + 1
        frame.set(side, oy + 3, .waterLight)
        frame.fillRect(side - 1, oy + 4, side + 1, oy + 6, .water)
    }
}

/// The puff of a change: a ring of little clouds that swells and thins out. `progress`
/// runs 0 → 1 over one puff.
func drawPiboPoof(_ frame: PixelFrame, _ cx: Double, _ centerY: Double, _ progress: Double) {
    let p = max(0, min(1, progress))
    let radius = 9 + p * 15
    let puffs = 10
    // Each puff has a grey rim so it reads over Pibo's white body.
    for pass in 0..<2 {
        for i in 0..<puffs {
            let angle = Double(i) * Double.pi * 2 / Double(puffs) + p * 0.8
            let px = jsRoundInt(cx + cos(angle) * radius)
            let py = jsRoundInt(centerY + sin(angle) * radius * 0.75)
            let size = max(1, jsRoundInt(5 * (1 - p * 0.7))) + (pass == 0 ? 1 : 0)
            for y in (-size)...size {
                for x in (-size)...size {
                    if x * x + y * y > size * size { continue }
                    let ink: PixelInk = pass == 0
                        ? .bodyShade
                        : (Double(y) > Double(size) / 3 ? .cloudShade : .cloudLight)
                    if p > 0.7 {
                        frame.ditherPixel(Double(px + x), Double(py + y), frame.get(px + x, py + y),
                                          ink, (1 - p) * 3.3)
                    } else {
                        frame.set(px + x, py + y, ink)
                    }
                }
            }
        }
    }
    if p < 0.5 {
        // A burst of sparkles in the middle at the start.
        let s = jsRoundInt(3 + p * 10)
        frame.set(cx - Double(s), centerY, .glow)
        frame.set(cx + Double(s), centerY, .glow)
        frame.set(cx, centerY - Double(s), .glow)
        frame.set(cx, centerY + Double(s), .glow)
    }
}

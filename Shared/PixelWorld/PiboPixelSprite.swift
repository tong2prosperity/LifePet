import Foundation

// Pibo as pixels, drawn to read like the original character art: a pure white mochi with
// no dark outline, small dark dot eyes under grey brow dots, a grey two-lobe muzzle,
// light grey U-line arms, two white foot bumps — and the head leaf, which is the `bo`.
//
// Ported from HarmonyPibo `pixel/character/PiboPixelSprite.ets`. Every table, threshold
// and formula is kept identical so both platforms draw the same picture.

enum PiboPixelEyes: Int {
    case open = 0
    case happy = 1
    case closed = 2
    case sleepy = 3
    case dot = 4
    case wink = 5
    case star = 6
    case dizzy = 7
    // Decision 060's feelings.
    /// Round and wide: surprised.
    case wide = 8
    /// > < squeezed shut: shy, sneezing.
    case squint = 9
    /// One wide, one a dot: puzzled.
    case uneven = 10
}

/// The little mouth under the muzzle (the original has none; it opens only for feelings).
enum PiboPixelMouth: Int {
    case none = 0
    /// A small round "o": surprised.
    case open = 1
    /// Tongue out: hot, panting.
    case tongue = 2
    /// A big yawn.
    case yawn = 3
    /// Corners down: sulking.
    case frown = 4
    /// Chewing a bite.
    case chew = 5
}

/// What a life echo puts in Pibo's hands.
enum PiboPixelProp: Int {
    case none = 0
    /// A big leaf, fanned up and down.
    case fan = 1
    /// A rolled leaf cup of water.
    case cup = 2
    /// One berry.
    case berry = 3
    /// A mushroom on a stick, held out to the fire.
    case skewer = 4
    /// A folded map held up in front.
    case map = 5
    /// A little lantern.
    case lantern = 6
    /// A small hammer, for the bridge planks.
    case hammer = 7
    /// A wooden plank under one arm.
    case plank = 8
    /// The old notebook, open.
    case notebook = 9
}

enum PiboPixelSprout: Int {
    case upright = 0
    case droop = 1
    case flat = 2
}

enum PiboPixelArms: Int {
    case rest = 0
    case up = 1
    case flex = 2
    case hug = 3
    /// Hands on hips, elbows out.
    case hips = 4
}

// Everything a single frame of Pibo needs. Values are continuous; drawing snaps them to
// whole logical pixels, which is what makes the motion read as pixel art.
final class PiboPixelPose {
    var squash: Double = 0 // > 0 wider and shorter, < 0 taller and thinner
    var lift: Double = 0 // pixels above the ground
    var lean: Double = 0 // top shifts this many pixels sideways
    var lying: Bool = false
    var eyes: PiboPixelEyes = .open
    var blush: Bool = false
    var armsUp: Bool = false
    var arms: PiboPixelArms = .rest
    var sprout: PiboPixelSprout = .upright
    var sproutSway: Double = 0 // -1, 0, 1
    var lookX: Double = 0 // -1, 0, 1
    // Body cues from today's health (decision 057).
    var eyeBags: Bool = false
    var abs: Bool = false
    var sweat: Bool = false
    // Growth: Core's appearance answer and the live bo container.
    var bodyStage: Int = 2
    var leafStage: Int = 0
    var accessoryMask: Int = 0
    /// 0 a dormant bud … 1 a full leaf.
    var leafGrowth: Double = 1
    var leafRipe: Bool = false
    /// Two-stage pull while collecting: 0 rest, 1 fully stretched.
    var leafPull: Double = 0
    var nightGlow: Bool = false
    /// Frame clock for sparkles; stepped by the motion layer.
    var twinkle: Double = 0
    /// Idle trick playing this frame (PiboPixelTrick); the effects layer adds notes or stones.
    var trick: Int = 0
    /// Workout mimic playing this frame (PiboPixelMimic).
    var mimic: Int = 0
    // Pibo's day (decision 058): walking, sitting and what is in its hands.
    /// Which foot is lifted mid-step: -1 left, 1 right, 0 both down.
    var stride: Double = 0
    var sitting: Bool = false
    /// A find carried in front of the belly; -1 for empty hands.
    var holding: Int = -1
    var umbrella: Bool = false
    var watering: Bool = false
    /// Eyes raised one pixel: stargazing, watching a bird.
    var lookUp: Bool = false
    /// One arm stretched up and out past the body (-1 left, 1 right, 0 none): pointing at a
    /// star, reaching for the antenna. The resting U-line arms stay inside the outline.
    var reach: Double = 0
    /// The reaching arm goes out sideways at belly height instead of up: something low.
    var reachLow: Bool = false
    // Decision 060: feelings and the props of life echoes.
    var mouth: PiboPixelMouth = .none
    /// A tear at the corner of the eye: moved.
    var tear: Bool = false
    /// A leaf tied round the forehead (jogging).
    var headband: Bool = false
    /// A floppy nightcap (the late-night watch).
    var nightCap: Bool = false
    var held: PiboPixelProp = .none
    /// Frame step for held props that move (the fan, the hammer).
    var propPhase: Double = 0
    /// One foot tucked up high (-1 left, 1 right): the tree pose.
    var footUp: Double = 0
    /// Both arms stretched up and out in a V.
    var reachBoth: Bool = false
    /// Feet apart: jumping jacks.
    var feetWide: Bool = false
    // Decision 062: the readout badge on its chest, lit in the colour of the Core state.
    var badge: PiboPixelBadge = .none
    /// Before the pod is fixed (season one, beat 4) the lens is cracked.
    var badgeCracked: Bool = false
    /// The cracked lens drops out now and then; a glance makes it blink bright.
    var badgeLit: Bool = true
}

/// The badge's light, one per Core state the stage shows (PiboPixelActivity + 1).
enum PiboPixelBadge: Int {
    case none = 0
    case dataUnknown = 1
    case sleeping = 2
    case waking = 3
    case stable = 4
    case energetic = 5
    case tired = 6
    case celebrate = 7
}

private let BADGE_LIGHT: [PixelInk] = [.clear, .stoneDark, .waterDeep, .acorn,
                                      .leafLight, .fire, .eyeBag, .berry]

/// The badge for a stage activity (PiboPixelActivity: 0 data unknown … 6 celebrate).
func piboPixelBadgeFor(_ activity: Int) -> PiboPixelBadge {
    return activity >= 0 && activity <= 6 ? (PiboPixelBadge(rawValue: activity + 1) ?? .none) : .none
}

/// A 5×5 badge with its top-left corner at (x, y): a dark rim, a 3×3 lens in the state's
/// colour with one highlight, and a crack across it until the pod is fixed.
func drawPiboPixelBadgeAt(_ frame: PixelFrame, _ x: Double, _ y: Double, _ badge: PiboPixelBadge,
                          _ cracked: Bool, _ lit: Bool) {
    if badge == .none { return }
    let ox = jsRoundInt(x)
    let oy = jsRoundInt(y)
    for i in 1..<4 {
        frame.set(ox + i, oy, .line)
        frame.set(ox + i, oy + 4, .line)
        frame.set(ox, oy + i, .line)
        frame.set(ox + 4, oy + i, .line)
    }
    let light: PixelInk = lit ? BADGE_LIGHT[badge.rawValue] : .stoneDark
    frame.fillRect(ox + 1, oy + 1, ox + 4, oy + 4, light)
    if lit { frame.set(ox + 1, oy + 1, .bodyLight) }
    if cracked {
        frame.set(ox + 3, oy + 1, .line)
        frame.set(ox + 2, oy + 2, .line)
    }
}

let PIBO_ACCESSORY_SCARF: Int = 1
let PIBO_ACCESSORY_ACORN_HAT: Int = 2
let PIBO_ACCESSORY_BACKPACK: Int = 4
let PIBO_ACCESSORY_NIGHT_GLOW: Int = 8

// Body radii per growth stage, in logical pixels.
private let BODY_RX: [Int] = [13, 16, 18]
private let BODY_RY: [Int] = [12, 15, 17]

// Kept for layout code that sizes hit areas before a pose exists.
let PIBO_PIXEL_BODY_RX: Int = BODY_RX[2]
let PIBO_PIXEL_BODY_RY: Int = BODY_RY[2]

private let EYE_OPEN: [String] = ["ee", "ee"]
private let EYE_STAR: [String] = ["we", "ee"]
private let EYE_HAPPY: [String] = [".e.", "e.e"]
private let EYE_CLOSED: [String] = ["..", "ee"]
private let EYE_SLEEPY: [String] = ["aa", "ee"]
private let EYE_DOT: [String] = ["e"]
private let EYE_DIZZY: [String] = ["e.e", ".e.", "e.e"]
private let EYE_WIDE: [String] = ["ee", "we", "ee"]
private let EYE_SQUINT: [String] = ["e.", ".e", "e."]
private let MOUTH_OPEN: [String] = ["ee", "ee"]
private let MOUTH_TONGUE: [String] = ["ee", ".b"]
private let MOUTH_YAWN: [String] = [".e.", "eee", "ebe", ".e."]
private let MOUTH_FROWN: [String] = [".e.", "e.e"]
private let MOUTH_CHEW: [String] = ["e.e"]
// Arms akimbo: a short elbow out on each side, hands back on the hips.
private let ARM_HIPS: [String] = ["..ww", ".wwa", "wwa.", "wa..", "wwa.", ".wwa"]
// A leaf headband with its two ends flying behind.
private let HEADBAND_KNOT: [String] = ["gg.", ".gG", "g.G"]
private let NIGHTCAP: [String] = ["..........ii.", ".........iiii", ".......zzz.ii", ".....zzZzz...",
                                  "...zzzzzZz...", "..zZzzzzzzz..", ".zzzzZzzzzZz.",
                                  "iiiiiiiiiiiii", ".IIIIIIIIIII."]
private let FAN_UP: [String] = ["..gGg..", ".gggGgg", "ggGgGgg", "gGgggGg", ".ggGgg.", "...D...", "...D..."]
private let FAN_DOWN: [String] = ["...D...", "...D...", ".ggGgg.", "gGgggGg", "ggGgGgg", ".gggGgg", "..gGg.."]
private let CUP: [String] = ["gZZZg", "gzzzg", ".gGg.", "..g.."]
private let BERRY: [String] = [".g", "66", "66"]
private let SKEWER: [String] = [".....hh", "....hHHh", "DDDDDhh."]
private let MAP: [String] = ["dddddd", "d3OO3d", "d33O3d", "dddddd"]
private let LANTERN: [String] = [".D..", ".DD.", "DDDD", "DyuD", "DuyD", "DDDD"]
private let HAMMER: [String] = ["QQQ", "QQQ", ".D.", ".D.", ".D."]
private let PLANK: [String] = ["dddddddddd", "MMMMMMMMMD", "DDDDDDDDDD"]
private let NOTEBOOK: [String] = ["JjjjJjjjJ", "J3O3J3O3J", "J333J333J", "J3O3J3O3J", "JJJJJJJJJ"]
private let MUZZLE: [String] = ["nn.nn", "nnnnn", ".nNn."]
private let ARM_REST: [String] = ["a..a", "a..a", ".aa."]
private let ARM_UP: [String] = [".aa.", "a..a", "a..a"]
private let ARM_FLEX: [String] = [".a..", "a.a.", "a..a", "a..a", ".aa."]
private let FOOT: [String] = [".www.", "wwwww", "wwwwm", ".mmm."]
// A foot turned sole-out, lifted to the knee of the other leg (tree pose).
private let TUCKED_FOOT: [String] = [".ww.", "wwww", "wwwm", "wwm.", ".m.."]
// A short white arm leaving the right shoulder up and outward; flipped for the left.
private let REACH_ARM: [String] = ["...ww", "..wwa", ".wwa.", "wwa..", "wa..."]
private let REACH_SIDE: [String] = ["wwwww.", "wwwwww", "aaaaa."]
// Both arms raised in a V over the shoulders (tree pose): longer than a reach and outlined
// on both edges, so they read against the sky and against Pibo's own white.
private let REACH_V: [String] = [".....aa", "....awa", "...awa.", "..awa..", ".awa...", "awa....", "wa....."]
// A foot pedalling the air in front of the body, outlined so it reads over Pibo's white.
private let PEDAL_FOOT: [String] = [".mmm.", "mwwwm", "mwwwm", ".mmm."]
private let ABS: [String] = ["a.a", "...", "a.a", "...", "a.a"]
private let SWEAT: [String] = [".r", "rr", "rr"]
// A big leaf held over the head in the rain, and a small watering can.
private let UMBRELLA: [String] = [".....ggggggg.....", "...gglgggggggg...", ".gglgggggGgggggg.",
                                  "gGgggGgggGgggGggG", "G...G...G...G...G"]
private let WATERING_CAN: [String] = ["..qq..", ".q..q.", "qqqqQq", "qqqqQ.q", "qqqqQ..", ".QQQ..."]
// The knot sits on Pibo's side and its two ends flare outward past the outline, wider
// than tall, so the scarf never reads as a stick held between the hands.
private let SCARF_TAIL: [String] = ["cc...", "cCcc.", ".cCcc", ".c.cC"]
private let ACORN_HAT: [String] = ["...HHHHH...", ".HHHhHhHHH.", "HHhHHHHHhHH", "hhhhhhhhhhh", ".hhhhhhhhh."]
// A canvas pack worn on the back: a red flap with a gold buckle peeks out over the right
// shoulder. No strap across the body: a diagonal line read as Pibo holding a stick.
private let BACKPACK: [String] = ["..HHHHH..", ".HcccccH.", "HccCKCccH", "HhhhhhhhH", "HhhHHhhhH",
                                  "HhhhhhhhH", "HhhhhhhhH", "HHhhhhhHH", ".HHHHHHH."]
private let FLOWER: [String] = [".F.", "FuF", ".F."]
private let BUD: [String] = ["b", "b"]

// MARK: - Small numeric helpers

/// JavaScript `Math.round`: halves go up, not away from zero.
private func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }
private func jsRoundInt(_ x: Double) -> Int { Int(jsRound(x)) }
private func jsFloor(_ x: Double) -> Int { Int(x.rounded(.down)) }
private func jsCeil(_ x: Double) -> Int { Int(x.rounded(.up)) }

// MARK: - Body

private struct BodyShape {
    var cx: Double = 0
    var cy: Double = 0
    var rx: Double = Double(PIBO_PIXEL_BODY_RX)
    var ry: Double = Double(PIBO_PIXEL_BODY_RY)
    var lean: Double = 0
    var lying: Bool = false
}

private func insideBody(_ shape: BodyShape, _ x: Int, _ y: Int) -> Bool {
    let ny = (Double(y) + 0.5 - shape.cy) / shape.ry
    if ny < -1 || ny > 1 { return false }
    // Lean shears the body: rows above the centre slide toward `lean`.
    let shift = -ny * shape.lean
    // Mochi silhouette: a round dome on a wider, flatter base.
    let widen = ny < 0 ? 1 + ny * 0.1 : 1
    let nx = (Double(x) + 0.5 - shape.cx - shift) / (shape.rx * widen)
    let power = ny > 0 ? (shape.lying ? 3.2 : 2.7) : 2
    return pow(abs(nx), power) + pow(abs(ny), power) <= 1
}

private struct BodyInks {
    var x0: Int = 0
    var y0: Int = 0
    var w: Int = 0
    var h: Int = 0
    var inks: [UInt8] = []
}

// The shaded silhouette depends only on the shape, which repeats across breathing frames,
// so it is computed once per distinct shape and then stamped.
private let BODY_CACHE_LIMIT: Int = 32

private enum BodyCache {
    static var entries: [String: BodyInks] = [:]
}

private func bodyInks(_ shape: BodyShape) -> BodyInks {
    let key = "\(shape.cx),\(shape.cy),\(shape.rx),\(shape.ry),\(shape.lean),\(shape.lying)"
    if let cached = BodyCache.entries[key] { return cached }
    let x0 = jsFloor(shape.cx - shape.rx - abs(shape.lean) - 2)
    let x1 = jsCeil(shape.cx + shape.rx + abs(shape.lean) + 2)
    let y0 = jsFloor(shape.cy - shape.ry - 1)
    let y1 = jsCeil(shape.cy + shape.ry + 1)
    // The silhouette once per cell, with a one-cell border for the neighbour tests.
    let mw = x1 - x0 + 3
    var mask = [UInt8](repeating: 0, count: mw * (y1 - y0 + 3))
    for y in (y0 - 1)...(y1 + 1) {
        for x in (x0 - 1)...(x1 + 1) where insideBody(shape, x, y) {
            mask[(y - y0 + 1) * mw + (x - x0 + 1)] = 1
        }
    }
    let inside: (Int, Int) -> Bool = { x, y in mask[(y - y0 + 1) * mw + (x - x0 + 1)] == 1 }
    var result = BodyInks()
    result.x0 = x0
    result.y0 = y0
    result.w = x1 - x0 + 1
    result.h = y1 - y0 + 1
    result.inks = [UInt8](repeating: 0, count: result.w * result.h)
    for y in y0...y1 {
        for x in x0...x1 {
            if !inside(x, y) { continue }
            let openLeft = !inside(x - 1, y)
            let openRight = !inside(x + 1, y)
            let openUp = !inside(x, y - 1)
            let openDown = !inside(x, y + 1)
            let nx = (Double(x) + 0.5 - shape.cx) / shape.rx
            let ny = (Double(y) + 0.5 - shape.cy) / shape.ry
            var ink = PixelInk.bodyLight
            // No dark outline: the lit upper-left edge stays white, the far edge picks up a
            // cool grey rim, and only the underside carries a soft shadow band.
            if openDown || ((openRight || openLeft) && ny > 0.35) {
                ink = .bodyShade
            } else if openRight || (openUp && nx > 0.45) {
                ink = .bodyMid
            } else if nx * 0.45 + ny > 0.92 {
                ink = .bodyMid
            }
            result.inks[(y - y0) * result.w + (x - x0)] = ink.rawValue
        }
    }
    if BodyCache.entries.count >= BODY_CACHE_LIMIT { BodyCache.entries.removeAll(keepingCapacity: true) }
    BodyCache.entries[key] = result
    return result
}

private func drawBody(_ frame: PixelFrame, _ shape: BodyShape) {
    let body = bodyInks(shape)
    for row in 0..<body.h {
        for col in 0..<body.w {
            let ink = body.inks[row * body.w + col]
            if ink != 0 { frame.set(body.x0 + col, body.y0 + row, PixelInk(rawValue: ink) ?? .clear) }
        }
    }
}

// MARK: - Face

private func eyeStamp(_ eyes: PiboPixelEyes) -> [String] {
    switch eyes {
    case .happy: return EYE_HAPPY
    case .closed: return EYE_CLOSED
    case .sleepy: return EYE_SLEEPY
    case .dot: return EYE_DOT
    case .star: return EYE_STAR
    case .dizzy: return EYE_DIZZY
    case .wide: return EYE_WIDE
    case .squint: return EYE_SQUINT
    default: return EYE_OPEN
    }
}

private struct FaceAnchor {
    var x: Int = 0
    var eyeY: Int = 0
    var spacing: Int = 0
}

private func faceAnchor(_ shape: BodyShape, _ pose: PiboPixelPose) -> FaceAnchor {
    var anchor = FaceAnchor()
    anchor.x = jsRoundInt(shape.cx + pose.lookX + shape.lean * 0.3 + (shape.lying ? -shape.rx * 0.35 : 0))
    anchor.eyeY = jsRoundInt(shape.cy - shape.ry * (shape.lying ? 0.05 : 0.22)) - (pose.lookUp ? 1 : 0)
    anchor.spacing = max(4, jsRoundInt(shape.rx * 0.3))
    return anchor
}

private func drawFace(_ frame: PixelFrame, _ shape: BodyShape, _ pose: PiboPixelPose) {
    let face = faceAnchor(shape, pose)
    var left: [String] = eyeStamp(pose.eyes)
    var right: [String] = eyeStamp(pose.eyes)
    if pose.eyes == .wink {
        left = EYE_OPEN
        right = EYE_CLOSED
    } else if pose.eyes == .uneven {
        left = EYE_WIDE
        right = EYE_DOT
    }
    let squint = pose.eyes == .squint
    let leftX = face.x - face.spacing - left[0].count + 1
    let rightX = face.x + face.spacing
    let eyeTop = face.eyeY - left.count + 1
    // Grey brow dots sit just above each eye, as in the original art.
    if pose.eyes != .dizzy {
        frame.set(leftX + left[0].count / 2, eyeTop - 2, .arm)
        frame.set(rightX + right[0].count / 2, eyeTop - 2, .arm)
    }
    frame.stamp(left, leftX, eyeTop)
    // Squinting eyes point at each other: > on the left, < on the right.
    frame.stamp(right, rightX, face.eyeY - right.count + 1, flip: squint)
    if pose.eyeBags {
        frame.fillRect(leftX, face.eyeY + 1, leftX + left[0].count, face.eyeY + 2, .eyeBag)
        frame.fillRect(rightX, face.eyeY + 1, rightX + right[0].count, face.eyeY + 2, .eyeBag)
    }
    frame.stamp(MUZZLE, face.x - 2, face.eyeY)
    if pose.blush {
        frame.fillRect(leftX - 3, face.eyeY + 2, leftX, face.eyeY + 3, .blush)
        frame.fillRect(rightX + right[0].count, face.eyeY + 2, rightX + right[0].count + 3,
                       face.eyeY + 3, .blush)
    }
    if pose.tear {
        frame.set(rightX + right[0].count, face.eyeY + 1, .waterLight)
        frame.set(rightX + right[0].count, face.eyeY + 2, .water)
    }
    let mouth = mouthStamp(pose.mouth)
    if !mouth.isEmpty { frame.stamp(mouth, face.x - mouth[0].count / 2, face.eyeY + 3) }
}

private func mouthStamp(_ mouth: PiboPixelMouth) -> [String] {
    switch mouth {
    case .open: return MOUTH_OPEN
    case .tongue: return MOUTH_TONGUE
    case .yawn: return MOUTH_YAWN
    case .frown: return MOUTH_FROWN
    case .chew: return MOUTH_CHEW
    default: return []
    }
}

// MARK: - Limbs

private func drawArms(_ frame: PixelFrame, _ shape: BodyShape, _ pose: PiboPixelPose) {
    if shape.lying || pose.reachBoth { return }
    let cx = jsRoundInt(shape.cx)
    let arms = pose.armsUp ? PiboPixelArms.up : pose.arms
    let inset = jsRoundInt(shape.rx * 0.62)
    let armY = jsRoundInt(shape.cy + shape.ry * 0.12)
    if arms == .up {
        let y = jsRoundInt(shape.cy - shape.ry * 0.1)
        frame.stamp(ARM_UP, cx - inset - 3, y)
        frame.stamp(ARM_UP, cx + inset, y, flip: true)
        return
    }
    if arms == .flex {
        frame.stamp(ARM_FLEX, cx - inset - 4, jsRoundInt(shape.cy - shape.ry * 0.15))
        frame.stamp(ARM_REST, cx + inset - 1, armY, flip: true)
        return
    }
    if arms == .hips {
        let y = armY - 1
        frame.stamp(ARM_HIPS, jsRoundInt(shape.cx - shape.rx) - 2, y)
        frame.stamp(ARM_HIPS, jsRoundInt(shape.cx + shape.rx) - 2, y, flip: true)
        return
    }
    if arms == .hug {
        frame.stamp(ARM_REST, cx - 4, armY + 1)
        frame.stamp(ARM_REST, cx + 1, armY + 1, flip: true)
        return
    }
    frame.stamp(ARM_REST, cx - inset - 2, armY)
    frame.stamp(ARM_REST, cx + inset - 1, armY, flip: true)
}

/// Sitting and pedalling the air (the air bike echo): the feet go round in front.
private func pedalling(_ pose: PiboPixelPose) -> Bool {
    return pose.sitting && !pose.lying && abs(pose.stride) > 1
}

private func drawReach(_ frame: PixelFrame, _ shape: BodyShape, _ pose: PiboPixelPose) {
    if shape.lying { return }
    if pose.reachBoth {
        let y = jsRoundInt(shape.cy - shape.ry * 0.62) - 5
        frame.stamp(REACH_V, jsRoundInt(shape.cx + shape.rx * 0.62), y)
        frame.stamp(REACH_V, jsRoundInt(shape.cx - shape.rx * 0.62) - 7, y, flip: true)
        return
    }
    if pose.reach == 0 { return }
    if pose.reachLow {
        let low = jsRoundInt(shape.cy + shape.ry * 0.05)
        if pose.reach > 0 {
            frame.stamp(REACH_SIDE, jsRoundInt(shape.cx + shape.rx) - 2, low)
        } else {
            frame.stamp(REACH_SIDE, jsRoundInt(shape.cx - shape.rx) - 4, low, flip: true)
        }
        return
    }
    let y = jsRoundInt(shape.cy - shape.ry * 0.55) - 3
    if pose.reach > 0 {
        frame.stamp(REACH_ARM, jsRoundInt(shape.cx + shape.rx * 0.72) - 1, y)
    } else {
        frame.stamp(REACH_ARM, jsRoundInt(shape.cx - shape.rx * 0.72) - 4, y, flip: true)
    }
}

private func drawBellyDetails(_ frame: PixelFrame, _ shape: BodyShape, _ pose: PiboPixelPose) {
    if shape.lying { return }
    let cx = jsRoundInt(shape.cx)
    if pose.abs { frame.stamp(ABS, cx - 1, jsRoundInt(shape.cy + shape.ry * 0.15)) }
    if pose.sweat {
        frame.stamp(SWEAT, jsRoundInt(shape.cx + shape.rx * 0.7), jsRoundInt(shape.cy - shape.ry * 0.75))
    }
}

private func drawScarf(_ frame: PixelFrame, _ shape: BodyShape) {
    if shape.lying { return }
    let y = jsRoundInt(shape.cy - shape.ry * 0.22) + 4
    let first = jsFloor(shape.cx - shape.rx - 2)
    let last = jsFloor(shape.cx + shape.rx + 2)
    for x in first...last {
        if insideBody(shape, x, y) { frame.set(x, y, .scarf) }
        if insideBody(shape, x, y + 1) { frame.set(x, y + 1, .scarf) }
        if insideBody(shape, x, y + 2) { frame.set(x, y + 2, .scarfShade) }
    }
    frame.stamp(SCARF_TAIL, jsRoundInt(shape.cx + shape.rx) - 3, y + 1)
}

private func drawBackpack(_ frame: PixelFrame, _ shape: BodyShape) {
    if shape.lying { return }
    // Drawn before the body, so only the part sticking out past the right side shows.
    frame.stamp(BACKPACK, jsRoundInt(shape.cx + shape.rx - 5), jsRoundInt(shape.cy - shape.ry * 0.75))
}

// MARK: - The bo leaf

private struct LeafPixel {
    var x: Int = 0
    var y: Int = 0
    var ink: PixelInk = .leafMid
}

private struct LeafSpec {
    var baseX: Double = 0
    var baseY: Double = 0
    var length: Double = 10
    /// Radians at the base; positive leans right.
    var angle: Double = 0
    /// Extra radians reached at the tip, for arching droops.
    var bend: Double = 0
    var zigzag: Double = 1.1
    var halfWidth: Double = 1.6
}

// Samples a tall zigzag leaf with a white centre vein, then bends and rotates it. Forward
// supersampling leaves no holes after rotation, unlike rotating finished pixels.
// Stepped motion repeats a handful of leaf poses, so rasterised leaves are reused.
private let LEAF_CACHE_LIMIT: Int = 48

private enum LeafCache {
    static var entries: [String: [LeafPixel]] = [:]
}

private func leafPixels(_ spec: LeafSpec) -> [LeafPixel] {
    let key = "\(spec.baseX),\(spec.baseY),\(spec.length),\(spec.angle),\(spec.bend),\(spec.zigzag),\(spec.halfWidth)"
    if let cached = LeafCache.entries[key] { return cached }
    let pixels = rasteriseLeaf(spec)
    if LeafCache.entries.count >= LEAF_CACHE_LIMIT { LeafCache.entries.removeAll(keepingCapacity: true) }
    LeafCache.entries[key] = pixels
    return pixels
}

private func rasteriseLeaf(_ spec: LeafSpec) -> [LeafPixel] {
    // Insertion order is kept: the merge rule below is order-dependent, exactly as the Map
    // iteration order is on HarmonyOS.
    var cells: [Int: LeafPixel] = [:]
    var order: [Int] = []
    let length = max(2, spec.length)
    let steps = jsCeil(length * 5)
    for i in 0...steps {
        let t = Double(i) / Double(steps)
        // Narrow at the stem, widest a third of the way up, pointed tip.
        let width = max(0.5, spec.halfWidth * sin(Double.pi * pow(t, 0.75)) + (t < 0.15 ? 0.3 : 0))
        let centre = length > 5 ? spec.zigzag * sin(t * Double.pi * 3) * min(1, t * 3) : 0
        let theta = spec.angle + spec.bend * t
        let cosT = cos(theta)
        let sinT = sin(theta)
        var u = -width
        while u <= width + 0.001 {
            let lx = centre + u
            let ly = t * length
            let px = jsRoundInt(spec.baseX + lx * cosT + ly * sinT)
            let py = jsRoundInt(spec.baseY - ly * cosT + lx * sinT)
            let key = py * 4096 + px
            var ink: PixelInk = .leafMid
            if u > width - 0.6 { ink = .leafDark }
            if abs(u - 0.1) < 0.2 && t > 0.18 && t < 0.86 && width > 1.1 { ink = .bodyLight }
            // Vein and dark edge win over fill so thin features survive the rasterisation.
            if cells[key] == nil {
                cells[key] = LeafPixel(x: px, y: py, ink: ink)
                order.append(key)
            } else if cells[key]!.ink == .leafMid && ink != .leafMid {
                cells[key]!.ink = ink
            }
            u += 0.25
        }
    }
    return order.map { cells[$0]! }
}

private func stampLeaf(_ frame: PixelFrame, _ pixels: [LeafPixel], _ rim: PixelInk) {
    if rim != .clear {
        var taken = Set<Int>()
        for p in pixels { taken.insert(p.y * 4096 + p.x) }
        let around: [(Int, Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        for p in pixels {
            for d in around where !taken.contains((p.y + d.1) * 4096 + p.x + d.0) {
                frame.set(p.x + d.0, p.y + d.1, rim)
            }
        }
    }
    for p in pixels { frame.set(p.x, p.y, p.ink) }
}

private func drawLeaves(_ frame: PixelFrame, _ shape: BodyShape, _ pose: PiboPixelPose) {
    let topY = jsRoundInt(shape.cy - shape.ry * (shape.lying ? 0.7 : 1)) + 1
    let topX = jsRoundInt(shape.cx + shape.lean + (shape.lying ? -shape.rx * 0.45 : 0))
    let grownMax: Double = pose.leafStage >= 1 ? 17 : 14
    let growth = max(0, min(1, pose.leafGrowth))
    var main = LeafSpec()
    main.baseX = Double(topX)
    main.baseY = Double(topY)
    main.length = 3 + (grownMax - 3) * growth + pose.leafPull * 6
    main.halfWidth = growth < 0.25 ? 1.2 : 2.0
    main.zigzag = pose.leafPull > 0 ? 0.4 : 1.1
    switch pose.sprout {
    case .droop:
        // Tired: the leaf flops over the head toward the left, like the original.
        main.angle = -1.15
        main.bend = -0.45
        main.zigzag = 0.3
    case .flat:
        main.angle = -0.75
        main.bend = -0.5
        main.zigzag = 0.3
    default:
        main.angle = 0.06 + pose.sproutSway * 0.12
        main.bend = pose.sproutSway * 0.15
    }
    var leaves: [[LeafPixel]] = []
    if pose.leafStage >= 2 {
        var second = LeafSpec()
        second.baseX = Double(topX + 1)
        second.baseY = Double(topY)
        second.length = max(4, main.length * 0.55)
        second.halfWidth = 1.3
        second.zigzag = 0.6
        second.angle = pose.sprout == .upright ? 0.75 : 0.3
        second.bend = pose.sprout == .upright ? 0.2 : -0.6
        leaves.append(leafPixels(second))
        let tipX = jsRoundInt(second.baseX + sin(second.angle + second.bend) * second.length)
        let tipY = jsRoundInt(second.baseY - cos(second.angle + second.bend) * second.length)
        if pose.leafStage == 3 { frame.stamp(BUD, tipX, tipY - 2) }
        if pose.leafStage >= 4 { frame.stamp(FLOWER, tipX - 1, tipY - 3) }
    }
    leaves.append(leafPixels(main))
    // The stage sets nightGlow only after dark and once Core unlocked the glow.
    let rim: PixelInk = pose.leafRipe ? .boLight : (pose.nightGlow ? .glow : .clear)
    for pixels in leaves { stampLeaf(frame, pixels, rim) }
    if pose.leafRipe {
        // Two sparkles orbit a ripe bo, alternating every few frames.
        var tip = leaves[leaves.count - 1][0]
        for p in leaves[leaves.count - 1] where p.y < tip.y { tip = p }
        let phase = jsFloor(pose.twinkle / 3) % 2
        frame.set(tip.x + (phase == 0 ? 3 : -3), tip.y + (phase == 0 ? 1 : 3), .glow)
        frame.set(tip.x + (phase == 0 ? -2 : 2), tip.y - 2, .boMid)
    }
}

private func drawGroundShadow(_ frame: PixelFrame, _ cx: Double, _ groundY: Double, _ rx: Double,
                              _ lift: Double) {
    // The same soft oval shadow the props stand on; it shrinks while Pibo is in the air.
    PixelArt.drawShadow(frame, cx: cx, y: groundY,
                        halfW: max(4, jsRound(rx * 0.9 - lift * 0.6)))
}

// MARK: - Held things

// A private copy of `pixel/scene/PixelFinds.ets`'s `drawPixelFind`, which has no Swift twin
// yet. Kept byte-identical so a carried find draws the same on both platforms; delete it
// when the scene module is ported.
private let FIND_STORY_SEED: Int = 100
private let FIND_ROWS: [[String]] = [
    ["..DD...", ".hHhH..", "HhHhHh.", ".hHhH..", "HhHhHh.", ".hHhH..", "..hh..."], // pinecone
    ["......j", "....jjJ", "...jjJ.", "..jjJ..", ".jjJ...", ".jJ....", "D......"], // feather
    ["..qqq..", ".qQqqq.", "qqqqQqq", "qQqqqqQ", ".qqqQq.", "..QQq..", "......."], // odd stone
    ["...p...", "..ppp..", ".pPppp.", "ppppPpp", ".ppPpp.", "...D...", "...D..."], // red leaf
    ["..DD...", ".HHHH..", "HHHHHH.", ".hhhh..", ".hhhh..", "..hh...", "......."], // acorn
    [".gg.gg.", "gllggl.", ".gggg..", "gglgg..", ".gg.gg.", "...G...", "...G..."], // four-leaf clover
    [".j.j.j.", "j.jjj.j", ".jjjjj.", "j.jjj.j", ".j.G.j.", "...G...", "...G..."], // dandelion
    ["..hhh..", ".hHHHh.", "hHhhhHh", "hHhHhHh", ".hhHhh.", "mmmmmm.", "......."], // snail shell
    ["......D", ".....D.", "..DdD..", ".D.D...", "D..D...", "..D....", ".D....."], // twig
    [".xxxx..", "xxjxxx.", "xxxxjx.", ".jjjj..", "..jj...", "..jj...", "......."], // little mushroom
    [".......", "..qqq..", ".qqqqq.", "qqqqqqQ", ".qqqqQ.", "..QQQ..", "......."], // smooth pebble
    ["...j...", "..jjj..", ".jJjJj.", "jJjJjJj", "jjjjjjj", ".jjjjj.", "......."], // river shell
    ["..hh...", ".hHHh..", "hHhhHh.", ".hHHh..", "h.hh.h.", ".h..h..", "......."], // cicada shell
    ["zzzzzzz", ".zZzZz.", ".zZ.Zz.", "..Z.Z..", "..Z..Z.", "..Z....", "......."], // icicle
    [".......", "..iii..", ".iiiiI.", "iiiiiII", "iiiiIII", ".iiIII.", "..III.."], // snowball
    ["..g....", ".Gg....", ".bbb.b.", "bbbbbbb", ".bbbbb.", "..bbb..", "......."], // wild berry
    [".......", "..FF...", ".FFFF..", "FFFFFF.", ".FFFFF.", "..FFF..", "...F..."], // petal
    [".......", "..jjj..", ".jjjJj.", "jJ.j.Jj", "jjjjjjj", ".jjjjj.", "......."], // eggshell
    [".......", ".uuuuu.", "uuuuuuu", ".uuuuu.", "..u.u..", "...D...", "...D..."], // ginkgo leaf
    [".DDDDD.", ".jZZZj.", "jZ.Z.Zj", "jZZ.ZZj", "jZ.Z.Zj", "jZZZZZj", ".jjjjj."], // a jar of wind
    [".......", ".qq.qq.", "qqqqqqq", "qqqqqqQ", ".qqqqQ.", ".......", "......."], // cloud stone
    ["G.G.G..", ".G.G.G.", "G.G.G..", ".GGGG..", "..DD...", "..DD...", "......."], // pine needles
    ["..u.u..", ".uuuuu.", "..uuu..", ".uuuuu.", "..uuu..", "...D...", "...D..."], // wheat ear
    [".......", "..ZZ...", ".ZZzZ..", "ZzZZzZ.", ".ZZzZZ.", "..ZZZ..", "......."] // sea glass
]

// The season's story things (decision 059), outside Core's find order.
private let FIND_STORY_ROWS: [[String]] = [
    [".......", "...g...", "..hHh..", ".hHHHh.", ".hHhHh.", "..hhh..", "......."], // the seed, already sprouting
    [".......", ".qLLq..", "..QqQ..", "...Q...", "...q...", "...Q...", "...q..."], // the screw
    [".......", "jjjjjj.", "jOOjOj.", "jjjjjjD", "jOjOOj.", "jjjjjj.", "......."], // the report
    [".......", "jjjjjjj", "jJ...Jj", "jjJ.Jjj", "jjjpjjj", "jjjjjjj", "......."], // a letter, sealed red
    [".......", ".......", "ddddddd", "MMQMMQM", "DDDDDDD", ".......", "......."], // a plank
    [".......", "5JJJJJ.", "J3O3OJ.", "J3OO3J5", "J3O3OJ.", "5JJJJJ.", "......."] // the old notebook, mossy
]

private func stampFind(_ frame: PixelFrame, _ item: Int, _ x: Int, _ y: Int) {
    if item >= FIND_STORY_SEED && item < FIND_STORY_SEED + FIND_STORY_ROWS.count {
        frame.stamp(FIND_STORY_ROWS[item - FIND_STORY_SEED], x, y)
        return
    }
    if item < 0 || item >= FIND_ROWS.count { return }
    frame.stamp(FIND_ROWS[item], x, y)
}

// Things in Pibo's hands, drawn over the body.
private func drawHeld(_ frame: PixelFrame, _ shape: BodyShape, _ pose: PiboPixelPose) {
    if shape.lying { return }
    if pose.holding >= 0 {
        stampFind(frame, pose.holding, jsRoundInt(shape.cx) - 3, jsRoundInt(shape.cy + shape.ry * 0.05))
    }
    if pose.watering {
        frame.stamp(WATERING_CAN, jsRoundInt(shape.cx + shape.rx * 0.55),
                    jsRoundInt(shape.cy + shape.ry * 0.05), flip: pose.lookX < 0)
    }
    drawProp(frame, shape, pose)
    if pose.umbrella {
        let top = jsRoundInt(shape.cy - shape.ry) - 16
        frame.stamp(UMBRELLA, jsRoundInt(shape.cx) - 8, top)
        let bottom = jsRoundInt(shape.cy)
        if top + 4 < bottom {
            for y in (top + 4)..<bottom {
                frame.set(jsRoundInt(shape.cx + shape.rx * 0.55), y, .woodDark)
            }
        }
    }
}

private func drawProp(_ frame: PixelFrame, _ shape: BodyShape, _ pose: PiboPixelPose) {
    let cx = jsRoundInt(shape.cx)
    let belly = jsRoundInt(shape.cy + shape.ry * 0.05)
    let side: Int = pose.lookX < 0 ? -1 : 1
    let flip = side < 0
    let hand = side > 0 ? jsRoundInt(shape.cx + shape.rx * 0.55) : jsRoundInt(shape.cx - shape.rx * 0.55)
    let evenPhase = pose.propPhase.truncatingRemainder(dividingBy: 2) == 0
    switch pose.held {
    case .fan:
        let art = evenPhase ? FAN_UP : FAN_DOWN
        frame.stamp(art, hand + (flip ? -4 : 0), jsRoundInt(shape.cy - shape.ry * 0.5), flip: flip)
    case .cup:
        frame.stamp(CUP, hand - (flip ? 3 : 0), belly - (evenPhase ? 0 : 5), flip: flip)
    case .berry:
        frame.stamp(BERRY, cx - 1, belly - (evenPhase ? 0 : 6))
    case .skewer:
        frame.stamp(SKEWER, side > 0 ? hand - 1 : hand - 7, belly, flip: flip)
    case .map:
        frame.stamp(MAP, cx - 3, belly - 3)
    case .lantern:
        frame.stamp(LANTERN, hand - 1, belly + 1)
    case .hammer:
        frame.stamp(HAMMER, hand - 1, belly - (evenPhase ? 6 : 1), flip: flip)
    case .plank:
        frame.stamp(PLANK, side > 0 ? cx - 1 : cx - 9, belly + 1, flip: flip)
    case .notebook:
        frame.stamp(NOTEBOOK, cx - 4, belly - 1)
    default:
        break
    }
}

/// Worn over the head: a leaf headband or the nightcap.
private func drawHeadwear(_ frame: PixelFrame, _ shape: BodyShape, _ pose: PiboPixelPose) {
    if shape.lying && !pose.nightCap { return }
    let top = jsRoundInt(shape.cy - shape.ry)
    if pose.headband {
        let y = top + jsRoundInt(shape.ry * 0.3)
        let first = jsFloor(shape.cx - shape.rx)
        let last = jsFloor(shape.cx + shape.rx)
        for x in first...last where insideBody(shape, x, y) {
            frame.set(x, y, .leafMid)
        }
        let back: Int = pose.lookX < 0 ? 1 : -1
        let knotX = back > 0 ? jsRoundInt(shape.cx + shape.rx) - 1 : jsRoundInt(shape.cx - shape.rx) - 2
        frame.stamp(HEADBAND_KNOT, knotX, y - 1, flip: back < 0)
    }
    if pose.nightCap {
        frame.stamp(NIGHTCAP, jsRoundInt(shape.cx + shape.lean - 7), top - 6)
    }
}

// MARK: - Entry points

func piboPixelBodySize(_ bodyStage: Int) -> [Int] {
    let stage = max(0, min(BODY_RX.count - 1, bodyStage))
    return [BODY_RX[stage], BODY_RY[stage]]
}

/// Where the top of the leaf base sits, for anchoring bubbles and effects.
func piboPixelHeadTop(cx: Double, groundY: Double, pose: PiboPixelPose) -> [Double] {
    let size = piboPixelBodySize(pose.bodyStage)
    return [jsRound(cx), groundY - jsRound(max(0, pose.lift)) - 3 - Double(size[1] * 2)]
}

// Draws Pibo standing (or lying) on `groundY`, horizontally centred on `cx`.
func drawPiboPixel(_ frame: PixelFrame, _ cx: Double, _ groundY: Double, _ pose: PiboPixelPose) {
    var shape = BodyShape()
    let size = piboPixelBodySize(pose.bodyStage)
    let squash = max(-0.35, min(0.35, pose.squash - pose.leafPull * 0.12))
    shape.rx = jsRound(Double(size[0]) * (1 + squash * 0.5))
    shape.ry = jsRound(Double(size[1]) * (1 - squash * 0.5))
    shape.lying = pose.lying
    if pose.lying {
        shape.rx = Double(size[0] + 5)
        shape.ry = Double(size[1] - 4)
    }
    let lift = jsRound(max(0, pose.lift) + pose.leafPull * 2)
    let feet: Double = pose.lying ? 0 : 2
    shape.cx = jsRound(cx)
    shape.cy = groundY - lift - feet - shape.ry
    shape.lean = jsRound(pose.lean)

    if pose.sitting && !pose.lying { shape.cy += 2 }
    drawGroundShadow(frame, cx, groundY, shape.rx, lift)
    let backpack = (pose.accessoryMask & PIBO_ACCESSORY_BACKPACK) != 0
    if backpack { drawBackpack(frame, shape) }
    let bodyCx = Int(shape.cx)
    if !pose.lying {
        let footY = groundY - lift - 4
        // Sitting: feet stick out to the sides; walking: one foot is up mid-step.
        let spread = max(3, jsRoundInt(shape.rx * 0.28)) + (pose.sitting ? 4 : 0) + (pose.feetWide ? 5 : 0)
        let sitDrop: Double = pose.sitting ? 1 : 0
        if pedalling(pose) {
            // Drawn over the body below, in front of it.
        } else if pose.footUp != 0 {
            // The tree pose: standing on one foot in the middle; the other is drawn tucked up
            // against it after the body.
            frame.stamp(FOOT, bodyCx - 2, jsRoundInt(footY))
        } else {
            frame.stamp(FOOT, bodyCx - spread - 4,
                        jsRoundInt(footY + sitDrop - (pose.stride < 0 ? 1 : 0)))
            frame.stamp(FOOT, bodyCx + spread,
                        jsRoundInt(footY + sitDrop - (pose.stride > 0 ? 1 : 0)))
        }
    } else {
        frame.stamp(FOOT, jsRoundInt(shape.cx + shape.rx - 4), jsRoundInt(groundY - 4))
    }
    drawBody(frame, shape)
    if pose.footUp != 0 && !pose.lying {
        // The lifted foot sticks out past the body's side, knee bent out.
        let tuckX = pose.footUp > 0
            ? jsRoundInt(shape.cx + shape.rx) - 2
            : jsRoundInt(shape.cx - shape.rx) - 3
        frame.stamp(TUCKED_FOOT, tuckX, jsRoundInt(groundY - lift - 8), flip: pose.footUp < 0)
    }
    if pedalling(pose) {
        let footY = groundY - 5
        let spread = jsRoundInt(shape.rx * 0.4)
        frame.stamp(PEDAL_FOOT, bodyCx - spread - 3, jsRoundInt(footY - (pose.stride < 0 ? 3 : 0)))
        frame.stamp(PEDAL_FOOT, bodyCx + spread - 2, jsRoundInt(footY - (pose.stride > 0 ? 3 : 0)))
    } else if !pose.lying && pose.footUp == 0 {
        // The two feet meet the body with a short grey crease, like the original's toes.
        let spread = max(3, jsRoundInt(shape.rx * 0.28))
        frame.set(bodyCx - spread - 2, jsFloor(groundY - lift - 4), .bodyMid)
        frame.set(bodyCx + spread + 2, jsFloor(groundY - lift - 4), .bodyMid)
    }
    if (pose.accessoryMask & PIBO_ACCESSORY_SCARF) != 0 { drawScarf(frame, shape) }
    drawArms(frame, shape, pose)
    drawReach(frame, shape, pose)
    drawBellyDetails(frame, shape, pose)
    if !pose.lying {
        // On the chest, off to one side of the belly so the abs and the scarf keep their place.
        drawPiboPixelBadgeAt(frame,
                             shape.cx + jsRound(shape.rx * 0.42) - 2 + jsRound(shape.lean * 0.2),
                             jsRound(shape.cy + shape.ry * 0.38) - 2,
                             pose.badge, pose.badgeCracked, pose.badgeLit)
    }
    drawFace(frame, shape, pose)
    drawLeaves(frame, shape, pose)
    drawHeadwear(frame, shape, pose)
    drawHeld(frame, shape, pose)
    if (pose.accessoryMask & PIBO_ACCESSORY_ACORN_HAT) != 0 && !pose.lying {
        frame.stamp(ACORN_HAT, jsRoundInt(shape.cx + shape.lean - 5), jsRoundInt(shape.cy - shape.ry) - 2)
    }
}

// Decision 061: whatever shape Pibo takes keeps its bo leaf and its eyes, so you always
// know it is Pibo. The forms draw these two parts with Pibo's own art.

/// The bo leaf alone, growing up from (baseX, baseY); `angle` leans it right.
func drawPiboPixelLeafAt(_ frame: PixelFrame, _ baseX: Double, _ baseY: Double, _ length: Double,
                         _ angle: Double = 0.06) {
    var spec = LeafSpec()
    spec.baseX = jsRound(baseX)
    spec.baseY = jsRound(baseY)
    spec.length = length
    spec.halfWidth = 1.8
    spec.angle = angle
    spec.bend = angle * 0.6
    stampLeaf(frame, leafPixels(spec), .clear)
}

/// Pibo's two eyes with their brow dots, centred on cx with their lower row at eyeY.
/// `closed` draws them shut; `squeezed` as > <.
func drawPiboPixelEyesAt(_ frame: PixelFrame, _ cx: Double, _ eyeY: Double, _ spacing: Double,
                         closed: Bool = false, squeezed: Bool = false) {
    let eye = squeezed ? EYE_SQUINT : (closed ? EYE_CLOSED : EYE_OPEN)
    // Kept as numbers: `stamp` rounds its origin while `set` floors it, exactly as on
    // HarmonyOS.
    let leftX = jsRound(cx) - spacing - Double(eye[0].count) + 1
    let rightX = jsRound(cx) + spacing
    let top = jsRound(eyeY) - Double(eye.count) + 1
    if !closed && !squeezed {
        frame.set(leftX + 1, top - 2, .arm)
        frame.set(rightX + 1, top - 2, .arm)
    }
    frame.stamp(eye, jsRoundInt(leftX), jsRoundInt(top))
    frame.stamp(eye, jsRoundInt(rightX), jsRoundInt(top), flip: squeezed)
}

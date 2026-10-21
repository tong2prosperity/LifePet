import Foundation

// How Pibo shows a feeling (decision 060). Core decides which of the ten feelings a
// moment brings out and when Pibo fidgets; this file only turns one into eyes, a mouth,
// a body motion and a small mark above the head, over however long it plays.
//
// Ported from HarmonyPibo `pixel/character/PiboPixelEmote.ets`.

/// The small sign drawn above Pibo's head.
enum PiboPixelMark: Int {
    case none = 0
    case exclaim = 1
    case question = 2
    /// Three dots, one at a time: bored.
    case dots = 3
    /// A twinkle beside the head: proud.
    case sparkle = 4
    /// Wavy heat rising: hot.
    case steam = 5
    /// Two sweat drops flying off.
    case sweat = 6
    /// The burst of a sneeze.
    case burst = 7
    /// A small heart: moved, shy.
    case heart = 8
    /// A puff of white breath: cold.
    case breath = 9
    /// A rising "!" then a hiccup bubble.
    case bubble = 10
}

/// Decision 060's feelings (Core `PiboEmote`). Declared here because the Swift twin of
/// `models/PiboDayValues.ets` does not exist yet; move it there when it does.
enum PiboEmote: Int {
    case none = 0
    case surprised = 1
    case shy = 2
    case proud = 3
    case puzzled = 4
    case sulky = 5
    case bored = 6
    case moved = 7
    case sneeze = 8
    case shiver = 9
    case hot = 10
}

/// Core `PiboFidget`, declared here for the same reason as `PiboEmote`.
enum PiboFidget: Int {
    case none = 0
    case doubleBlink = 1
    case lookAround = 2
    case scratchHead = 3
    case yawn = 4
    case stumble = 5
    case hiccup = 6
}

/// How long each feeling plays, indexed by PiboEmote.
private let EMOTE_MS: [Double] = [0, 1600, 2200, 2600, 2400, 2600, 3000, 3200, 1800, 2800, 3000]
/// How long each fidget plays, indexed by PiboFidget.
private let FIDGET_MS: [Double] = [0, 600, 2000, 1600, 2200, 1100, 1400]

func piboEmoteDuration(_ emote: PiboEmote) -> Double {
    let index = emote.rawValue
    return index >= 0 && index < EMOTE_MS.count ? EMOTE_MS[index] : 0
}

func piboFidgetDuration(_ fidget: PiboFidget) -> Double {
    let index = fidget.rawValue
    return index >= 0 && index < FIDGET_MS.count ? FIDGET_MS[index] : 0
}

private func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }
private func jsRoundInt(_ x: Double) -> Int { Int(jsRound(x)) }
private func jsFloor(_ x: Double) -> Int { Int(x.rounded(.down)) }

private func step(_ age: Double, _ period: Double) -> Int {
    return jsFloor(max(0, age) / period)
}

/// Layers a feeling over the pose. Returns the mark to draw above the head.
func applyPiboEmote(_ pose: PiboPixelPose, _ emote: PiboEmote, _ age: Double,
                    _ reduceMotion: Bool) -> PiboPixelMark {
    let t = reduceMotion ? 300 : age
    let sit = pose.sitting
    switch emote {
    case .surprised:
        // A jolt up, wide eyes and a round mouth, then it settles.
        let jolt = t < 240
        pose.eyes = .wide
        pose.mouth = .open
        pose.squash = jolt ? -0.22 : (t < 420 ? 0.12 : 0)
        if !sit && !pose.lying { pose.lift = jolt ? 3 : 0 }
        pose.lookX = 0
        pose.sprout = .upright
        return .exclaim
    case .shy:
        pose.eyes = .squint
        pose.blush = true
        pose.arms = .hug
        pose.armsUp = false
        pose.lean = step(t, 260) % 4 == 1 ? -2 : (step(t, 260) % 4 == 3 ? 2 : 0)
        pose.squash = 0.08
        return .heart
    case .proud:
        pose.eyes = .happy
        pose.arms = .hips
        pose.armsUp = false
        pose.squash = -0.12
        pose.lean = 0
        pose.lookUp = true
        return .sparkle
    case .puzzled:
        pose.eyes = .uneven
        pose.lean = 2
        pose.lookX = 1
        pose.sproutSway = 1
        return .question
    case .sulky:
        // Turns half away for a beat, cheeks puffed, then peeks back.
        pose.eyes = t < 1800 ? .closed : .dot
        pose.mouth = .frown
        pose.lookX = t < 1800 ? -1 : 0
        pose.lean = t < 1800 ? -1 : 0
        pose.blush = true
        pose.squash = 0.1
        pose.armsUp = false
        pose.arms = .hug
        return .none
    case .bored:
        pose.eyes = .sleepy
        pose.sprout = .droop
        pose.squash = 0.1
        pose.stride = step(t, 500) % 2 == 0 ? 1 : 0
        pose.lookX = step(t, 1500) % 2 == 0 ? -1 : 1
        return .dots
    case .moved:
        pose.eyes = .star
        pose.tear = step(t, 400) % 3 != 2
        pose.blush = true
        pose.arms = .hug
        pose.armsUp = false
        pose.lookUp = true
        return .heart
    case .sneeze:
        // Wind up (tall, eyes squeezing), achoo (squash, burst), wobble.
        if t < 900 {
            pose.eyes = t < 500 ? .open : .squint
            pose.squash = -0.1 - (t / 900) * 0.12
            pose.lookUp = true
            pose.mouth = t > 500 ? .open : .none
            return .none
        }
        pose.eyes = .squint
        pose.squash = t < 1200 ? 0.28 : 0.06
        pose.lean = t < 1200 ? 3 : (step(t, 120) % 2 == 0 ? -1 : 1)
        pose.lookX = 1
        return t < 1500 ? .burst : .none
    case .shiver:
        pose.lean = step(t, 70) % 2 == 0 ? -1 : 1
        pose.arms = .hug
        pose.armsUp = false
        pose.eyes = .squint
        pose.squash = 0.12
        pose.sprout = .droop
        return .breath
    case .hot:
        pose.mouth = .tongue
        pose.eyes = .sleepy
        pose.sweat = true
        pose.squash = 0.06 + (step(t, 300) % 2 == 0 ? 0.04 : 0)
        pose.sprout = .droop
        return .steam
    default:
        return .none
    }
}

/// Layers a small idle motion over the pose. Returns a mark, if any.
func applyPiboFidget(_ pose: PiboPixelPose, _ fidget: PiboFidget, _ age: Double,
                     _ reduceMotion: Bool) -> PiboPixelMark {
    if reduceMotion { return .none }
    switch fidget {
    case .doubleBlink:
        if age < 120 || (age > 260 && age < 380) { pose.eyes = .closed }
        return .none
    case .lookAround:
        pose.lookX = age < 700 ? -1 : (age < 1400 ? 1 : 0)
        pose.lookUp = age > 1400
        return .none
    case .scratchHead:
        pose.reach = 1
        pose.reachLow = false
        pose.lean = step(age, 160) % 2 == 0 ? 1 : 0
        pose.eyes = .dot
        return age > 600 ? .question : .none
    case .yawn:
        if age > 300 && age < 1700 {
            pose.mouth = .yawn
            pose.eyes = .closed
            pose.squash = -0.14
            pose.armsUp = !pose.sitting && !pose.lying
        }
        return .none
    case .stumble:
        // Toe catches, lurches forward, arms flail, catches itself.
        if age < 300 {
            pose.lean = Double((pose.lookX < 0 ? -1 : 1) * 3)
            pose.eyes = .wide
            pose.armsUp = true
        } else if age < 700 {
            pose.lean = Double(pose.lookX < 0 ? 1 : -1)
            pose.eyes = .dot
        }
        return age < 500 ? .exclaim : .none
    case .hiccup:
        let hic = age.truncatingRemainder(dividingBy: 700) < 160
        if hic {
            pose.lift = max(pose.lift, pose.sitting ? 0 : 1)
            pose.squash = -0.1
            pose.eyes = .wide
        }
        return hic ? .bubble : .none
    default:
        return .none
    }
}

private let HEART: [String] = ["b.b", "bbb", ".b."]
private let SPARKLE_A: [String] = [".y.", "yuy", ".y."]
private let SPARKLE_B: [String] = ["y.y", ".u.", "y.y"]
private let BURST: [String] = ["i.i.i", ".iii.", "ii.ii", ".iii.", "i.i.i"]
private let BREATH: [String] = [".BB.", "BBBB", ".BB."]
private let DROP: [String] = [".z", "zZ"]
private let BUBBLE: [String] = [".BB.", "B..B", ".BB."]

// A private copy of `effects/PixelEffects.ets`'s 3×5 font and `drawPixelText`, which have
// no Swift twin yet. Only the glyphs the marks use are reachable from here, but the whole
// table is kept so text renders identically when the effects module is ported.
private let TEXT_GLYPHS: [Character: [String]] = [
    "0": ["###", "#.#", "#.#", "#.#", "###"],
    "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["###", "..#", "###", "#..", "###"],
    "3": ["###", "..#", ".##", "..#", "###"],
    "4": ["#.#", "#.#", "###", "..#", "..#"],
    "5": ["###", "#..", "###", "..#", "###"],
    "6": ["###", "#..", "###", "#.#", "###"],
    "7": ["###", "..#", ".#.", ".#.", ".#."],
    "8": ["###", "#.#", "###", "#.#", "###"],
    "9": ["###", "#.#", "###", "..#", "###"],
    "+": ["...", ".#.", "###", ".#.", "..."],
    "L": ["#..", "#..", "#..", "#..", "###"],
    "v": ["...", "...", "#.#", "#.#", ".#."],
    ".": ["...", "...", "...", "...", ".#."],
    "!": [".#.", ".#.", ".#.", "...", ".#."],
    "?": ["###", "..#", ".##", "...", ".#."],
    "x": ["...", "#.#", ".#.", "#.#", "..."]
]

/// Draws short text in the 3×5 pixel font with a one-pixel dark rim for legibility.
private func drawText(_ frame: PixelFrame, _ text: String, _ x: Double, _ y: Double,
                      _ ink: PixelInk, _ rim: PixelInk = .outline) {
    let ox = jsRoundInt(x)
    let oy = jsRoundInt(y)
    var cells: [(Int, Int)] = []
    for (i, glyphChar) in text.enumerated() {
        guard let glyph = TEXT_GLYPHS[glyphChar] else { continue }
        for row in 0..<5 {
            for col in 0..<3 where glyph[row].charactersAt(col) == "#" {
                cells.append((ox + i * 4 + col, oy + row))
            }
        }
    }
    if rim != .clear {
        for c in cells {
            frame.set(c.0 - 1, c.1, rim)
            frame.set(c.0 + 1, c.1, rim)
            frame.set(c.0, c.1 - 1, rim)
            frame.set(c.0, c.1 + 1, rim)
        }
    }
    for c in cells { frame.set(c.0, c.1, ink) }
}

private extension String {
    /// The character at `offset`, or a space when the row is shorter than expected.
    func charactersAt(_ offset: Int) -> Character {
        let index = self.index(startIndex, offsetBy: offset)
        return self[index]
    }
}

/// Draws a mark at the right of Pibo's head. `rx` is the body's half width.
func drawPiboPixelMark(_ frame: PixelFrame, _ mark: PiboPixelMark, _ cx: Double, _ headY: Double,
                       _ rx: Double, _ age: Double) {
    let x = cx + rx - 2
    let y = headY - 10
    let bob = jsFloor(age / 400) % 2
    switch mark {
    case .exclaim:
        drawText(frame, "!", x, y - Double(min(3, jsFloor(age / 60))), .sun)
    case .question:
        drawText(frame, "?", x, y - Double(bob), .bodyLight)
    case .dots:
        let shown = 1 + jsFloor(age / 700) % 3
        for i in 0..<shown {
            frame.fillRect(x + Double(i * 3), y + 4, 2, 2, .bodyLight)
        }
    case .sparkle:
        frame.stamp(bob == 0 ? SPARKLE_A : SPARKLE_B, jsRoundInt(x + 2), jsRoundInt(y))
        frame.stamp(bob == 0 ? SPARKLE_B : SPARKLE_A, jsRoundInt(cx - rx - 4), jsRoundInt(y + 6))
    case .steam:
        for i in 0..<3 {
            let phase = ((age / 500) + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
            let sx = cx - 6 + Double(i * 6) + jsRound(sin(phase * 6.28) * 1)
            let sy = headY - 2 - jsRound(phase * 8)
            frame.set(sx, sy, .cloudLight)
            frame.set(sx, sy - 1, .cloudShade)
        }
    case .sweat:
        frame.stamp(DROP, jsRoundInt(x + 2), jsRoundInt(y + 6 - Double(bob * 2)))
        frame.stamp(DROP, jsRoundInt(cx - rx - 2), jsRoundInt(y + 8 - Double(bob)), flip: true)
    case .burst:
        frame.stamp(BURST, jsRoundInt(x + 4), jsRoundInt(headY + 4))
    case .heart:
        frame.stamp(HEART, jsRoundInt(x + 1), jsRoundInt(y + 2 - Double(min(4, jsFloor(age / 300)))))
    case .breath:
        let puff = jsFloor(age / 900) % 2 == 0
        if puff { frame.stamp(BREATH, jsRoundInt(x + 2), jsRoundInt(headY + 6)) }
    case .bubble:
        frame.stamp(BUBBLE, jsRoundInt(x + 2), jsRoundInt(y + 2))
    default:
        break
    }
}

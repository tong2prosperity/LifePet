import Foundation

// One-shot pixel effects. Each effect is a pure function of (kind, start, position, seed)
// and the current time, so a frame can be redrawn at any moment and tests can pin it.
//
// Ported from HarmonyPibo `pixel/effects/PixelEffects.ets`.

enum PixelEffectKind: Int {
    case hearts = 0
    case xpPop = 1
    case energyOrbs = 2
    case levelPillar = 3
    case confetti = 4
    case boBurst = 5
    case bloom = 6
    case dizzyStars = 7
    case stamp = 8
    case sparkle = 9
}

struct PixelEffect {
    var kind: PixelEffectKind = .hearts
    var startMs: Double = 0
    var x: Int = 0
    var y: Int = 0
    /// Where travelling effects (energy orbs) land.
    var toX: Int = 0
    var toY: Int = 0
    var value: Double = 0
    var seed: Int = 1
    var ink: PixelInk = .glow
}

private let DURATIONS: [Double] = [1100, 1300, 1400, 2200, 2400, 900, 900, 1600, 1100, 800]

func pixelEffectDuration(_ kind: PixelEffectKind) -> Double {
    DURATIONS.indices.contains(kind.rawValue) ? DURATIONS[kind.rawValue] : 1000
}

func makePixelEffect(_ kind: PixelEffectKind, _ startMs: Double, _ x: Int, _ y: Int,
                     _ value: Double = 0, _ seed: Int = 1) -> PixelEffect {
    var effect = PixelEffect()
    effect.kind = kind
    effect.startMs = startMs
    effect.x = x
    effect.y = y
    effect.value = value
    effect.seed = seed
    return effect
}

// 3×5 digits and a few signs for "+12", "Lv.5" and similar pops.
private let GLYPHS: [Character: [String]] = [
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

func pixelTextWidth(_ text: String) -> Int {
    text.count * 4 - 1
}

/// Draws short text in the 3×5 pixel font with a one-pixel dark rim for legibility.
func drawPixelText(_ frame: PixelFrame, _ text: String, _ x: Int, _ y: Int, _ ink: PixelInk,
                   _ rim: PixelInk = .outline) {
    var cells: [[Int]] = []
    for (i, character) in text.enumerated() {
        guard let glyph = GLYPHS[character] else { continue }
        for row in 0..<5 {
            let line = Array(glyph[row])
            for col in 0..<3 where col < line.count && line[col] == "#" {
                cells.append([x + i * 4 + col, y + row])
            }
        }
    }
    if rim != .clear {
        for c in cells {
            frame.set(c[0] - 1, c[1], rim)
            frame.set(c[0] + 1, c[1], rim)
            frame.set(c[0], c[1] - 1, rim)
            frame.set(c[0], c[1] + 1, rim)
        }
    }
    for c in cells { frame.set(c[0], c[1], ink) }
}

private let HEART: [String] = ["b.b", "bbb", ".b."]
private let NOTE: [String] = [".oo", ".o.", "oo.", "oo."]
private let STAR: [String] = [".y.", "yyy", ".y."]
private let STAMP: [String] = [
    "..ccccc..",
    ".c.....c.",
    "c..c.c..c",
    "c.......c",
    "c.c...c.c",
    "c..ccc..c",
    ".c.....c.",
    "..ccccc.."
]

private func ease(_ t: Double) -> Double {
    1 - (1 - t) * (1 - t)
}

private func drawHearts(_ frame: PixelFrame, _ e: PixelEffect, _ t: Double) {
    let rng = PixelRandom(e.seed)
    for i in 0..<3 {
        let delay = Double(i) * 0.18
        let local = (t - delay) / (1 - delay)
        if local <= 0 || local >= 1 { continue }
        let x = e.x + rng.int(-8, 8) + PixelMath.round(sin(local * 6 + Double(i)) * 1.5)
        let y = e.y - PixelMath.round(ease(local) * 14)
        if local > 0.8 && PixelMath.floor(local * 20) % 2 == 0 { continue }
        frame.stamp(HEART, x - 1, y)
    }
}

private func drawXpPop(_ frame: PixelFrame, _ e: PixelEffect, _ t: Double) {
    let text = "+\(PixelMath.round(e.value))"
    let y = e.y - PixelMath.round(ease(min(1, t * 1.6)) * 9)
    if t > 0.85 && PixelMath.floor(t * 30) % 2 == 0 { return }
    drawPixelText(frame, text, e.x - pixelTextWidth(text) / 2, y, e.ink)
}

private func drawEnergyOrbs(_ frame: PixelFrame, _ e: PixelEffect, _ t: Double) {
    let count = max(1, min(6, PixelMath.round(e.value)))
    let rng = PixelRandom(e.seed)
    for i in 0..<count {
        let delay = Double(i) * 0.08
        let local = max(0, min(1, (t - delay) / 0.7))
        if local <= 0 || local >= 1 { continue }
        // A shallow arc from the source chip up to the leaf.
        let arc = sin(local * Double.pi) * Double(10 + rng.int(0, 8))
        let x = PixelMath.round(Double(e.x) + Double(e.toX - e.x) * ease(local)
                                + Double(rng.int(-2, 2)) * (1 - local))
        let y = PixelMath.round(Double(e.y) + Double(e.toY - e.y) * local - arc)
        frame.set(x, y, e.ink)
        frame.set(x + 1, y, e.ink)
        frame.set(x, y + 1, e.ink)
        frame.set(x + 1, y + 1, .glow)
    }
}

private func drawPillar(_ frame: PixelFrame, _ e: PixelEffect, _ t: Double) {
    // A column of light falls on Pibo, widens, then thins out.
    let grow = t < 0.2 ? t / 0.2 : (t > 0.7 ? (1 - t) / 0.3 : 1)
    let half = max(0, PixelMath.round(grow * 9))
    if e.y >= 0 {
        for y in 0...e.y {
            for x in (e.x - half)...(e.x + half) {
                let edge = abs(x - e.x) >= half - 1
                if edge {
                    frame.ditherPixel(Double(x), Double(y), frame.get(x, y), .glow, 0.5)
                } else if (x + y + PixelMath.floor(t * 20)) % 4 == 0 {
                    frame.set(x, y, .sun)
                }
            }
        }
    }
    if t > 0.25 { drawSparkleRing(frame, e.x, e.y - 18, t, e.seed) }
}

private func drawSparkleRing(_ frame: PixelFrame, _ x: Int, _ y: Int, _ t: Double, _ seed: Int) {
    let rng = PixelRandom(seed + 7)
    for i in 0..<8 {
        let angle = (Double(i) / 8) * Double.pi * 2 + t * 2
        let r = 8 + t * 18 + Double(rng.int(0, 3))
        frame.stamp(STAR, PixelMath.round(Double(x) + cos(angle) * r) - 1,
                    PixelMath.round(Double(y) + sin(angle) * r * 0.6) - 1)
    }
}

private let CONFETTI_INKS: [PixelInk] = [.flowerA, .flowerB, .leafLight, .scarf, .waterLight, .sun]

private func drawConfetti(_ frame: PixelFrame, _ e: PixelEffect, _ t: Double) {
    let rng = PixelRandom(e.seed)
    for i in 0..<40 {
        let vx = rng.range(-1.4, 1.4)
        let vy = rng.range(-2.6, -0.8)
        let ink = CONFETTI_INKS[rng.int(0, CONFETTI_INKS.count - 1)]
        let age = t * 40
        let x = PixelMath.round(Double(e.x) + vx * age)
        let y = PixelMath.round(Double(e.y) + vy * age + 0.06 * age * age)
        if y > frame.height || (t > 0.8 && (i + PixelMath.floor(t * 30)) % 3 == 0) { continue }
        frame.set(x, y, ink)
        if (i + PixelMath.floor(age / 3)) % 2 == 0 { frame.set(x + 1, y, ink) }
    }
}

private func drawBoBurst(_ frame: PixelFrame, _ e: PixelEffect, _ t: Double) {
    let r = PixelMath.round(2 + t * 12)
    for i in 0..<12 {
        let angle = (Double(i) / 12) * Double.pi * 2
        let x = PixelMath.round(Double(e.x) + cos(angle) * Double(r))
        let y = PixelMath.round(Double(e.y) + sin(angle) * Double(r))
        frame.set(x, y, i % 2 == 0 ? .boLight : .glow)
    }
}

private func drawBloom(_ frame: PixelFrame, _ e: PixelEffect, _ t: Double) {
    // A flower pops open: bud, half, full, with a short sparkle.
    let stage = min(2, PixelMath.floor(t * 4))
    if stage == 0 {
        frame.stamp(["f", "g"], e.x, e.y)
    } else {
        frame.stamp(stage == 1 ? [".f.", "fuf", ".g."] : ["f.f", ".u.", "f.f"], e.x - 1, e.y)
    }
    if t > 0.4 { frame.set(e.x + 3, e.y - 2, .glow) }
}

private func drawDizzy(_ frame: PixelFrame, _ e: PixelEffect, _ t: Double) {
    for i in 0..<3 {
        let angle = t * Double.pi * 6 + (Double(i) / 3) * Double.pi * 2
        frame.stamp(STAR, PixelMath.round(Double(e.x) + cos(angle) * 12) - 1,
                    PixelMath.round(Double(e.y) + sin(angle) * 3) - 1)
    }
}

private func drawStamp(_ frame: PixelFrame, _ e: PixelEffect, _ t: Double) {
    // Thumps down slightly too big, then settles.
    let offset = t < 0.15 ? -3 : 0
    frame.stamp(STAMP, e.x - 4 + offset, e.y - 4 + offset)
}

private func drawSparkle(_ frame: PixelFrame, _ e: PixelEffect, _ t: Double) {
    if PixelMath.floor(t * 8) % 2 == 0 {
        frame.stamp(STAR, e.x - 1, e.y - 1)
    } else {
        frame.set(e.x, e.y, .glow)
    }
}

/// Effects drawn behind Pibo; everything else is drawn over the scene.
func pixelEffectIsBackdrop(_ kind: PixelEffectKind) -> Bool {
    kind == .levelPillar
}

/// Draws live effects of one layer and returns every effect still running.
func drawPixelEffects(_ frame: PixelFrame, _ effects: [PixelEffect], _ nowMs: Double,
                      _ backdrop: Bool = false) -> [PixelEffect] {
    var alive: [PixelEffect] = []
    for e in effects {
        let t = (nowMs - e.startMs) / pixelEffectDuration(e.kind)
        if t >= 1 { continue }
        alive.append(e)
        if t < 0 || pixelEffectIsBackdrop(e.kind) != backdrop { continue }
        switch e.kind {
        case .hearts: drawHearts(frame, e, t)
        case .xpPop: drawXpPop(frame, e, t)
        case .energyOrbs: drawEnergyOrbs(frame, e, t)
        case .levelPillar: drawPillar(frame, e, t)
        case .confetti: drawConfetti(frame, e, t)
        case .boBurst: drawBoBurst(frame, e, t)
        case .bloom: drawBloom(frame, e, t)
        case .dizzyStars: drawDizzy(frame, e, t)
        case .stamp: drawStamp(frame, e, t)
        case .sparkle: drawSparkle(frame, e, t)
        }
    }
    return alive
}

// --- Ambient marks that follow Pibo's state rather than a one-shot event ----------------

func drawPixelZzz(_ frame: PixelFrame, _ x: Int, _ y: Int, _ timeMs: Double) {
    let phase = PixelMath.floor(timeMs / 600) % 3
    for i in 0...phase {
        let size = i == 2 ? 4 : 3
        let zx = x + i * 4
        let zy = y - i * 5
        frame.fillRect(zx, zy, zx + size, zy + 1, .glow)
        for k in 1..<(size - 1) {
            frame.set(zx + size - 1 - k, zy + k, .glow)
        }
        frame.fillRect(zx, zy + size - 1, zx + size, zy + size, .glow)
    }
}

func drawPixelQuestion(_ frame: PixelFrame, _ x: Int, _ y: Int, _ timeMs: Double) {
    let bob = PixelMath.floor(timeMs / 500) % 2
    drawPixelText(frame, "?", x, y - bob, .bodyLight)
}

func drawPixelNotes(_ frame: PixelFrame, _ x: Int, _ y: Int, _ timeMs: Double) {
    for i in 0..<2 {
        let local = (timeMs / 900 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
        frame.stamp(NOTE, x + i * 6 + PixelMath.round(sin(local * 6) * 2),
                    y - PixelMath.round(local * 10))
    }
}

/// A streak across the night sky; returns the head position so taps can find it.
func drawPixelShootingStar(_ frame: PixelFrame, _ startX: Int, _ startY: Int, _ t: Double) -> [Int] {
    let headX = PixelMath.round(Double(startX) - t * 70)
    let headY = PixelMath.round(Double(startY) + t * 26)
    for i in 0..<22 {
        let x = headX + i
        let y = headY - PixelMath.round(Double(i) * 0.37)
        if i < 8 { frame.set(x, y, .sun) }
        else if i < 15 || i % 2 == 0 { frame.set(x, y, .glow) }
    }
    frame.stamp(STAR, headX - 1, headY - 1)
    return [headX, headY]
}

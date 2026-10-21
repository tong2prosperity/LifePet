import Foundation

// 「你的记录」's three little windows into Pibo's world: the night sky over a sleep, the
// slope a day's steps grew on, the pond the day's activity dripped into. Each picture only
// redraws recorded values; the rules behind them (stages, Core's activity intensities) come
// in as inputs, and Pibo is a fixed companion in the corner that never reacts to them.
//
// Ported from HarmonyPibo `pixel/ui/RecordWindows.ets`. Every table, threshold and formula
// is kept identical so both platforms draw the same picture; the callers
// (`HistorySleepCard`, `HistoryStepsCard`, `HistoryActivityCard`) stay on their own side.

/// ArkTS `fillRect(x, y, w, h)` — width/height, not corners, and floored like the original.
private func rect(_ frame: PixelFrame, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                  _ ink: PixelInk) {
    frame.fillRect(x, y, w, h, ink)
}

// ---------------- Sleep: the night-sky strip ----------------

let SLEEP_SKY_W: Int = 160
let SLEEP_SKY_H: Int = 42

/// The four stage colours, the same ones the legend and the detail sheet use.
let RECORD_SLEEP_STAGE_HEX: [String] = ["F8EAD8", "C3A8EF", "8DABF4", "5552A5"]
private let SLEEP_STAGE_INK: [PixelInk] = [.flowerA, .flowerB, .rain, .hillFar]
/// Band [top, height] per stage: awake highest, deep lowest, like a hypnogram.
private let SLEEP_BAND: [[Int]] = [[10, 4], [15, 5], [21, 6], [28, 8]]
private let SLEEP_BASELINE: Int = 38
private let SLEEP_GUIDE_INK: PixelInk = .skyMid
private let SLEEP_CURSOR_INK: PixelInk = .glow

/// The day palette with the night strip's own inks: the stage colours, the faint guides.
func recordSleepPalette() -> [UInt8] {
    var rgb = PixelPalette.rgb(.day)
    for (stage, hex) in RECORD_SLEEP_STAGE_HEX.enumerated() {
        setHex(&rgb, SLEEP_STAGE_INK[stage], hex)
    }
    setHex(&rgb, SLEEP_GUIDE_INK, "343C52")
    setHex(&rgb, .skyLow, "667483")
    return rgb
}

/// `"RRGGBB"` → the three bytes, written over an ink's slot in a palette.
private func setHex(_ rgb: inout [UInt8], _ ink: PixelInk, _ hex: String) {
    let i = ink.index * 3
    guard i + 2 < rgb.count else { return }
    let bytes = Array(hex.utf8)
    guard bytes.count >= 6 else { return }
    func byte(_ offset: Int) -> UInt8 {
        func nibble(_ c: UInt8) -> UInt8 {
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
            case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
            case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
            default: return 0
            }
        }
        return nibble(bytes[offset]) << 4 | nibble(bytes[offset + 1])
    }
    rgb[i] = byte(0)
    rgb[i + 1] = byte(2)
    rgb[i + 2] = byte(4)
}

/// Which stage each column shows, -1 where nothing was recorded. A column belongs to the
/// slice covering its centre; a slice too short to cover any centre still claims the column
/// it sits in, so a three-minute waking never disappears.
///
/// `slices` come from `SleepTrailGeometry.runs(segments:timeline:width: SLEEP_SKY_W)`; only
/// their exact-time `x`/`width`/`stage` are used, never the decorative contour.
func sleepSkyColumns(slices: [SleepTrailSlice], logicalW: Int = SLEEP_SKY_W) -> [Int] {
    let width = max(0, logicalW)
    guard width > 0 else { return [] }
    var columns = [Int](repeating: -1, count: width)
    var claimed = [Bool](repeating: false, count: slices.count)
    for c in 0..<width {
        let centre = Double(c) + 0.5
        for (i, slice) in slices.enumerated() {
            let x = Double(slice.x)
            if centre >= x, centre < x + Double(slice.width) {
                columns[c] = slice.stage.rawValue
                claimed[i] = true
                break
            }
        }
    }
    for (i, slice) in slices.enumerated() where !claimed[i] && slice.width > 0 {
        let centre = Double(slice.x) + Double(slice.width) / 2
        let c = max(0, min(width - 1, Int(centre.rounded(.down))))
        columns[c] = slice.stage.rawValue
    }
    return columns
}

/// The logical column a touch at `x` of `viewWidth` lands on.
func sleepSkyColumnAt(x: Double, viewWidth: Double) -> Int {
    guard viewWidth > 0 else { return 0 }
    let column = Int((x / viewWidth * Double(SLEEP_SKY_W)).rounded(.down))
    return max(0, min(SLEEP_SKY_W - 1, column))
}

private let SLEEP_MOON: [String] = [".uu", "uu.", "uu.", ".uu"]

func drawSleepSkyStrip(_ frame: PixelFrame, columns: [Int], cursor: Int, seed: Int) {
    frame.clear(.clear)
    for x in 0..<frame.width {
        for y in 1..<9 where PixelArt.hash(x, y, seed) > 0.975 {
            frame.set(x, y, .glow)
        }
    }
    frame.stamp(SLEEP_MOON, frame.width - 6, 1)
    for band in SLEEP_BAND {
        var x = 0
        while x < frame.width {
            frame.set(x, band[0] + band[1] - 1, SLEEP_GUIDE_INK)
            x += 3
        }
    }
    var x = 0
    while x < frame.width {
        frame.set(x, SLEEP_BASELINE, .skyLow)
        x += 2
    }
    for x in 0..<min(columns.count, frame.width) {
        let stage = columns[x]
        guard stage >= 0, stage < SLEEP_BAND.count else { continue }
        let band = SLEEP_BAND[stage]
        rect(frame, Double(x), Double(band[0]), 1, Double(band[1]), SLEEP_STAGE_INK[stage])
        // A thread down to the baseline, so the night reads as one line through the stages.
        guard x == 0 || columns[x - 1] != stage else { continue }
        let previous = x > 0 ? columns[x - 1] : -1
        guard previous >= 0, previous < SLEEP_BAND.count else { continue }
        let top = min(SLEEP_BAND[previous][0], band[0])
        let bottom = max(SLEEP_BAND[previous][0] + SLEEP_BAND[previous][1], band[0] + band[1])
        for y in top..<bottom {
            let ink = frame.get(x, y)
            if ink == .clear || ink == SLEEP_GUIDE_INK {
                frame.set(x, y, SLEEP_STAGE_INK[stage])
            }
        }
    }
    if cursor >= 0, cursor < frame.width {
        var y = 9
        while y <= SLEEP_BASELINE {
            frame.set(cursor, y, SLEEP_CURSOR_INK)
            y += 2
        }
    }
}

// ---------------- Steps: the slope ----------------

let STEPS_SLOPE_W: Int = 160
let STEPS_SLOPE_H: Int = 60
private let SLOPE_GROUND: Int = 52
private let SLOPE_PLANT_X: Int = 80

/// Which plant the day's total grew (chosen by the card): a stone, a sprout, a pine, a
/// tall tree.
enum StepsPlant: Int {
    case stone = 0
    case sprout = 1
    case pine = 2
    case tall = 3

    /// The card's thresholds, kept next to the drawing that uses them.
    static func forSteps(_ steps: Int) -> StepsPlant {
        if steps <= 0 { return .stone }
        if steps < 150 { return .sprout }
        if steps < 500 { return .pine }
        return .tall
    }
}

private let SLOPE_FIREFLIES: [[Int]] = [[22, 18], [41, 30], [58, 12], [100, 22], [104, 36],
                                        [140, 14], [151, 30]]

private func hillTop(_ x: Int, _ base: Double, _ amp: Double, _ period: Double,
                     _ phase: Double) -> Int {
    let wave = 0.5 + 0.5 * sin((Double(x) / period + phase) * Double.pi * 2)
    return Int((base - amp * wave).rounded())
}

private func drawPlant(_ frame: PixelFrame, _ plant: StepsPlant, _ x: Int, _ ground: Int) {
    if plant == .stone {
        rect(frame, Double(x - 3), Double(ground - 3), 7, 3, .stone)
        rect(frame, Double(x - 2), Double(ground - 4), 4, 1, .stoneLight)
        rect(frame, Double(x - 3), Double(ground - 1), 7, 1, .stoneDark)
        return
    }
    let trunk = plant == .sprout ? 5 : (plant == .pine ? 12 : 22)
    rect(frame, Double(x), Double(ground - trunk), 2, Double(trunk),
         plant == .sprout ? .leafDark : .trunk)
    if plant == .sprout {
        frame.stamp(["ll.gg", ".lgg."], x - 1, ground - trunk - 2)
        return
    }
    if plant == .pine {
        for row in 0..<18 {
            let half = 1 + row / 2
            rect(frame, Double(x + 1 - half), Double(ground - trunk - 14 + row),
                 Double(half * 2), 1, row % 4 == 0 ? .pineLight : .pineMid)
        }
        return
    }
    PixelArt.drawFoliage(frame, cx: x + 1, cy: ground - trunk - 8, rx: 12, ry: 11,
                         inks: [.treeDark, .treeMid, .treeLight], seed: 7)
}

/// `reveal` 0→1 grows the slope from the left; the plant appears past 0.6 and the fireflies
/// once it is whole. `tick` only blinks Pibo and the fireflies.
func drawStepsSlope(_ frame: PixelFrame, plant: StepsPlant, reveal: Double, tick: Int,
                    selected: Bool) {
    frame.clear(.clear)
    let grown = Int((max(0, min(1, reveal)) * Double(frame.width)).rounded())
    for x in 0..<grown {
        let far = hillTop(x, 38, 10, 96, 0.1)
        let near = hillTop(x, 48, 6, 70, 0.55)
        for y in far..<SLOPE_GROUND { frame.set(x, y, .hillFar) }
        for y in near..<SLOPE_GROUND { frame.set(x, y, .hillNear) }
        frame.set(x, near, PixelArt.hash(x, near, 3) > 0.5 ? .grassTip : .hillNear)
        for y in SLOPE_GROUND..<frame.height {
            frame.set(x, y, y == SLOPE_GROUND ? .groundLight
                     : (PixelArt.hash(x, y, 9) > 0.86 ? .groundDark : .groundMid))
        }
        if PixelArt.hash(x, 0, 5) > 0.8 { frame.set(x, SLOPE_GROUND - 1, .grassTip) }
    }
    if reveal >= 0.6 {
        drawPlant(frame, plant, SLOPE_PLANT_X, SLOPE_GROUND)
        if selected {
            var y = 4
            while y < SLOPE_GROUND {
                frame.set(SLOPE_PLANT_X + 4, y, .outline)
                y += 2
            }
        }
    }
    if reveal >= 1 {
        let pose = PiboPixelPose()
        pose.bodyStage = 0
        pose.leafGrowth = 0.6
        pose.lookX = -1
        pose.eyes = tick % 25 == 0 ? .closed : .open
        drawPiboPixel(frame, 126, Double(SLOPE_GROUND + 1), pose)
        for (index, spot) in SLOPE_FIREFLIES.enumerated() where (tick + index * 3) % 8 < 5 {
            rect(frame, Double(spot[0]), Double(spot[1]), 2, 2, .boMid)
        }
    }
}

// ---------------- Activity: the pond ----------------

let POND_W: Int = 160
let POND_H: Int = 56
private let POND_SURFACE: Int = 32
private let POND_RING_Y: Int = 43
private let POND_COLUMNS: [Double] = [0.34, 0.6, 0.86]

/// How far a column's rings reach, in logical pixels, from Core's intensity alone.
func pondRingRadius(_ amp: Double) -> Double {
    let a = max(0, min(1, amp))
    return 6 + 16 * a
}

func pondColumnX(_ index: Int) -> Int {
    let column = POND_COLUMNS.indices.contains(index) ? POND_COLUMNS[index] : POND_COLUMNS[0]
    return Int((Double(POND_W) * column).rounded())
}

private func ellipseRing(_ frame: PixelFrame, _ cx: Double, _ cy: Double, _ r: Double,
                         _ ink: PixelInk) {
    let steps = max(16, Int((r * 6).rounded()))
    for i in 0..<steps {
        let angle = Double(i) / Double(steps) * Double.pi * 2
        let x = (cx + r * cos(angle)).rounded()
        let y = (cy + r * 0.4 * sin(angle)).rounded()
        if y > Double(POND_SURFACE) { frame.set(Int(x), Int(y), ink) }
    }
}

private func drawPondBase(_ frame: PixelFrame, _ timeSec: Double) {
    frame.clear(.clear)
    for y in POND_SURFACE..<frame.height {
        let depth = Double(y - POND_SURFACE) / Double(frame.height - POND_SURFACE)
        for x in 0..<frame.width {
            frame.ditherPixel(Double(x), Double(y), .water, .waterDeep, depth * 0.9)
        }
    }
    let drift = Int((timeSec * 3).rounded(.down))
    for x in 0..<frame.width {
        frame.set(x, POND_SURFACE, .waterLight)
        if (x + drift) % 23 < 4 { frame.set(x, POND_SURFACE + 5, .waterLight) }
        if (x - drift + 11) % 31 < 3 { frame.set(x, POND_SURFACE + 11, .waterLight) }
    }
    // The near bank Pibo sits on.
    for x in 0..<30 {
        let top = POND_SURFACE - 2 + (x > 24 ? x - 24 : 0)
        var y = top
        while y < POND_SURFACE + 3 && y < frame.height {
            frame.set(x, y, y == top ? .grassTip : .groundMid)
            y += 1
        }
    }
    let pose = PiboPixelPose()
    pose.bodyStage = 0
    pose.leafGrowth = 0.6
    pose.sitting = true
    pose.lookX = 1
    let blink = Int((timeSec / 4).rounded(.down)) % 6 == 0 && timeSec.truncatingRemainder(dividingBy: 4) < 0.2
    pose.eyes = blink ? .closed : .open
    drawPiboPixel(frame, 14, Double(POND_SURFACE - 1), pose)
}

private func drawDrop(_ frame: PixelFrame, _ cx: Int, _ progress: Double) {
    let y = Int((2 + Double(POND_RING_Y - 2) * progress * progress).rounded())
    frame.set(cx, y - 2, .waterLight)
    rect(frame, Double(cx - 1), Double(y - 1), 3, 2, .water)
    frame.set(cx, y + 1, .waterDeep)
    frame.set(cx - 1, y - 1, .waterLight)
}

private func drawSplash(_ frame: PixelFrame, _ cx: Int, _ progress: Double, _ amp: Double) {
    let scale = 0.6 + 0.4 * amp
    if progress < 0.22 {
        ellipseRing(frame, Double(cx), Double(POND_RING_Y), (2 + 10 * progress) * scale + 1,
                    .waterLight)
    }
    if progress < 0.42 {
        let height = Int((sin(progress / 0.42 * Double.pi) * 7 * scale).rounded())
        for y in 0..<max(0, height) { frame.set(cx, POND_RING_Y - y, .waterLight) }
        if height > 2 {
            frame.set(cx - 1, POND_RING_Y - height, .water)
            frame.set(cx + 1, POND_RING_Y - height, .water)
        }
    }
}

/// `amps` are Core's [move, exercise, stand] intensities; nil means Core is unavailable, and
/// the pond lies still. `animate` false draws the resting rings only.
func drawActivityPond(_ frame: PixelFrame, amps: [Double]?, timeSec: Double, animate: Bool) {
    drawPondBase(frame, animate ? timeSec : 0)
    guard let amps else { return }
    for (index, amp) in amps.enumerated() where amp > 0.02 {
        let cx = pondColumnX(index)
        let rings = 1 + Int((amp * 2).rounded())
        let reach = pondRingRadius(amp)
        for ring in 0..<rings {
            ellipseRing(frame, Double(cx), Double(POND_RING_Y),
                        reach * Double(ring + 1) / Double(rings),
                        ring == rings - 1 ? .waterLight : .water)
        }
    }
    guard animate else { return }
    let phases: [Double] = [0, 0.34, 0.67]
    for (index, amp) in amps.enumerated() where amp >= 0.02 {
        let period = 4.2 + (1.6 - 4.2) * amp
        let phase = phases.indices.contains(index) ? phases[index] : 0
        let local = (timeSec / period + phase).truncatingRemainder(dividingBy: 1)
        let cx = pondColumnX(index)
        if local < 0.36 {
            drawDrop(frame, cx, local / 0.36)
        } else {
            drawSplash(frame, cx, (local - 0.36) / 0.64, amp)
        }
    }
}

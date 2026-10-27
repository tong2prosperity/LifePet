import Foundation

// Indexed palette for the pixel stage (decision 057). Every pixel in a `PixelFrame` is one
// of these inks; time of day and weather swap the whole palette instead of adding art.
//
// Ported from HarmonyPibo `entry/src/main/ets/pixel/render/PixelPalette.ets`. The tables
// are byte-identical so both platforms draw the same picture; the goldens live in
// HarmonyPibo `tools/fixtures/pixel-visual-baseline.json`.

nonisolated enum PixelInk: UInt8, CaseIterable {
    case clear = 0
    case outline = 1
    case bodyLight = 2
    case bodyMid = 3
    case bodyShade = 4
    case eye = 5
    case muzzle = 6
    case muzzleShade = 7
    case leafLight = 8
    case leafMid = 9
    case leafDark = 10
    case blush = 11
    case skyTop = 12
    case skyMid = 13
    case skyLow = 14
    case hillFar = 15
    case hillNear = 16
    case treeDark = 17
    case treeMid = 18
    case treeLight = 19
    case trunk = 20
    case groundDark = 21
    case groundMid = 22
    case groundLight = 23
    case flowerA = 24
    case flowerB = 25
    case rain = 26
    case glow = 27
    case sun = 28
    case groundShadow = 29
    case boLight = 30
    case boMid = 31
    case arm = 32
    case eyeBag = 33
    case scarf = 34
    case scarfShade = 35
    case acorn = 36
    case acornCap = 37
    case woodLight = 38
    case woodDark = 39
    case stone = 40
    case stoneDark = 41
    case water = 42
    case waterLight = 43
    case fire = 44
    case fireCore = 45
    case cloth = 46
    case clothShade = 47
    // Seasons (decision 058): autumn canopies and falling leaves, snow on the ground.
    case autumnLeaf = 48
    case autumnDeep = 49
    case snow = 50
    case snowShade = 51
    // Polish pass (decision 058): object outline, a fuller wood ramp, the dirt path, lit
    // stone, deep water, grass tips, pines, distant mist, clouds, painted sign boards, a
    // non-glowing autumn highlight, moss and berries.
    case line = 52
    case woodMid = 53
    case pathLight = 54
    case pathMid = 55
    case pathDark = 56
    case stoneLight = 57
    case waterDeep = 58
    case grassTip = 59
    case pineDark = 60
    case pineMid = 61
    case pineLight = 62
    case mist = 63
    case cloudLight = 64
    case cloudShade = 65
    case signFace = 66
    case autumnLight = 67
    case moss = 68
    case berry = 69
    // Cycling inks: each borrows its colour from a ring of the inks above and steps round
    // it with time, so water flows, fire flickers and stars twinkle without a single pixel
    // being redrawn. See `PixelPalette.cycle`.
    case waterFlowA = 70
    case waterFlowB = 71
    case waterFlowC = 72
    case fireFlickerA = 73
    case fireFlickerB = 74
    case starA = 75
    case starB = 76
    case starC = 77

    /// Inks 0–31 are hand-tuned per mood; the rest derive from the day colour.
    static let tunedCount: Int = 32
    static let count: Int = 78
    /// The first cycling ink; every ink from here up takes its colour from `cycle`.
    static let cycleFirst: Int = Int(PixelInk.waterFlowA.rawValue)

    var index: Int { Int(rawValue) }
}

nonisolated enum PixelMood: Int, CaseIterable {
    case day = 0
    case dusk = 1
    case night = 2
    case rain = 3
}

/// The three rings that step on their own clocks; a pixel's family says which one
/// recolours it.
nonisolated enum PixelCycleFamily: Int, CaseIterable {
    case water = 0
    case fire = 1
    case star = 2
}

nonisolated enum PixelPalette {
    static let cycleFamilies: Int = 3

    /// One row per mood, indexed by `PixelInk`. Clear is never drawn; its slot is a
    /// placeholder.
    private static let moodHex: [[String]] = [
        [
            "000000", "2E3B45", "FFFFFF", "E9EFF1", "C6D3D9", "454F58", "CDD7DD", "A9B8C2",
            "6FDCA8", "23A07A", "146B55", "F4B4B4", "8ED2EF", "B8E5F1", "E2F4E6", "9CCBB0",
            "7AB894", "2F6B4F", "3F8A5C", "62AE6B", "6B4B3A", "4E8B4A", "6DAA55", "9BCB6A",
            "F7E07A", "F2A0C0", "D5E8F5", "FFF3A0", "FFF6D0", "3E7040", "FFE38A", "F5B94A"
        ],
        [
            "000000", "3A2E45", "FFF4EA", "F2DCD6", "D3B4B8", "2C2733", "D9C0C4", "B79AA3",
            "8ED9A0", "3E9A6E", "235A4A", "F6A8A0", "6C6FB8", "D98C9E", "F7C49A", "B08EA8",
            "8E7A9A", "3B3F5C", "4E5A6E", "6E7E78", "5A3E3A", "4A5A50", "6A7660", "8E9468",
            "F7D27A", "F28FA8", "E8D8EE", "FFE7A0", "FFD9A0", "3A4044", "FFE08A", "F2A24A"
        ],
        [
            "000000", "141A2E", "D8E2F2", "B3C2DC", "8496B8", "0E1220", "9FAECB", "7A8AAD",
            "5FB89A", "2C7A66", "17463E", "C98AA6", "0F1736", "1D2A55", "2E3F6E", "25365A",
            "1E2E4A", "0F1E2A", "173040", "23465A", "2A2430", "1A3330", "22443C", "2F5A4A",
            "C9C27A", "B87AA0", "8EA2C8", "FFF09A", "E8EED0", "0E1C1E", "FFE38A", "E8A84A"
        ],
        [
            "000000", "2A3540", "F2F6F8", "D6E0E6", "AFBFC9", "232B33", "B9C6CF", "93A4B0",
            "5FC49A", "24876C", "135447", "DDAAB0", "7C8E9E", "9AABB8", "BCCAD2", "8AA39A",
            "6E8C80", "2A4E44", "36685A", "4E8670", "574538", "3E6A50", "55865E", "79A272",
            "D9CC80", "D995B0", "E6F0F8", "F0F0C0", "E0E6E8", "30503C", "FFE38A", "F0B04A"
        ]
    ]

    /// Day colours for inks 32–69 (character details, forest decorations, seasons).
    private static let derivedDayHex: [String] = [
        "D7E0E5", "CDBFDB", "E8705A", "B94E3E", "C98A4B", "7A5233", "C9A06A", "8A6440",
        "B7BEC2", "858F96", "5FB3D9", "A8E0F2", "FF9A3C", "FFE07A", "F2E6CF", "C9B89A",
        "E8A23C", "C2592E", "F6FAFC", "D3DEE8",
        "3A302C", "A7784B", "E6D3A0", "CBAE76", "A08452", "E0E6E8", "3D82B5", "C6E58A",
        "1F4B3B", "2D6A4C", "4E9160", "A7CDBF", "FFFFFF", "D2E4EE", "F5E5BA", "F7C75A",
        "8FBA4C", "D8485F"
    ]

    /// Inks that give off their own light keep their colour at night.
    private static let emissiveInks: Set<Int> = [PixelInk.fire.index, PixelInk.fireCore.index]

    /// Per-mood multipliers for derived inks: [r, g, b, mix-to-grey].
    private static let moodTint: [[Double]] = [
        [1, 1, 1, 0],
        [1.02, 0.9, 0.86, 0.05],
        [0.56, 0.62, 0.86, 0.1],
        [0.9, 0.94, 0.98, 0.25]
    ]

    private static let waterRing: [Int] = [PixelInk.waterLight.index, PixelInk.water.index,
                                           PixelInk.waterDeep.index]
    private static let fireRings: [[Int]] = [[PixelInk.fireCore.index, PixelInk.fire.index],
                                             [PixelInk.glow.index, PixelInk.fireCore.index]]
    private static let starRing: [Int] = [PixelInk.glow.index, PixelInk.glow.index, PixelInk.skyLow.index]

    private static let waterStepMs: Double = 260
    private static let fireStepMs: Double = 150
    private static let starStepMs: Double = 700

    static var moodCount: Int { moodHex.count }

    private static func hexByte(_ hex: String, _ offset: Int) -> Int {
        let start = hex.index(hex.startIndex, offsetBy: offset)
        let end = hex.index(start, offsetBy: 2)
        return Int(hex[start..<end], radix: 16) ?? 0
    }

    /// RGB triplets for every ink in a mood, ready for `PixelFrame.writeRGBA`.
    static func rgb(_ mood: PixelMood) -> [UInt8] {
        let row = moodHex.indices.contains(mood.rawValue) ? moodHex[mood.rawValue] : moodHex[0]
        var rgb = [UInt8](repeating: 0, count: PixelInk.count * 3)
        for ink in 0..<PixelInk.tunedCount {
            let hex = row[ink]
            rgb[ink * 3] = UInt8(hexByte(hex, 0))
            rgb[ink * 3 + 1] = UInt8(hexByte(hex, 2))
            rgb[ink * 3 + 2] = UInt8(hexByte(hex, 4))
        }
        let tint = moodTint.indices.contains(mood.rawValue) ? moodTint[mood.rawValue] : moodTint[0]
        for ink in PixelInk.tunedCount..<PixelInk.cycleFirst {
            let hex = derivedDayHex[ink - PixelInk.tunedCount]
            let emissive = emissiveInks.contains(ink)
            let r = Double(hexByte(hex, 0))
            let g = Double(hexByte(hex, 2))
            let b = Double(hexByte(hex, 4))
            let grey = (r + g + b) / 3
            let channels = [r, g, b]
            for c in 0..<3 {
                let mixed = channels[c] + (grey - channels[c]) * (emissive ? 0 : tint[3])
                let scaled = mixed * (emissive ? 1 : tint[c])
                rgb[ink * 3 + c] = UInt8(max(0, min(255, scaled.rounded())))
            }
        }
        cycle(&rgb, beat: 0)
        return rgb
    }

    /// Which ring `ink` follows, or -1 for an ink that never cycles.
    static func cycleFamily(_ ink: Int) -> Int {
        if ink < PixelInk.waterFlowA.index || ink > PixelInk.starC.index { return -1 }
        if ink <= PixelInk.waterFlowC.index { return PixelCycleFamily.water.rawValue }
        if ink <= PixelInk.fireFlickerB.index { return PixelCycleFamily.fire.rawValue }
        return PixelCycleFamily.star.rawValue
    }

    /// Bit per family (`1 << PixelCycleFamily`) whose colours differ between two beats; a
    /// `from` below zero (nothing shown yet) steps them all.
    static func cycleStepped(from: Int, to: Int) -> Int {
        if from < 0 { return (1 << cycleFamilies) - 1 }
        var mask = 0
        if from % 3 != to % 3 { mask |= 1 << PixelCycleFamily.water.rawValue }
        if (from / 3) % 2 != (to / 3) % 2 { mask |= 1 << PixelCycleFamily.fire.rawValue }
        if (from / 6) % 3 != (to / 6) % 3 { mask |= 1 << PixelCycleFamily.star.rawValue }
        return mask
    }

    /// The cycle position at `timeMs`, one number that changes whenever any ring steps.
    static func cycleBeat(_ timeMs: Double) -> Int {
        let t = max(0, timeMs)
        let water = Int(t / waterStepMs) % 3
        let fire = Int(t / fireStepMs) % 2
        let star = Int(t / starStepMs) % 3
        return water + fire * 3 + star * 6
    }

    /// Points the cycling inks of `rgb` (already filled for a mood) at their colours for
    /// `beat`.
    static func cycle(_ rgb: inout [UInt8], beat: Int) {
        let water = beat % 3
        let fire = (beat / 3) % 2
        let star = (beat / 6) % 3
        for k in 0..<3 {
            copyInk(&rgb, to: PixelInk.waterFlowA.index + k, from: waterRing[(k + water) % 3])
        }
        for k in 0..<2 {
            copyInk(&rgb, to: PixelInk.fireFlickerA.index + k, from: fireRings[k][(k + fire) % 2])
        }
        for k in 0..<3 {
            copyInk(&rgb, to: PixelInk.starA.index + k, from: starRing[(k + star) % 3])
        }
    }

    private static func copyInk(_ rgb: inout [UInt8], to: Int, from: Int) {
        rgb[to * 3] = rgb[from * 3]
        rgb[to * 3 + 1] = rgb[from * 3 + 1]
        rgb[to * 3 + 2] = rgb[from * 3 + 2]
    }

    /// Stamp glyphs shared by every hand-placed sprite fragment. "." leaves the pixel
    /// untouched.
    static func glyphInk(_ glyph: Character) -> PixelInk {
        switch glyph {
        case "o": return .outline
        case "w": return .bodyLight
        case "m": return .bodyMid
        case "s": return .bodyShade
        case "e": return .eye
        case "n": return .muzzle
        case "N": return .muzzleShade
        case "l": return .leafLight
        case "g": return .leafMid
        case "G": return .leafDark
        case "b": return .blush
        case "r": return .rain
        case "y": return .glow
        case "k": return .boLight
        case "K": return .boMid
        case "u": return .sun
        case "f": return .flowerA
        case "F": return .flowerB
        case "t": return .trunk
        case "a": return .arm
        case "v": return .eyeBag
        case "c": return .scarf
        case "C": return .scarfShade
        case "h": return .acorn
        case "H": return .acornCap
        case "d": return .woodLight
        case "D": return .woodDark
        case "q": return .stone
        case "Q": return .stoneDark
        case "z": return .water
        case "Z": return .waterLight
        case "x": return .fire
        case "X": return .fireCore
        case "j": return .cloth
        case "J": return .clothShade
        case "S": return .groundShadow
        case "p": return .autumnLeaf
        case "P": return .autumnDeep
        case "i": return .snow
        case "I": return .snowShade
        case "O": return .line
        case "M": return .woodMid
        case "T": return .pathLight
        case "U": return .pathMid
        case "V": return .pathDark
        case "L": return .stoneLight
        case "W": return .waterDeep
        case "E": return .grassTip
        case "R": return .pineDark
        case "Y": return .pineMid
        case "A": return .pineLight
        case "1": return .mist
        case "B": return .cloudLight
        case "2": return .cloudShade
        case "3": return .signFace
        case "4": return .autumnLight
        case "5": return .moss
        case "6": return .berry
        case "7": return .fireFlickerA
        case "8": return .fireFlickerB
        default: return .clear
        }
    }
}

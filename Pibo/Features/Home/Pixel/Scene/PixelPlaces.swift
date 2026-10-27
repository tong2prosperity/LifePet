import Foundation
import PiboCore

// Where things are in each scene (decision 058). Core says which places exist and what
// Pibo does there; this file says where each place stands, where Pibo's feet go, what
// can be tapped, and draws the scene's own natural places (decor draws itself).
//
// Ported from HarmonyPibo `pixel/scene/PixelPlaces.ets`.

/// How Pibo uses a spot. The motion layer picks the pose from the activity; this only
/// says whether the spot lifts Pibo onto something or hides it behind something.
enum PixelSpotKind: Int {
    case stand = 0
    /// On top of an object: `lift` pixels above the spot's ground.
    case perch = 1
    /// Inside (tent): Pibo is not drawn, only marks at the door.
    case inside = 2
    /// Behind a cover that is redrawn over Pibo.
    case behind = 3
}

struct PixelSpot {
    var place: PiboCoreDayPlace = .ground
    var x: Int = 0
    /// Pibo's feet line.
    var y: Int = 0
    var lift: Int = 0
    var kind: PixelSpotKind = .stand
    /// Which way Pibo faces there (-1 left, 1 right, 0 towards you).
    var facing: Int = 0
    /// The y used for depth: perched on a back object, Pibo still draws in front of it.
    var depth: Int = 0
}

/// `place` is the raw `PiboCoreDayPlace` value, or a `PixelHotspot` value for boxes that
/// belong to a moment rather than a Core place (the ArkTS field is a plain number too).
struct PixelPlaceBox {
    var place: Int = 0
    var x: Int = 0
    var y: Int = 0
    var w: Int = 0
    var h: Int = 0

    var dayPlace: PiboCoreDayPlace? { PiboCoreDayPlace(rawValue: Int32(clamping: place)) }
    var hotspot: PixelHotspot? { PixelHotspot(rawValue: place) }
}

/// Tap targets that are not Core places: they open sheets, or belong to a moment.
enum PixelHotspot: Int {
    case basket = 100
    /// Pibo hiding in disguise (decision 065): tapping it finds it.
    case disguise = 101
    /// The look-alikes beside a disguised Pibo, 110 + index.
    case decoy = 110
    /// A food sticker on the meal mat, 120 + index (newest first).
    case mealSticker = 120
}

struct PixelWalkBounds {
    var minX: Int = 0
    var maxX: Int = 0
    var minY: Int = 0
    var maxY: Int = 0
}

private func cx(_ layout: PixelForestLayout, _ fraction: Double) -> Int {
    PixelMath.round(Double(layout.width) / 2 + fraction * Double(layout.width))
}

/// Natural places drawn by this file, per scene, in draw order (back to front).
private let NATURAL: [[PiboCoreDayPlace]] = [
    [.bigTree, .trailSign, .mossNest, .tallGrass],
    [.fallenLog, .creekBank, .steppingStones, .reeds, .trailSign, .mossNest],
    [.hilltop, .loneTree, .bigRock, .flowerField, .trailSign, .mossNest, .tallGrass]
]

func pixelNaturalPlaces(_ scene: PiboCoreDayScene) -> [PiboCoreDayPlace] {
    NATURAL.indices.contains(Int(scene.rawValue)) ? NATURAL[Int(scene.rawValue)] : NATURAL[0]
}

/// Decor (and the two legacy ornaments) sit at fixed slots in the clearing; the boat, the
/// kite and the telescope (decision 065) at theirs in the creek and on the hill.
func pixelDecorForPlace(_ place: PiboCoreDayPlace) -> Int {
    if place.rawValue >= PiboCoreDayPlace.stool.rawValue
        && place.rawValue <= PiboCoreDayPlace.observer.rawValue {
        return Int(place.rawValue - PiboCoreDayPlace.stool.rawValue)
    }
    if place.rawValue >= PiboCoreDayPlace.boat.rawValue
        && place.rawValue <= PiboCoreDayPlace.telescope.rawValue {
        return PixelDecorID.boat.rawValue + Int(place.rawValue - PiboCoreDayPlace.boat.rawValue)
    }
    return -1
}

func pixelPlaceForDecor(_ decor: Int) -> PiboCoreDayPlace? {
    if decor >= PixelDecorID.mushroomStool.rawValue && decor <= PixelDecorID.observer.rawValue {
        return PiboCoreDayPlace(rawValue: Int32(decor + Int(PiboCoreDayPlace.stool.rawValue)))
    }
    if decor >= PixelDecorID.boat.rawValue && decor <= PixelDecorID.telescope.rawValue {
        return PiboCoreDayPlace(rawValue: Int32(decor - PixelDecorID.boat.rawValue
                                               + Int(PiboCoreDayPlace.boat.rawValue)))
    }
    return nil
}

/// The art's bounding box for a natural place (hit testing and pokes).
func pixelNaturalBox(_ layout: PixelForestLayout, _ scene: PiboCoreDayScene,
                     _ place: PiboCoreDayPlace) -> PixelPlaceBox? {
    let g = layout.groundY
    func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> PixelPlaceBox {
        var b = PixelPlaceBox()
        b.place = Int(place.rawValue)
        b.x = x
        b.y = y
        b.w = w
        b.h = h
        return b
    }
    switch scene {
    case .clearing:
        switch place {
        case .bigTree: return box(cx(layout, -0.12) - 18, g - 82, 36, 62)
        case .mossNest: return box(cx(layout, -0.05) - 12, g + 55, 24, 7)
        case .tallGrass: return box(cx(layout, 0.34) - 19, g + 40, 38, 24)
        case .trailSign: return box(cx(layout, -0.4) - 13, g + 22, 26, 34)
        default: return nil
        }
    case .creek:
        switch place {
        case .fallenLog: return box(cx(layout, 0.27) - 17, g - 15, 34, 8)
        case .creekBank: return box(cx(layout, -0.22) - 18, g + 16, 36, 16)
        case .steppingStones: return box(cx(layout, 0.12) - 8, g + 17, 18, 24)
        case .reeds: return box(cx(layout, -0.36) - 17, g + 8, 34, 26)
        case .trailSign: return box(cx(layout, -0.4) - 13, g + 36, 26, 34)
        case .mossNest: return box(cx(layout, 0.0) - 12, g + 57, 24, 7)
        default: return nil
        }
    default:
        switch place {
        case .hilltop: return box(cx(layout, 0.27) - 27, g - 36, 54, 22)
        case .loneTree: return box(cx(layout, 0.31) - 13, g - 70, 26, 36)
        case .bigRock: return box(cx(layout, -0.34) - 10, g - 8, 20, 12)
        case .flowerField: return box(cx(layout, -0.17) - 26, g + 18, 52, 18)
        case .trailSign: return box(cx(layout, -0.4) - 13, g + 30, 26, 34)
        case .mossNest: return box(cx(layout, 0.02) - 12, g + 57, 24, 7)
        case .tallGrass: return box(cx(layout, 0.34) - 19, g + 40, 38, 24)
        default: return nil
        }
    }
}

func pixelBasketBox(_ layout: PixelForestLayout) -> PixelPlaceBox {
    var box = PixelPlaceBox()
    box.place = PixelHotspot.basket.rawValue
    box.x = cx(layout, 0.17) - 6
    box.y = layout.groundY + 57
    box.w = 11
    box.h = 8
    return box
}

/// Decision 065: the picnic mat at the clearing's edge, where today's food stickers sit.
func pixelMealMatBox(_ layout: PixelForestLayout) -> PixelPlaceBox {
    var box = PixelPlaceBox()
    box.place = Int(PiboCoreDayPlace.mealMat.rawValue)
    box.x = cx(layout, 0.3) - 17
    box.y = layout.groundY + 21
    box.w = 35
    box.h = 14
    return box
}

/// Where the find out on display sits in each scene (its ground point).
func pixelFindSpot(_ layout: PixelForestLayout, _ scene: PiboCoreDayScene) -> [Int] {
    let g = layout.groundY
    switch scene {
    case .creek: return [cx(layout, -0.12), g + 9]
    case .hill: return [cx(layout, 0.12), g + 32]
    default: return [cx(layout, 0.06), g + 46]
    }
}

/// The display spot's tap target around the find standing there.
func pixelFindSpotBox(_ layout: PixelForestLayout, _ scene: PiboCoreDayScene) -> PixelPlaceBox {
    let at = pixelFindSpot(layout, scene)
    var box = PixelPlaceBox()
    box.place = Int(PiboCoreDayPlace.findSpot.rawValue)
    box.x = at[0] - 7
    box.y = at[1] - 13
    box.w = 14
    box.h = 15
    return box
}

/// Where Pibo and its look-alikes stand for a hide in disguise (decision 065): the first
/// point is Pibo's, the rest the decoys', spread over the walkable ground.
func pixelDisguiseSpots(_ layout: PixelForestLayout, _ scene: PiboCoreDayScene, _ decoys: Int,
                        _ seed: Int, _ inWater: Bool = false) -> [[Int]] {
    var bounds = pixelWalkBounds(layout, scene)
    // A fish hides in the creek itself, along the middle of the water.
    if inWater && scene == .creek {
        let band = pixelCreekBand(layout)
        bounds.minY = band[0] + 10
        bounds.maxY = band[1] - 3
    }
    let rng = PixelRandom(seed)
    var spots: [[Int]] = []
    var tries = 0
    while tries < 80 && spots.count < decoys + 1 {
        let x = rng.int(bounds.minX + 6, bounds.maxX - 6)
        let y = rng.int(bounds.minY + 2, bounds.maxY)
        if spots.allSatisfy({ abs($0[0] - x) >= 26 || abs($0[1] - y) >= 14 }) { spots.append([x, y]) }
        tries += 1
    }
    return spots
}

/// The three puddles that appear on the ground while it rains.
func pixelPuddles(_ layout: PixelForestLayout, _ scene: PiboCoreDayScene) -> [[Int]] {
    let g = layout.groundY
    if scene == .creek { return [[cx(layout, -0.05), g + 6], [cx(layout, 0.33), g + 2]] }
    return [[cx(layout, -0.15), g + 14], [cx(layout, 0.1), g + 28], [cx(layout, 0.3), g + 42]]
}

func pixelSteppingStones(_ layout: PixelForestLayout) -> [[Int]] {
    let x = cx(layout, 0.12)
    let g = layout.groundY
    return [[x, g + 20], [x + 5, g + 26], [x, g + 32], [x + 5, g + 38]]
}

/// The water's top edge in column x of the creek scene.
func pixelCreekTop(_ layout: PixelForestLayout, _ x: Int) -> Int {
    layout.groundY + 17 + PixelMath.round(sin(Double(x) / 13) * 2)
}

/// The creek's water, top and bottom (the wave of its banks left out), for routing.
func pixelCreekBand(_ layout: PixelForestLayout) -> [Int] {
    [layout.groundY + 15, layout.groundY + 35]
}

/// Season two's bridge (decision 059, "小溪那边"): its column and how far one plank reaches.
func pixelBridgeX(_ layout: PixelForestLayout) -> Int {
    cx(layout, 0.3)
}

/// Waypoints for a walk across the creek: down to the near lip, over every stepping stone,
/// up onto the other bank. Empty when the walk stays on one side; Pibo never wades. Once
/// the bridge is whole it walks straight over the bridge instead.
func pixelCreekCrossing(_ layout: PixelForestLayout, _ fromY: Int, _ toY: Int,
                        _ bridge: Bool = false) -> [[Int]] {
    let band = pixelCreekBand(layout)
    let down = fromY < band[0] && toY > band[1]
    let up = fromY > band[1] && toY < band[0]
    if !down && !up { return [] }
    if bridge {
        let x = pixelBridgeX(layout)
        let over: [[Int]] = [[x, band[0] - 2], [x, band[1] + 6]]
        return up ? Array(over.reversed()) : over
    }
    let stones = pixelSteppingStones(layout)
    var path: [[Int]] = [[stones[0][0], band[0] - 2]]
    for stone in stones { path.append([stone[0], stone[1] - 1]) }
    let last = stones[stones.count - 1]
    path.append([last[0], band[1] + 6])
    return up ? Array(path.reversed()) : path
}

/// Where Pibo's feet go for a place, or nil when the place has no spot here.
func pixelPlaceSpot(_ layout: PixelForestLayout, _ scene: PiboCoreDayScene,
                    _ place: PiboCoreDayPlace) -> PixelSpot? {
    let g = layout.groundY
    var spot = PixelSpot()
    spot.place = place
    func at(_ x: Int, _ y: Int, _ kind: PixelSpotKind = .stand, _ lift: Int = 0,
            _ facing: Int = 0) -> PixelSpot {
        spot.x = x
        spot.y = y
        spot.kind = kind
        spot.lift = lift
        spot.facing = facing
        spot.depth = spot.y
        return spot
    }
    if place == .ground { return at(cx(layout, 0), g) }
    if place == .forestEdge { return at(-24, pixelEdgeY(layout, scene), .stand, 0, -1) }
    if place == .puddles {
        let first = pixelPuddles(layout, scene)[0]
        return at(first[0], first[1])
    }
    if place == .mealMat {
        if scene != .clearing { return nil }
        let mat = pixelMealMatBox(layout)
        return at(mat.x - 16, mat.y + mat.h - 1, .stand, 0, 1)
    }
    if place == .findSpot {
        let find = pixelFindSpot(layout, scene)
        return at(find[0] - 11, find[1], .stand, 0, 1)
    }
    let decor = pixelDecorForPlace(place)
    if decor >= 0 {
        if decor <= PixelDecorID.observer.rawValue && scene != .clearing { return nil }
        if decor == PixelDecorID.boat.rawValue && scene != .creek { return nil }
        if decor > PixelDecorID.boat.rawValue && scene != .hill { return nil }
        guard let id = PixelDecorID(rawValue: decor) else { return nil }
        let origin = pixelDecorOrigin(layout, id)
        let size = pixelDecorSize(id)
        let midX = origin[0] + size[0] / 2
        let bottom = origin[1] + size[1]
        switch place {
        case .stool: return at(midX, bottom, .perch, 6)
        case .nameSign: return at(origin[0] - 12, bottom + 2, .stand, 0, 1)
        case .stonePile: return at(origin[0] + size[0] + 10, bottom + 2, .stand, 0, -1)
        case .flowerBed: return at(midX, bottom - 6, .stand, 0, 0)
        case .windmill: return at(midX + 16, bottom + 4, .stand, 0, -1)
        case .moonLamp: return at(origin[0] - 12, bottom + 2, .stand, 0, 1)
        case .pond: return at(origin[0] + size[0] + 6, bottom - 2, .stand, 0, -1)
        case .swing:
            _ = at(midX, origin[1] + 16, .perch, 0)
            spot.depth = bottom + 1
            return spot
        case .campfire: return at(origin[0] - 12, bottom, .stand, 0, 1)
        case .tent:
            _ = at(midX, bottom - 1, .inside)
            spot.depth = bottom + 1
            return spot
        case .hammock:
            _ = at(origin[0] + 13, origin[1] + 9, .perch, 0)
            spot.depth = bottom + 1
            return spot
        case .observer: return at(origin[0] - 10, bottom + 2, .stand, 0, 1)
        // In the boat: the hull is drawn over Pibo's lower half.
        case .boat: return at(midX, bottom - 3, .perch, 0, 0)
        // Holding the string, the kite away up to the left.
        case .kite: return at(origin[0] + size[0] + 6, bottom + 2, .stand, 0, -1)
        case .telescope: return at(origin[0] + size[0] + 13, bottom, .stand, 0, -1)
        default: return nil
        }
    }
    guard let box = pixelNaturalBox(layout, scene, place) else { return nil }
    let mid = box.x + box.w / 2
    switch place {
    case .bigTree: return at(mid + 14, box.y + box.h + 1, .stand, 0, -1)
    case .mossNest: return at(mid, box.y + 5, .perch, 0)
    case .tallGrass, .reeds:
        return at(mid, box.y + box.h - 2, .behind)
    case .trailSign: return at(box.x + box.w + 12, box.y + box.h + 1, .stand, 0, -1)
    case .fallenLog: return at(mid, box.y + 3, .perch, 0)
    case .creekBank: return at(mid, box.y - 1, .stand, 0, 0)
    case .steppingStones: return at(box.x + 8, box.y - 1, .stand)
    case .hilltop: return at(mid, box.y + 4, .stand)
    case .loneTree: return at(mid + 12, box.y + box.h + 1, .stand, 0, -1)
    case .bigRock: return at(mid, box.y + 2, .perch, 0)
    case .flowerField: return at(mid, box.y + box.h - 4, .stand)
    default: return at(mid, box.y + box.h)
    }
}

/// Where a hidden Pibo crouches, so its leaf just shows over the cover.
func pixelHideSpot(_ layout: PixelForestLayout, _ scene: PiboCoreDayScene,
                   _ place: PiboCoreDayPlace) -> PixelSpot? {
    guard var spot = pixelPlaceSpot(layout, scene, place) else { return nil }
    spot.kind = .behind
    switch place {
    case .bigTree: spot.x -= 14; spot.y -= 2
    case .loneTree: spot.x -= 13; spot.y -= 2
    case .nameSign: spot.x += 12; spot.y -= 3
    case .fallenLog: spot.y -= 4; spot.lift = 0
    case .bigRock: spot.y -= 3; spot.lift = 0
    case .flowerField: spot.y += 2
    case .tent: spot.kind = .inside
    default: break
    }
    return spot
}

/// The edge Pibo walks off through, along each scene's path.
func pixelEdgeY(_ layout: PixelForestLayout, _ scene: PiboCoreDayScene) -> Int {
    switch scene {
    case .creek: return layout.groundY + 6
    case .hill: return layout.groundY + 22
    default: return layout.groundY + 26
    }
}

func pixelWalkBounds(_ layout: PixelForestLayout, _ scene: PiboCoreDayScene) -> PixelWalkBounds {
    var bounds = PixelWalkBounds()
    let g = layout.groundY
    bounds.minX = PixelMath.round(Double(layout.width) * 0.14)
    bounds.maxX = PixelMath.round(Double(layout.width) * 0.86)
    switch scene {
    case .creek:
        bounds.minY = g - 12
        bounds.maxY = g + 12
    case .hill:
        bounds.minY = g - 6
        bounds.maxY = g + 44
    default:
        bounds.minY = g - 12
        bounds.maxY = g + 40
    }
    return bounds
}

// --- Natural place art -------------------------------------------------------------------

// Icons painted on the trail sign's boards: the three scenes it leads to.
private let ICON_TREE: [String] = ["..g..", ".glg.", "gglgg", ".GgG.", "..t.."]
private let ICON_WAVE: [String] = [".....", "Z..Z.", "zZzzZ", "WzWWz", "....."]
private let ICON_HILL: [String] = ["..L..", ".LqL.", ".qqQ.", "qqqQQ", "....."]
private let BASKET: [String] = [
    "...MMMMM...",
    "..M.....M..",
    ".M.......M.",
    "dMdMdMdMdMd",
    "MdMdMdMdMdM",
    "dDdDdDdDdDd",
    ".MDMDMDMDM.",
    "..DDDDDDD.."
]
private let BASKET_FULL: [String] = [
    "...MMMMM...",
    "..M.....M..",
    ".MhH.fFlgM.",
    "dMdMdMdMdMd",
    "MdMdMdMdMdM",
    "dDdDdDdDdDd",
    ".MDMDMDMDM.",
    "..DDDDDDD.."
]
private let MUSHROOM: [String] = [".cc.", "cwcC", ".jJ."]

struct PixelPlaceLook {
    /// Raw `PiboCoreDaySeason`.
    var season: Int = 1
    var snow: Bool = false
    var timeMs: Double = 0
    /// A place just tapped wiggles for a moment (raw place, -1 for none).
    var poked: Int = -1
    var pokeAge: Int = -1
    var basketFull: Bool = false
    /// Wind step, 0 or 1: the trees' top crowns lean a pixel and back.
    var wind: Int = 0

    init(season: PiboCoreDaySeason = .summer, snow: Bool = false, timeMs: Double = 0,
         poked: PiboCoreDayPlace? = nil, pokeAge: Int = -1, basketFull: Bool = false, wind: Int = 0) {
        self.season = Int(season.rawValue)
        self.snow = snow
        self.timeMs = timeMs
        self.poked = poked.map { Int($0.rawValue) } ?? -1
        self.pokeAge = pokeAge
        self.basketFull = basketFull
        self.wind = wind
    }
}

private func wiggle(_ look: PixelPlaceLook, _ place: PiboCoreDayPlace) -> Int {
    if look.poked != Int(place.rawValue) || look.pokeAge < 0 || look.pokeAge > 900 { return 0 }
    return PixelMath.floor(Double(look.pokeAge) / 90) % 2 == 0 ? 1 : -1
}

// The time steps each place moves on. Drawing and the memo key both read them, so a place
// is only repainted when its picture can actually change.
private func grassSway(_ look: PixelPlaceLook) -> Int {
    PixelMath.floor(look.timeMs / 700) % 2
}

private func reedSway(_ look: PixelPlaceLook) -> Int {
    PixelMath.floor(look.timeMs / 800) % 2
}

private func flowerSway(_ look: PixelPlaceLook) -> Int {
    PixelMath.floor(look.timeMs / 900) % 2
}

/// The trail sign's twinkle step, or −1 between twinkles.
private func signTwinkle(_ look: PixelPlaceLook) -> Int {
    let beat = PixelMath.floor(look.timeMs / 120) % 36
    return beat < 6 ? beat : -1
}

/// Radius of the ring on the water after a tap at the creek bank, or −1.
private func bankRipple(_ look: PixelPlaceLook) -> Int {
    if look.poked != Int(PiboCoreDayPlace.creekBank.rawValue) || look.pokeAge < 0
        || look.pokeAge >= 1200 { return -1 }
    return 2 + PixelMath.floor(Double(look.pokeAge) / 200)
}

private func foliage(_ look: PixelPlaceLook) -> [PixelInk] {
    look.season == 2 ? [.autumnDeep, .autumnLeaf, .autumnLight] : [.treeDark, .treeMid, .treeLight]
}

// Snow settles on the top of whatever was just drawn in a sticker.
private func snowCap(_ frame: PixelFrame, _ w: Int, _ h: Int) {
    for x in 0..<w {
        for y in 0..<h {
            if frame.get(x, y) == .clear { continue }
            frame.set(x, y, .snow)
            if (x & 1) == 0 { frame.set(x, y + 1, .snow) }
            break
        }
    }
}

// A trunk with bark: lit left edge, dark right, vertical grooves and a flared root.
private func drawTrunk(_ frame: PixelFrame, _ x: Int, _ top: Int, _ bottom: Int, _ w: Int) {
    for y in top..<bottom {
        let flare = y > bottom - 4 ? bottom - 4 - y + 1 : 0
        for dx in flare..<(w - flare) {
            var ink: PixelInk = .trunk
            if dx <= flare { ink = .woodMid }
            else if dx >= w - flare - 1 { ink = .woodDark }
            else if (dx * 5 + PixelMath.floor(Double(y) / 3)) % 7 == 0 { ink = .acornCap }
            frame.set(x + dx, y, ink)
        }
    }
}

private func drawBigTree(_ frame: PixelFrame, _ box: PixelPlaceBox, _ look: PixelPlaceLook) {
    let shift = wiggle(look, .bigTree)
    let w = box.w
    let h = box.h
    PixelArt.drawShadow(frame, cx: Double(box.x) + Double(w) / 2, y: Double(box.y + h - 1), halfW: 13)
    PixelArt.drawSticker(frame, x: Double(box.x), y: Double(box.y), w: Double(w), h: Double(h)) { t in
        let inks = foliage(look)
        let tx = w / 2 - 2
        drawTrunk(t, tx, 24, h + 1, 7)
        // A branch, and the knot hole the squirrel lives in.
        t.fillRect(tx + 6, 30, tx + 11, 32, .trunk)
        t.fillRect(tx + 6, 31, tx + 11, 32, .woodDark)
        t.fillRect(tx + 2, 36, tx + 5, 40, .line)
        t.set(tx + 2, 36, .acornCap)
        PixelArt.drawFoliage(t, cx: tx - 7 + shift, cy: 22, rx: 10, ry: 8, inks: inks, seed: 41)
        PixelArt.drawFoliage(t, cx: tx + 12 + shift, cy: 20, rx: 10, ry: 8, inks: inks, seed: 42)
        PixelArt.drawFoliage(t, cx: tx + 3 + shift + look.wind, cy: 12, rx: 14, ry: 11, inks: inks,
                             seed: 43)
        PixelArt.drawFoliage(t, cx: tx + 13, cy: 30, rx: 4, ry: 3, inks: inks, seed: 44)
        if look.snow { snowCap(t, w + 2, h + 2) }
    }
}

private func drawLoneTree(_ frame: PixelFrame, _ box: PixelPlaceBox, _ look: PixelPlaceLook) {
    let shift = wiggle(look, .loneTree)
    PixelArt.drawShadow(frame, cx: Double(box.x) + Double(box.w) / 2,
                        y: Double(box.y + box.h - 1), halfW: 9)
    PixelArt.drawSticker(frame, x: Double(box.x), y: Double(box.y), w: Double(box.w),
                         h: Double(box.h)) { t in
        let tx = box.w / 2 - 1
        drawTrunk(t, tx, 14, box.h + 1, 5)
        PixelArt.drawFoliage(t, cx: tx + 2 + shift + look.wind, cy: 11, rx: 11, ry: 9,
                             inks: foliage(look), seed: 52)
        if look.snow { snowCap(t, box.w + 2, box.h + 2) }
    }
}

private func drawMossNest(_ frame: PixelFrame, _ box: PixelPlaceBox, _ look: PixelPlaceLook) {
    // A nest seen from a little above: a woven rim of twigs around a bowl of moss.
    let w = box.w
    let h = box.h
    PixelArt.drawShadow(frame, cx: Double(box.x) + Double(w) / 2, y: Double(box.y + h - 1), halfW: 12)
    PixelArt.drawSticker(frame, x: Double(box.x), y: Double(box.y), w: Double(w), h: Double(h)) { t in
        let cx = Double(w) / 2
        let cy = 2.6
        let rx = Double(w) / 2
        let ry = 2.8
        for y in 0..<h {
            for x in 0..<w {
                let nx = (Double(x) + 0.5 - cx) / rx
                let top = (Double(y) + 0.5 - cy) / ry
                let d = nx * nx + top * top
                // The rim's outer wall drops below the ellipse to the ground, tapering slightly.
                let wall = Double(y) > cy && abs(nx) <= 1 - (Double(y) - cy) * 0.06
                if d > 1 && !wall { continue }
                var ink: PixelInk
                if d < 0.5 {
                    // Moss inside: darker toward the back wall, light at the front lip.
                    ink = top < -0.2 ? .leafDark : ((x + y) % 4 == 0 ? .leafLight : .moss)
                    if look.snow { ink = top < -0.2 ? .snowShade : .snow }
                } else {
                    let twig = (x * 2 + y * 3) % 5
                    ink = twig == 0 ? .woodLight : (twig < 3 ? .woodMid : .woodDark)
                    if y >= h - 1 { ink = .woodDark }
                    if look.snow && y < 2 && d >= 0.5 { ink = .snow }
                }
                t.set(1 + x, 1 + y, ink)
            }
        }
        if !look.snow {
            t.set(5, 1, .flowerA)
            t.set(w - 4, 2, .flowerB)
            t.set(3, h - 1, .woodLight)
            t.set(w - 2, h - 2, .woodLight)
        }
    }
}

private func drawTallGrass(_ frame: PixelFrame, _ box: PixelPlaceBox, _ look: PixelPlaceLook) {
    // Clumps of blades fanning out from a dark base, each blade curving as it rises, tips
    // catching the light; a few seed heads. Never a barcode of straight lines.
    let sway = grassSway(look)
    let poke = wiggle(look, .tallGrass) * 2
    let rng = PixelRandom(box.x * 31 + box.y)
    let bottom = box.y + box.h
    PixelArt.drawShadow(frame, cx: Double(box.x) + Double(box.w) / 2, y: Double(bottom - 1),
                        halfW: Double(PixelMath.round(Double(box.w) / 2) - 1))
    let clumps = 6
    for c in 0..<clumps {
        let baseX = box.x + 3 + PixelMath.round(Double(c) * Double(box.w - 6) / Double(clumps - 1))
            + rng.int(-1, 1)
        let back = c % 2 == 1
        let blades = 5
        for b in 0..<blades {
            let spread = Double(b) - Double(blades - 1) / 2
            let h = max(8, box.h - 4 - rng.int(0, 9) - Int(abs(spread)) * 2 - (back ? 2 : 0))
            for k in 0..<h {
                let t = Double(k) / Double(h)
                let bend = PixelMath.round(spread * t * t * 3)
                    + (t > 0.6 ? (sway + poke) * (c % 2 == 0 ? 1 : -1) : 0)
                var ink: PixelInk = back ? .leafDark : .leafMid
                if t > 0.72 { ink = back ? .leafMid : .grassTip }
                if t < 0.2 { ink = .leafDark }
                if look.snow && k == h - 1 { ink = .snow }
                frame.set(baseX + PixelMath.round(spread * 0.6) + bend, bottom - 1 - k, ink)
            }
            if b == 1 && c % 2 == 0 && !look.snow {
                let tipX = baseX + PixelMath.round(spread * 0.6) + PixelMath.round(spread * 3) + sway + poke
                frame.set(tipX, bottom - 1 - h, look.season == 2 ? .acorn : .cloth)
                frame.set(tipX, bottom - 2 - h, look.season == 2 ? .acornCap : .clothShade)
            }
        }
    }
}

private func drawReeds(_ frame: PixelFrame, _ box: PixelPlaceBox, _ look: PixelPlaceLook) {
    let sway = reedSway(look)
    let poke = wiggle(look, .reeds) * 2
    let bottom = box.y + box.h
    for i in 0..<15 {
        let x = box.x + 2 + i * 2 + (i % 2)
        let height = 15 + ((i * 7) % 9)
        for k in 0..<height {
            let lean = Double(k) > Double(height) * 0.5 ? sway + poke : 0
            var ink: PixelInk = i % 2 == 0 ? .leafDark : .leafMid
            if Double(k) > Double(height) * 0.75 && i % 2 == 1 { ink = .grassTip }
            frame.set(x + lean, bottom - 1 - k, ink)
        }
        // Cattails: a brown head on every third stem.
        if i % 3 == 0 {
            frame.fillRect(x + sway + poke, bottom - height - 4, x + sway + poke + 2,
                           bottom - height, .acornCap)
            frame.set(x + sway + poke, bottom - height - 4, .acorn)
            frame.set(x + sway + poke, bottom - height - 5, .leafDark)
        }
    }
}

private func drawTrailSign(_ frame: PixelFrame, _ box: PixelPlaceBox, _ look: PixelPlaceLook) {
    let w = box.w
    let h = box.h
    let shake = wiggle(look, .trailSign)
    PixelArt.drawShadow(frame, cx: Double(box.x) + Double(w) / 2, y: Double(box.y + h - 1), halfW: 8)
    PixelArt.drawSticker(frame, x: Double(box.x), y: Double(box.y), w: Double(w + 1), h: Double(h)) { t in
        let post = w / 2 - 1
        // Post: lit, mid and dark columns, a cap on top, stones at its foot.
        for y in 1...(h - 2) {
            t.set(post, y, .woodLight)
            t.set(post + 1, y, .woodMid)
            t.set(post + 2, y, .woodDark)
        }
        t.fillRect(post - 1, 1, post + 4, 2, .woodDark)
        t.fillRect(post, 0, post + 3, 1, .woodMid)
        // Three boards point to the three scenes: the clearing, the creek and the hill.
        drawPixelBoard(t, 2 + shake, 3, w - 3, 9, 1)
        t.stamp(ICON_TREE, 5 + shake, 5)
        t.fillRect(12 + shake, 6, 19 + shake, 7, .woodMid)
        t.fillRect(12 + shake, 8, 17 + shake, 9, .woodMid)
        drawPixelBoard(t, 1 - shake, 13, w - 4, 9, -1)
        t.stamp(ICON_WAVE, w - 10 - shake, 15)
        t.fillRect(6 - shake, 16, 13 - shake, 17, .woodMid)
        t.fillRect(8 - shake, 18, 13 - shake, 19, .woodMid)
        drawPixelBoard(t, 4 + shake, 23, w - 7, 8, 1)
        t.stamp(ICON_HILL, 7 + shake, 24)
        t.fillRect(13 + shake, 26, 18 + shake, 27, .woodMid)
        t.stamp([".LqQ", "qqQQ"], post - 4, h - 1)
        t.stamp(["Lq.", "qQQ"], post + 3, h - 1)
        if look.snow {
            t.fillRect(3, 3, w - 3, 4, .snow)
            t.fillRect(2, 13, w - 5, 14, .snow)
        }
    }
    // A twinkle now and then, so it reads as something to tap.
    let beat = signTwinkle(look)
    if beat >= 0 {
        let sx = box.x + w - 2
        let sy = box.y + 2
        frame.set(sx, sy, .glow)
        if beat > 1 && beat < 5 {
            frame.set(sx - 1, sy, .sun)
            frame.set(sx + 1, sy, .sun)
            frame.set(sx, sy - 1, .sun)
            frame.set(sx, sy + 1, .sun)
        }
    }
}

private func drawFallenLog(_ frame: PixelFrame, _ box: PixelPlaceBox, _ look: PixelPlaceLook) {
    let dy = wiggle(look, .fallenLog) > 0 ? 1 : 0
    PixelArt.drawShadow(frame, cx: Double(box.x) + Double(box.w) / 2,
                        y: Double(box.y + box.h - 1), halfW: 16)
    PixelArt.drawSticker(frame, x: Double(box.x), y: Double(box.y), w: Double(box.w),
                         h: Double(box.h)) { t in
        let y = 2 + dy
        for x in 4..<box.w {
            t.set(x, y, .woodLight)
            t.fillRect(x, y + 1, x + 1, y + 4, .woodMid)
            t.set(x, y + 4, .woodDark)
            if (x * 3) % 7 == 0 { t.set(x, y + 2, .woodDark) }
        }
        // The cut end shows its rings.
        t.stamp([".hh.", "hHHh", "hHhh", "hHHh", ".hh."], 1, y)
        // Moss on top and a little mushroom.
        t.fillRect(11, y - 1, 19, y, look.snow ? .snow : .moss)
        t.fillRect(13, y - 2, 17, y - 1, look.snow ? .snow : .leafMid)
        t.stamp(MUSHROOM, box.w - 7, y - 2)
    }
}

private func drawCreek(_ frame: PixelFrame, _ layout: PixelForestLayout, _ look: PixelPlaceLook) {
    // The stream runs across the scene: a sandy lip, deeper water in the middle, light
    // streaks drifting with the flow, and a shaded far bank.
    // The flow itself is palette cycling: ripples are drawn once in the three water-flow inks,
    // a step apart along the stream, and the colours walk round them (PixelPalette.cycle).
    let g = layout.groundY
    for x in 0..<frame.width {
        let top = pixelCreekTop(layout, x)
        let bottom = g + 33 + PixelMath.round(sin(Double(x) / 17 + 1) * 2)
        frame.set(x, top - 2, .pathMid)
        frame.set(x, top - 1, .pathLight)
        for y in top..<bottom {
            let depth = Double(y - top) / Double(bottom - top)
            var ink: PixelInk = .water
            if y == top { ink = .groundShadow }
            else if y == top + 1 { ink = .waterDeep }
            else if depth > 0.28 && depth < 0.68 { ink = .waterDeep }
            // Soft ripples: short dashes in the deep band, each one step on from the last.
            let ripple = x * 3 + y * 7
            if depth > 0.3 && depth < 0.66 && ripple % 23 < 3 {
                ink = PixelMath.ink(.waterFlowA, PixelMath.floor(Double(ripple) / 23) % 3)
            }
            if look.snow && y < top + 2 { ink = .snowShade }
            frame.set(x, y, ink)
        }
        frame.set(x, bottom, .pathLight)
        frame.set(x, bottom + 1, .pathMid)
        frame.set(x, bottom + 2, .groundDark)
        if x % 11 == 0 {
            frame.fillRect(x, top + 3 + (x % 3) * 3, x + 3, top + 4 + (x % 3) * 3,
                           PixelMath.ink(.waterFlowA, PixelMath.floor(Double(x) / 11) % 3))
        }
    }
}

private func drawSteppingStones(_ frame: PixelFrame, _ layout: PixelForestLayout,
                                _ look: PixelPlaceLook) {
    let poke = wiggle(look, .steppingStones)
    let stones = pixelSteppingStones(layout)
    for (index, stone) in stones.enumerated() {
        let dy = index == 1 ? poke : 0
        frame.fillRect(stone[0] - 4, stone[1] + 1 + dy, stone[0] + 5, stone[1] + 2 + dy, .waterLight)
        PixelArt.drawSticker(frame, x: Double(stone[0] - 3), y: Double(stone[1] - 3 + dy), w: 7, h: 4) { t in
            t.stamp(look.snow
                        ? [".iiii..", "iiiiiq.", "qqqqqQQ", ".QQQQQ."]
                        : [".LLqq..", "Lqqqqq.", "qqqqqQQ", ".QQQQQ."],
                    1, 1)
        }
    }
}

private func drawCreekBank(_ frame: PixelFrame, _ box: PixelPlaceBox, _ look: PixelPlaceLook) {
    // Pebbles on the near bank, and a ring where something tapped the water.
    frame.stamp([".Lq.", "qqQQ"], box.x + 4, box.y - 4)
    frame.stamp([".L.", "qqQ"], box.x + box.w - 8, box.y - 3)
    frame.stamp(["Lq", "qQ"], box.x + 12, box.y - 3)
    let r = bankRipple(look)
    if r >= 0 {
        let mx = box.x + box.w / 2
        let my = box.y + 8
        frame.fillRect(mx - r, my, mx + r + 1, my + 1, .waterLight)
        frame.set(mx - r - 1, my - 1, .waterLight)
        frame.set(mx + r + 1, my - 1, .waterLight)
    }
}

private let HILL_TUFT: [String] = ["E.E", "gEg"]
private let HILL_BLOOMS: [String] = [".f.F", "fuFu", ".g.g"]

private func drawHilltop(_ frame: PixelFrame, _ box: PixelPlaceBox, _ look: PixelPlaceLook) {
    // A grassy knoll: lit from the upper left, shaded on the right, rimmed in dark grass so
    // it reads as one shape against the meadow. The lone tree stands on its crest.
    let w = box.w
    PixelArt.drawSticker(frame, x: Double(box.x), y: Double(box.y), w: Double(w), h: Double(box.h),
                         outline: .groundDark) { t in
        for row in 0..<box.h {
            let ny = Double(row) / Double(box.h - 1)
            let half = PixelMath.round(
                pow(max(0, 1 - (1 - ny) * (1 - ny)), 0.6) * (Double(w) / 2))
            for x in (-half)..<half {
                let nx = Double(x) / Double(max(1, half))
                var ink: PixelInk = .groundMid
                if row < 2 || (nx < -0.2 && ny < 0.55) { ink = .groundLight }
                if nx > 0.55 || (nx > 0.3 && ny > 0.5) { ink = .groundDark }
                if look.snow && (row < 3 || (nx < 0 && ny < 0.4)) { ink = .snow }
                t.set(1 + w / 2 + x, 1 + row, ink)
            }
        }
        if !look.snow {
            t.stamp(HILL_TUFT, 9, 7)
            t.stamp(HILL_TUFT, w - 16, 5)
            t.stamp(HILL_TUFT, 20, 12)
            if look.season != 3 {
                t.stamp(HILL_BLOOMS, 13, 10)
                t.stamp(HILL_BLOOMS, w - 22, 13)
            }
        }
    }
}

private func drawBigRock(_ frame: PixelFrame, _ box: PixelPlaceBox, _ look: PixelPlaceLook) {
    PixelArt.drawShadow(frame, cx: Double(box.x) + Double(box.w) / 2,
                        y: Double(box.y + box.h - 1), halfW: 12)
    PixelArt.drawSticker(frame, x: Double(box.x - 2), y: Double(box.y), w: Double(box.w + 4),
                         h: Double(box.h)) { t in
        let w = box.w + 4
        let h = box.h
        for y in 0..<h {
            let ny = 1 - Double(y) / Double(h)
            let half = PixelMath.round((Double(w) / 2)
                                       * max(0, 1 - ny * ny * 0.8).squareRoot()
                                       * (0.85 + 0.15 * sin(Double(y) * 1.3)))
            for dx in (-half)..<half {
                var ink: PixelInk = .stone
                if Double(dx) < -Double(half) * 0.2 && Double(y) < Double(h) * 0.5 { ink = .stoneLight }
                if Double(dx) > Double(half) * 0.35 || y > h - 3 { ink = .stoneDark }
                if (dx * 7 + y * 3) % 17 == 0 { ink = .stoneDark }
                t.set(1 + w / 2 + dx, 1 + y, ink)
            }
        }
        // Moss (or snow) on its shoulders.
        for x in 4..<(w - 6) {
            for y in 0..<h {
                if t.get(1 + x, 1 + y) == .clear { continue }
                t.set(1 + x, 1 + y, look.snow ? .snow : (x % 3 == 0 ? .leafMid : .moss))
                break
            }
        }
    }
}

private func drawFlowerField(_ frame: PixelFrame, _ box: PixelPlaceBox, _ look: PixelPlaceLook) {
    let sway = flowerSway(look)
    let poke = wiggle(look, .flowerField)
    let rng = PixelRandom(733)
    for i in 0..<54 {
        let x = box.x + rng.int(0, box.w - 1)
        let y = box.y + rng.int(4, box.h - 1)
        let stem = rng.int(3, 7)
        let lean = (sway + poke) * (i % 2 == 0 ? 1 : 0)
        for k in 0..<stem {
            frame.set(x + (Double(k) > Double(stem) / 2 ? lean : 0), y - k,
                      k == 1 ? .leafLight : .leafMid)
        }
        if look.snow { continue }
        var bloom: PixelInk = i % 4 == 0 ? .flowerB
            : (i % 4 == 1 ? .flowerA : (i % 4 == 2 ? .scarf : .cloth))
        if look.season == 2 { bloom = i % 2 == 0 ? .autumnLeaf : .autumnLight }
        frame.set(x + lean, y - stem, bloom)
        frame.set(x + lean + 1, y - stem, bloom)
        frame.set(x + lean, y - stem - 1, bloom)
        frame.set(x + lean + 1, y - stem + 1, .sun)
    }
}

private func drawBasket(_ frame: PixelFrame, _ box: PixelPlaceBox, _ full: Bool) {
    PixelArt.drawShadow(frame, cx: Double(box.x) + Double(box.w) / 2,
                        y: Double(box.y + box.h - 1), halfW: 6)
    PixelArt.drawSticker(frame, x: Double(box.x), y: Double(box.y), w: 11, h: 8) { t in
        t.stamp(full ? BASKET_FULL : BASKET, 1, 1)
    }
}

private let memo = PixelMemo(capacity: 64)

private func layoutKey(_ layout: PixelForestLayout) -> String {
    "\(layout.width)x\(layout.height)@\(layout.groundY)"
}

/// Everything time does to a place's picture right now.
private func placePhase(_ place: PiboCoreDayPlace, _ look: PixelPlaceLook) -> String {
    let poke = wiggle(look, place)
    switch place {
    case .tallGrass: return "\(grassSway(look)):\(poke)"
    case .reeds: return "\(reedSway(look)):\(poke)"
    case .flowerField: return "\(flowerSway(look)):\(poke)"
    case .trailSign: return "\(signTwinkle(look)):\(poke)"
    case .creekBank: return "\(bankRipple(look))"
    case .bigTree, .loneTree: return "\(poke):\(look.wind)"
    default: return "\(poke)"
    }
}

private func drawPlace(_ frame: PixelFrame, _ layout: PixelForestLayout, _ scene: PiboCoreDayScene,
                       _ place: PiboCoreDayPlace, _ look: PixelPlaceLook) {
    guard let box = pixelNaturalBox(layout, scene, place) else { return }
    let key = "p\(scene.rawValue).\(place.rawValue)|\(layoutKey(layout))|\(look.season)\(look.snow ? "s" : "")|\(placePhase(place, look))"
    memo.draw(frame, key: key) { target in paintPlace(target, layout, box, place, look) }
}

private func paintPlace(_ frame: PixelFrame, _ layout: PixelForestLayout, _ box: PixelPlaceBox,
                        _ place: PiboCoreDayPlace, _ look: PixelPlaceLook) {
    switch place {
    case .bigTree: drawBigTree(frame, box, look)
    case .loneTree: drawLoneTree(frame, box, look)
    case .mossNest: drawMossNest(frame, box, look)
    case .tallGrass: drawTallGrass(frame, box, look)
    case .reeds: drawReeds(frame, box, look)
    case .trailSign: drawTrailSign(frame, box, look)
    case .fallenLog: drawFallenLog(frame, box, look)
    case .creekBank: drawCreekBank(frame, box, look)
    case .steppingStones: drawSteppingStones(frame, layout, look)
    case .hilltop: drawHilltop(frame, box, look)
    case .bigRock: drawBigRock(frame, box, look)
    case .flowerField: drawFlowerField(frame, box, look)
    default: break
    }
}

/// Bottom edge of a natural place, for depth against Pibo's feet.
func pixelPlaceBottom(_ layout: PixelForestLayout, _ scene: PiboCoreDayScene,
                      _ place: PiboCoreDayPlace) -> Int {
    guard let box = pixelNaturalBox(layout, scene, place) else { return 0 }
    return box.y + box.h
}

/// Natural places whose bottom is on Pibo's side of `feetY`. `front` false draws those
/// behind Pibo, true those in front. The creek's water always lies under everything.
func drawPixelPlaces(_ frame: PixelFrame, _ layout: PixelForestLayout, _ scene: PiboCoreDayScene,
                     _ look: PixelPlaceLook, _ feetY: Int, _ front: Bool) {
    if !front && scene == .creek {
        memo.draw(frame, key: "creek|\(layoutKey(layout))|\(look.snow ? "s" : "")") { target in
            drawCreek(target, layout, look)
        }
    }
    for place in pixelNaturalPlaces(scene) {
        let bottom = place == .steppingStones || place == .creekBank
            || place == .flowerField || place == .hilltop
            ? -1 : pixelPlaceBottom(layout, scene, place)
        if (bottom > feetY) == front { drawPlace(frame, layout, scene, place, look) }
    }
    let basket = pixelBasketBox(layout)
    if (basket.y + basket.h > feetY) == front {
        memo.draw(frame, key: "basket|\(layoutKey(layout))|\(look.basketFull ? 1 : 0)") { target in
            drawBasket(target, basket, look.basketFull)
        }
    }
}

/// Redraws a place over a hiding Pibo so only its leaf peeks out.
func drawPixelPlaceCover(_ frame: PixelFrame, _ layout: PixelForestLayout, _ scene: PiboCoreDayScene,
                         _ place: PiboCoreDayPlace, _ look: PixelPlaceLook) {
    drawPlace(frame, layout, scene, place, look)
}

/// Rain puddles, with rings where drops land.
func drawPixelPuddles(_ frame: PixelFrame, _ layout: PixelForestLayout, _ scene: PiboCoreDayScene,
                      _ timeMs: Double) {
    for (index, puddle) in pixelPuddles(layout, scene).enumerated() {
        let x = puddle[0]
        let y = puddle[1]
        frame.fillRect(x - 5, y, x + 6, y + 1, .water)
        frame.fillRect(x - 4, y + 1, x + 5, y + 2, .water)
        frame.fillRect(x - 3, y - 1, x + 4, y, .water)
        let ring = PixelMath.floor(timeMs / 300 + Double(index) * 2) % 4
        if ring < 3 { frame.fillRect(x - ring, y, x - ring + ring * 2 + 1, y + 1, .waterLight) }
    }
}

/// Every tappable natural place in a scene, plus the basket.
func pixelPlaceBoxes(_ layout: PixelForestLayout, _ scene: PiboCoreDayScene) -> [PixelPlaceBox] {
    var boxes: [PixelPlaceBox] = []
    for place in pixelNaturalPlaces(scene) {
        if let box = pixelNaturalBox(layout, scene, place) { boxes.append(box) }
    }
    boxes.append(pixelBasketBox(layout))
    return boxes
}

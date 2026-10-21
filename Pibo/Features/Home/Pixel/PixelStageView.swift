import Combine
import os
import PiboCore
import SwiftUI

/// Draws the pixel home stage in the same order as HarmonyOS: the cached forest, its living
/// layers, the places, the season's things, decorations, Pibo, then the front half and the
/// lights.
///
/// Ported from the `renderFrame` order in HarmonyPibo `pixel/PixelStage.ets`. The director
/// lives here too, so a frame always has Pibo's position and pose to draw; Home feeds it
/// Core's answers through `brain`.
@MainActor
final class PixelStageRenderer {
    /// Logical width the stage aims for; the integer scale follows from the view size.
    static let targetWidth = 136
    static let forestSeed = 2026
    private static let windMs: Double = 1200
    private static let windRainMs: Double = 500
    /// Changing scene: the view pans along the trail from the old scene to the new one.
    private static let travelPanMs: Double = 2500
    private static let celebrateMs: Double = 2600
    private static let dizzyMs: Double = 1800
    private static let starFlightMs: Double = 2600
    private static let starCheckMs: Double = 5000
    private static let badgeBlinkMs: Double = 720
    private static let badgeFlickerEveryMs: Double = 4700
    private static let badgeFlickerOffMs: Double = 180
    private static let foodAttentionMs: Double = 320
    private static let foodLeanMs: Double = 420
    private static let foodLineMs: Double = 760
    private static let foodSurpriseMs: Double = 900
    private static let foodLookMs: Double = 4920
    /// The pull length Core's two-stage phases are measured against.
    static let pullFullVp: Double = 90

    /// Everything the picture depends on besides time. Change one and the next frame is a
    /// full redraw; the static forest is cached per mood and wind step.
    struct Look {
        /// −1 means "whatever the clock says".
        var hour: Int = -1
        var raining = false
        var scene: PiboCoreDayScene = .clearing
        /// Raw `PiboCoreDaySeason`.
        var season: Int = Int(PiboCoreDayRules.season(month: Calendar.current.component(.month, from: Date())).rawValue)
        var snow = false
        var reduceMotion = false
        /// Core's animation state id, for the pose Pibo stands in when nothing else happens.
        var animationStateID = ""
        var piboVisible = true
        var holdPibo = false
        // Growth look (Core appearance) and today's body cues.
        var bodyStage = 2
        var leafStage = 0
        var accessoryMask = 0
        var trickMask = 0
        var leafGrowth: Double = 1
        var leafRipe = false
        var sleepBand = -1
        var flexing = false
        var mimic = 0
        // Forest decorations and health-driven details.
        var ownedDecor: [Int] = []
        var hammock = false
        var observer = false
        var grass = false
        var cake = false
        var flowers = 0
        var footprints = 0
        var windmillSpeed = 0
        var moonLamp = 0
        var stones = 1
        var beetles = 0
        var beetleSpot = false
        var beetleOnLeaf = false
        var firstMarkers = 0
        var dayCount = 1
        // Season one's things in the clearing (decision 059).
        var podFixed = false
        var sproutStage = 0
        var mailbox = 0
        // Season two, "小溪那边": bridge planks, the old pod (0 none, 1 found, 2 lit), the far light.
        var planks = 0
        var oldPod = 0
        var farLight = false
        /// Core's small-life mask (`PiboCoreAmbient`).
        var ambientMask: PiboCoreAmbient = []
        var basketFull = false
        // Decision 065: today's food stickers on the mat (encoded inks, newest first), whether
        // one is still new, and the find out on display in this scene (-1 none).
        var mealStickers: [String] = []
        var mealFresh = false
        var displayedFind = -1
        /// A verified meal's sticker just landed (HomeFoodProjection's sequence; 0 none).
        var foodLook = 0
        var foodOnRight = false

        init() {}
    }

    private var frame = PixelFrame(1, 1)
    private var staticFrames = [PixelFrame(1, 1), PixelFrame(1, 1)]
    private var staticDrawn = [false, false]
    private var staticKey = ""
    private var layout = PixelForestLayout()
    private var palette = PixelPalette.rgb(.day)
    private let imageRenderer = PixelImageRenderer()

    private(set) var scale: Int = 1
    private(set) var actor = PixelActorFrame()
    /// The layout the last frame was drawn with, for the gesture layer and the director.
    var currentLayout: PixelForestLayout { layout }

    /// Pibo's day. Home feeds it Core's answers; without a brain it simply stands there.
    let director = PixelDayDirector()
    var brain: PixelDayBrain? {
        get { directorBrain }
        set {
            directorBrain = newValue
            if let newValue { director.setBrain(newValue) }
        }
    }
    private weak var directorBrain: PixelDayBrain?

    /// Asked every few seconds at night; true when Core says a star may cross now.
    var shootingStarDue: ((Bool) -> Bool)?
    var onShootingStarCaught: (() -> Void)?
    var onHaptic: ((Double) -> Void)?

    // Scene-change pan: the old scene's last frame, the trail and the view being composed.
    private var shownScene = -1
    private var travelFrom = PixelFrame(1, 1)
    private var travelTrail = PixelFrame(1, 1)
    private var travelView = PixelFrame(1, 1)
    private var travelStart: Double = -1

    private var effects: [PixelEffect] = []
    private var anchors = PixelAmbientAnchors()
    private var patStartMs: Double = -1
    private var celebrateUntil: Double = 0
    private var dizzyUntil: Double = 0
    private var badgeBlinkUntil: Double = 0
    private var foodLookAt: Double = -1
    private var pullDistance: Double = 0
    private var releaseFrom: Double = 1
    private var releaseStartMs: Double = -1
    private var collecting = false
    private var star: StarFlight?
    private var lastStarCheck: Double = 0
    private var pokedPlace = -1
    private var pokedAt: Double = 0

    // The look being drawn this frame, for the helpers below.
    private var look = Look()
    private var now: Double = 0
    private var elapsed: Double = 0

    private final class StarFlight {
        var startMs: Double = 0
        var x = 0
        var y = 0
        var headX = 0
        var headY = 0
    }

    func mood() -> PixelMood {
        pixelMoodFor(look.hour >= 0 ? look.hour : Calendar.current.component(.hour, from: Date()), look.raining)
    }

    private func raining() -> Bool { look.raining }

    private func world() -> PixelWorldLook {
        PixelWorldLook(scene: look.scene,
                       season: PiboCoreDaySeason(rawValue: Int32(look.season)) ?? .summer,
                       snow: look.snow, wind: 0)
    }

    /// Rebuilds the frame for a view of `size` in points at `scale`. `now` is milliseconds
    /// since the stage started.
    func render(size: CGSize, scale: Int, now: Double, look: Look) -> CGImage? {
        self.scale = scale
        self.look = look
        self.now = now
        elapsed = look.reduceMotion ? 0 : now
        let pixelWidth = max(1, Int(size.width) / max(1, scale))
        let pixelHeight = max(1, Int(size.height) / max(1, scale))
        if frame.width != pixelWidth || frame.height != pixelHeight {
            frame = PixelFrame(pixelWidth, pixelHeight)
            staticFrames = [PixelFrame(pixelWidth, pixelHeight), PixelFrame(pixelWidth, pixelHeight)]
            staticDrawn = [false, false]
            staticKey = ""
            layout = pixelForestLayout(pixelWidth, pixelHeight)
            travelFrom = PixelFrame(1, 1)
            travelTrail = PixelFrame(1, 1)
            travelView = PixelFrame(1, 1)
            travelStart = -1
            shownScene = Int(look.scene.rawValue)
            refreshAnchors()
        }
        // Pibo walked off the edge and the scene changed: pan along the trail to the new one.
        if shownScene != Int(look.scene.rawValue) {
            let from = PiboCoreDayScene(rawValue: Int32(shownScene)) ?? .clearing
            beginTravel(from: from, to: look.scene)
            refreshAnchors()
        }

        let mood = mood()
        var world = self.world()
        let key = "\(mood.rawValue):\(world.key())"
        if key != staticKey {
            staticDrawn = [false, false]
            staticKey = key
        }
        // Wind: the crowns lean a pixel and back, quicker in the rain.
        let wind = look.reduceMotion ? 0 : Int(elapsed / (raining() ? Self.windRainMs : Self.windMs)) % 2
        world.wind = wind
        if !staticDrawn[wind] {
            drawPixelForestStatic(staticFrames[wind], layout, Self.forestSeed, mood, world)
            staticDrawn[wind] = true
        }
        var paletteRGB = PixelPalette.rgb(mood)
        PixelPalette.cycle(&paletteRGB, beat: PixelPalette.cycleBeat(elapsed))
        palette = paletteRGB

        let director = self.director
        director.configure(layout, look.scene)
        let directed = director.isConfigured
        let panning = travelling(now)
        let hold = panning || look.holdPibo || pullDistance > 0 || foodLookAge(now) >= 0
        let actor = directed ? director.step(now, hold: hold) : centerActor()
        self.actor = actor
        let drawn = look.piboVisible && actor.visible && !actor.inside
        let feetYD = drawn ? actor.depthY : Double(layout.groundY)
        let feetY = Int(pixelDayRound(feetYD))

        frame.copyFrom(staticFrames[wind])
        drawPixelForestLife(frame, layout, Self.forestSeed, mood, raining(), elapsed,
                            !directed || look.ambientMask.contains(.fireflies))
        if directed { drawPixelAmbientBack(frame, layout, look.ambientMask, anchors, elapsed) }
        updateShootingStar(now, mood)
        var scene = decorScene(elapsed)
        scene.swingBusy = actor.activity == .swing && actor.sway != 0
        scene.swingSway = actor.sway
        scene.windmillBoost = pokedPlace == Int(PiboCoreDayPlace.windmill.rawValue) && now - pokedAt < 2000
        // Decision 065: flying the kite, the kite leaves its stake for the sky.
        scene.kiteFlying = directed && actor.activity == .flyKite && actor.gait == .still &&
            actor.place == .kite
        scene.kiteHand = [Int(pixelDayRound(actor.x)) - 9, Int(pixelDayRound(actor.y)) - actor.lift - 22]
        let clearingHere = directed && look.scene == .clearing
        let matBehind = pixelMealMatBottom(layout) <= feetY
        var placeLook = self.placeLook(now, elapsed)
        if directed { drawPixelPlaces(frame, layout, look.scene, placeLook, feetY, false) }
        let story = seasonLook(now, elapsed, mood == .night)
        let storyHere = directed && look.scene == .clearing
        let storyTwo = seasonTwoLook(now, elapsed, mood == .night)
        let creekHere = directed && look.scene == .creek
        if storyHere { drawPixelFarLight(frame, layout, storyTwo) }
        if storyHere { drawPixelSeason(frame, layout, story, feetY, false) }
        if creekHere { drawPixelSeasonTwo(frame, layout, storyTwo, feetY, false) }
        if raining() && directed { drawPixelPuddles(frame, layout, look.scene, elapsed) }
        drawPixelDecorBack(frame, layout, scene, feetY)
        if clearingHere && matBehind { drawMealMat(elapsed) }
        if directed { drawDisplayedFind(actor, feetYD, false) }
        if directed { drawDecoys(actor, elapsed, now, false) }
        _ = drawPixelEffects(frame, effects, now, true)

        let activity = currentActivity(now)
        let x = Int(pixelDayRound(actor.x))
        let groundY = Int(pixelDayRound(actor.y)) - actor.lift
        if drawn {
            let patAge = patStartMs >= 0 ? now - patStartMs : -1
            if patAge > PIBO_PIXEL_PAT_MS { patStartMs = -1 }
            let pose = piboPixelPose(activity, timeMs: elapsed, patAgeMs: patAge,
                                     reduceMotion: look.reduceMotion, look: pixelLook(mood, actor))
            if directed {
                let input = PiboDayPoseInput()
                input.activity = actor.activity
                input.gait = actor.gait
                input.facing = actor.facing
                input.carrying = actor.carrying
                input.refusing = actor.refusing
                input.waving = actor.waving
                input.noticing = actor.noticing
                input.lying = actor.lying
                input.story = actor.story
                input.elapsedMs = actor.elapsedMs
                input.remainingMs = actor.remainingMs
                // Walking to bed: on its feet until it gets there.
                if actor.gait != .still { pose.lying = false }
                applyPiboDayPose(pose, input, elapsed, look.reduceMotion)
                // On its feet whenever it is walking, whatever it is walking to.
                if actor.gait != .still {
                    pose.lying = false
                    pose.sitting = false
                }
            }
            // Decision 060: a feeling (or a small fidget) over whatever Pibo is doing.
            var mark = PiboPixelMark.none
            var markAge: Double = 0
            if directed && actor.emote > 0 {
                mark = applyPiboEmote(pose, PiboEmote(rawValue: actor.emote) ?? .none, actor.emoteAge,
                                      look.reduceMotion)
                markAge = actor.emoteAge
            } else if directed && actor.fidget > 0 && !pose.lying {
                mark = applyPiboFidget(pose, PiboFidget(rawValue: actor.fidget) ?? .none, actor.fidgetAge,
                                       look.reduceMotion)
                markAge = actor.fidgetAge
            }
            // Decision 061: a shape it has taken replaces Pibo; a puff covers the change.
            let phase = directed ? (PixelShapePhase(rawValue: actor.formPhase) ?? .none) : .none
            let puffing = phase == .in || phase == .out
            let puff = puffing ? min(1, actor.formAge / PIXEL_SHAPE_POOF_MS) : -1
            let showForm = actor.form > 0 && (phase == .hold || phase == .stuck ||
                (phase == .in && puff >= 0.5) || (phase == .out && puff < 0.5))
            if phase == .attempt {
                // Puffing up to change: squeezed eyes, red cheeks, swelling and sagging.
                pose.eyes = .squint
                pose.blush = true
                pose.squash = look.reduceMotion ? 0.1 : 0.2 * sin(actor.formAge / 120)
            }
            if showForm {
                let formLook = PiboFormLook()
                formLook.form = PiboForm(rawValue: actor.form) ?? .none
                formLook.timeMs = elapsed
                formLook.facing = actor.facing
                formLook.moving = actor.gait != .still
                formLook.stuck = phase == .stuck
                formLook.night = mood == .night
                formLook.reduceMotion = look.reduceMotion
                formLook.badge = piboPixelBadgeFor(activity.rawValue)
                formLook.badgeCracked = !look.podFixed
                formLook.badgeLit = badgeLit(now)
                formLook.disguise = actor.hiding && director.disguise == actor.form ? 1 : 0
                drawPiboForm(frame, Double(x), Double(groundY), formLook)
            } else {
                applyInteractionPose(pose, now)
                applyFoodLook(pose, now)
                pose.badge = piboPixelBadgeFor(activity.rawValue)
                pose.badgeCracked = !look.podFixed
                pose.badgeLit = badgeLit(now)
                drawPiboPixel(frame, Double(x), Double(groundY), pose)
                if mark != .none {
                    let body = piboPixelBodySize(pose.bodyStage)
                    drawPiboPixelMark(frame, mark, Double(x),
                                      Double(groundY - Int(pixelDayRound(pose.lift)) - body[1] * 2),
                                      Double(body[0]), markAge)
                }
            }
            if puff >= 0 { drawPiboPoof(frame, Double(x), Double(groundY - 16), puff) }
            // The try fizzles out: a thin puff that comes to nothing.
            if phase == .attempt && actor.formAge > 1100 {
                drawPiboPoof(frame, Double(x), Double(groundY - 16), 0.85)
            }
            // Stuck: every so often it strains to change back, and a little puff fails.
            if phase == .stuck && actor.formAge.truncatingRemainder(dividingBy: 2400) < 300 {
                drawPiboPoof(frame, Double(x), Double(groundY - 10),
                             0.75 + actor.formAge.truncatingRemainder(dividingBy: 2400) / 1200)
            }
            if actor.hiding && actor.coverPlace >= 0 { drawCover(actor.coverPlace, scene, placeLook) }
            drawAmbientMarks(activity, pose, x, groundY, elapsed)
            if actor.noticing {
                let body = piboPixelBodySize(pose.bodyStage)
                drawPixelText(frame, "!", x + body[0] - 2, groundY - body[1] * 2 - 12, .sun)
            }
        } else if actor.inside && look.piboVisible {
            drawInsideTent(elapsed)
        }
        if directed { drawPixelPlaces(frame, layout, look.scene, placeLook, feetY, true) }
        if storyHere { drawPixelSeason(frame, layout, story, feetY, true) }
        if creekHere { drawPixelSeasonTwo(frame, layout, storyTwo, feetY, true) }
        drawPixelDecorFront(frame, layout, scene, feetY)
        if clearingHere && !matBehind { drawMealMat(elapsed) }
        if directed { drawDisplayedFind(actor, feetYD, true) }
        if directed { drawDecoys(actor, elapsed, now, true) }
        drawPixelKiteFlight(frame, scene)
        if directed { drawPixelAmbientFront(frame, layout, look.ambientMask, anchors, elapsed) }
        // The creek mirrors its far bank, then lamps and fire light whatever is near them.
        if creekHere { applyPixelReflection(frame, layout, elapsed) }
        if directed { applyPixelLight(frame, lights(mood, scene, story, storyTwo)) }
        effects = drawPixelEffects(frame, effects, now, false)
        if panning { composeTravel(now) }
        if pokedPlace >= 0 && now - pokedAt > 4000 { pokedPlace = -1 }

        return imageRenderer.image(for: frame, palette: palette)
    }

    // --- Moments and gestures the view calls in ------------------------------------------

    /// A square around Pibo and the ground, cropped from the last frame drawn.
    func snapshot() -> PixelSnapshot? {
        if frame.width <= 0 || frame.height <= 0 { return nil }
        let width = frame.width
        let side = min(width, frame.height)
        let top = max(0, min(frame.height - side, layout.groundY - Int(pixelDayRound(Double(side) * 0.7))))
        let source = frame.writeRGBA(palette)
        let left = (width - side) / 2
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        for row in 0..<side {
            let from = ((top + row) * width + left) * 4
            rgba.replaceSubrange(row * side * 4..<(row + 1) * side * 4,
                                 with: source[from..<(from + side * 4)])
        }
        return PixelSnapshot(width: side, height: side, rgba: rgba)
    }

    func playMoment(_ moment: PixelStageMoment, value: Double, source: Int) {
        let head = headPoint()
        let seed = Int(now.truncatingRemainder(dividingBy: 997)) + 1
        switch moment {
        case .patHearts:
            effects.append(makePixelEffect(.hearts, now, head[0] + 8, head[1] + 10, 0, seed))
        case .xpPop:
            if value > 0 { effects.append(makePixelEffect(.xpPop, now, head[0], head[1] - 6, value, seed)) }
        case .sourcePop, .awayOrbs:
            let from = sourcePoint(source)
            var orbs = makePixelEffect(.energyOrbs, now, from[0], from[1],
                                       moment == .awayOrbs ? max(3, min(6, value / 6)) : 2, seed)
            orbs.toX = head[0]
            orbs.toY = head[1] + 4
            orbs.ink = source == 0 ? .waterLight : (source == 1 ? .leafLight : .fire)
            effects.append(orbs)
            if value > 0 { effects.append(makePixelEffect(.xpPop, now + 700, head[0], head[1] - 6, value, seed)) }
        case .levelUp:
            effects.append(makePixelEffect(.levelPillar, now, head[0], layout.groundY, value, seed))
            effects.append(makePixelEffect(.confetti, now + 300, head[0], head[1] - 10, value, seed))
            celebrateUntil = now + Self.celebrateMs
            onHaptic?(30)
        case .wishStamp:
            effects.append(makePixelEffect(.stamp, now, head[0] + 18, head[1] - 4, 0, seed))
            effects.append(makePixelEffect(.xpPop, now + 300, head[0], head[1] - 6, value, seed))
            patStartMs = now
        case .heartUp:
            effects.append(makePixelEffect(.hearts, now, head[0], head[1] + 6, 0, seed))
            effects.append(makePixelEffect(.hearts, now + 250, head[0] - 8, head[1] + 8, 0, seed + 3))
        case .boCollected:
            effects.append(makePixelEffect(.boBurst, now, head[0], head[1] - 8, 0, seed))
        case .dizzy:
            dizzyUntil = now + Self.dizzyMs
            effects.append(makePixelEffect(.dizzyStars, now, head[0], head[1] + 2, 0, seed))
        case .starWish:
            celebrateUntil = now + 1200
            effects.append(makePixelEffect(.sparkle, now, head[0] - 10, head[1] - 4, 0, seed))
            if value > 0 { effects.append(makePixelEffect(.xpPop, now + 200, head[0], head[1] - 6, value, seed)) }
        case .bloom:
            effects.append(makePixelEffect(.bloom, now, head[0] + 24, layout.groundY + 8, 0, seed))
        case .celebrate:
            celebrateUntil = now + Self.celebrateMs
            effects.append(makePixelEffect(.confetti, now, head[0], head[1] - 10, 0, seed))
        }
    }

    /// A finger landed on Pibo: it stops where it is, so a moving Pibo can still be patted.
    func touched(_ at: Double) { director.touched(at) }

    /// A tap on a place, the basket or a decoration: it answers with a little wobble.
    func poke(_ place: Int, _ at: Double) {
        pokedPlace = place
        pokedAt = at
    }

    /// A finger went up on the leaf. `offsetY` is the drag, negative upwards.
    func leafPan(_ offsetY: Double, ripe: Bool) {
        if collecting { return }
        if !ripe {
            // Decision 048: an unripe bo answers a pull without letting go — it stretches a
            // little against the grip and springs back on release.
            pullDistance = min(Self.pullFullVp * 0.3, max(0, -offsetY) * 0.35)
            return
        }
        pullDistance = max(0, -offsetY)
        if PiboBoContainer.pullPhase(ripe: 1, distance: pullDistance) >= 2 {
            onHaptic?(12)
        }
    }

    func leafPanEnd() {
        if collecting { return }
        if pullDistance > 0 {
            releaseFrom = min(1, pullDistance / Self.pullFullVp)
            releaseStartMs = now
        }
        pullDistance = 0
    }

    /// A star was caught: a sparkle where it was, then Home's callback.
    func catchStar() {
        guard let star else { return }
        self.star = nil
        effects.append(makePixelEffect(.sparkle, now, star.headX, star.headY, 0, 3))
        onShootingStarCaught?()
    }

    var starVisible: Bool { star != nil }

    /// The sky position of the falling star, for the tap target.
    var starHead: (x: Int, y: Int) {
        guard let star else { return (0, 0) }
        return (star.headX, star.headY)
    }

    /// A glance makes the badge blink (decision 062).
    func glance() {
        badgeBlinkUntil = now + Self.badgeBlinkMs
    }

    /// A verified meal's sticker just landed: Pibo looks at it for a few seconds.
    func foodLookLanded() {
        foodLookAt = look.foodLook > 0 ? now : -1
    }

    // --- Helpers -------------------------------------------------------------------------

    private func placeLook(_ now: Double, _ elapsed: Double) -> PixelPlaceLook {
        var look = PixelPlaceLook(season: PiboCoreDaySeason(rawValue: Int32(self.look.season)) ?? .summer,
                                  snow: self.look.snow, timeMs: elapsed, basketFull: self.look.basketFull,
                                  wind: Int(elapsed / (raining() ? Self.windRainMs : Self.windMs)) % 2)
        look.poked = pokedPlace
        look.pokeAge = pokedPlace >= 0 ? Int(now - pokedAt) : -1
        return look
    }

    private func seasonLook(_ now: Double, _ elapsed: Double, _ night: Bool) -> PixelSeasonLook {
        var look = PixelSeasonLook()
        look.podFixed = self.look.podFixed
        look.sprout = self.look.sproutStage
        look.mailbox = self.look.mailbox
        look.timeMs = elapsed
        look.night = night
        look.snow = self.look.snow
        look.poked = pokedPlace
        look.pokeAge = pokedPlace >= 0 ? Int(now - pokedAt) : -1
        return look
    }

    private func seasonTwoLook(_ now: Double, _ elapsed: Double, _ night: Bool) -> PixelSeasonTwoLook {
        var look = PixelSeasonTwoLook()
        look.planks = self.look.planks
        look.oldPodFound = self.look.oldPod >= 1
        look.oldPodLit = self.look.oldPod >= 2
        look.farLight = self.look.farLight
        look.timeMs = elapsed
        look.night = night
        look.snow = self.look.snow
        look.poked = pokedPlace
        look.pokeAge = pokedPlace >= 0 ? Int(now - pokedAt) : -1
        return look
    }

    private func decorScene(_ timeMs: Double) -> PixelDecorScene {
        var scene = PixelDecorScene()
        // Decorations, ornaments, story traces and markers belong to the clearing.
        let clearing = look.scene == .clearing
        // `ownedDecor` is already this scene's (Core ids); the creek and hill keep theirs.
        scene.owned = look.ownedDecor.map { pixelDecorFromCore($0) }.filter { $0 >= 0 }
        scene.hammock = clearing && look.hammock
        scene.observer = clearing && look.observer
        scene.grass = clearing && look.grass
        scene.cake = clearing && look.cake
        scene.flowers = clearing ? look.flowers : 0
        scene.footprints = look.footprints
        scene.windmillSpeed = look.windmillSpeed
        scene.moonLamp = look.moonLamp
        scene.stones = look.stones
        scene.beetles = clearing ? look.beetles : 0
        scene.beetleSpot = look.beetleSpot
        scene.beetleOnLeaf = look.beetleOnLeaf
        scene.firstMarkers = clearing ? look.firstMarkers : 0
        scene.dayCount = look.dayCount
        scene.mood = mood()
        scene.timeMs = timeMs
        return scene
    }

    private func pixelLook(_ mood: PixelMood, _ actor: PixelActorFrame) -> PiboPixelLook {
        let value = PiboPixelLook()
        // Idle tricks and workout mimics play only while Pibo stands around with nothing to do.
        let idle = actor.activity == .idle && actor.gait == .still && actor.carrying < 0
        value.bodyStage = look.bodyStage
        value.leafStage = look.leafStage
        value.accessoryMask = look.accessoryMask
        value.trickMask = idle ? look.trickMask : 0
        value.leafGrowth = look.leafRipe ? 1 : look.leafGrowth
        value.leafRipe = look.leafRipe && !collecting
        // Core's night-glow unlock shows only after dark.
        value.nightGlow = (look.accessoryMask & 8) != 0 && mood == .night
        value.sleepBand = look.sleepBand
        value.flexing = look.flexing
        value.mimic = idle ? (PiboPixelMimic(rawValue: look.mimic) ?? .none) : .none
        return value
    }

    private func currentActivity(_ now: Double) -> PiboPixelActivity {
        if now < celebrateUntil { return .celebrate }
        return piboPixelActivity(look.animationStateID)
    }

    private func centerActor() -> PixelActorFrame {
        let actor = PixelActorFrame()
        actor.x = Double(layout.width) / 2
        actor.y = Double(layout.groundY)
        actor.depthY = Double(layout.groundY)
        return actor
    }

    /// The badge's lens: steady once the pod is fixed; before that the cracked lens drops out
    /// for a moment every few seconds. A glance blinks it either way.
    private func badgeLit(_ now: Double) -> Bool {
        if now < badgeBlinkUntil { return Int((badgeBlinkUntil - now) / 120) % 2 == 0 }
        if look.podFixed || look.reduceMotion { return true }
        return now.truncatingRemainder(dividingBy: Self.badgeFlickerEveryMs) > Self.badgeFlickerOffMs
    }

    /// How long ago the food sticker landed, while Pibo is still looking at it (else -1).
    private func foodLookAge(_ now: Double) -> Double {
        let age = foodLookAt >= 0 ? now - foodLookAt : -1
        return age >= 0 && age < Self.foodLookMs ? age : -1
    }

    /// Pibo stops, turns to the sticker and leans in; surprised when its line appears.
    private func applyFoodLook(_ pose: PiboPixelPose, _ now: Double) {
        let age = foodLookAge(now)
        if age < 0 { return }
        let side: Double = look.foodOnRight ? 1 : -1
        pose.lookX = side
        if age >= Self.foodAttentionMs && !look.reduceMotion {
            pose.lean = side * pixelDayRound(2 * min(1, (age - Self.foodAttentionMs) / Self.foodLeanMs))
        }
        if age >= Self.foodLineMs && age < Self.foodLineMs + Self.foodSurpriseMs {
            pose.eyes = .wide
            pose.mouth = .open
        }
    }

    private func applyInteractionPose(_ pose: PiboPixelPose, _ now: Double) {
        if now < dizzyUntil {
            pose.eyes = .dizzy
            pose.lean = Int(now / 120) % 2 == 0 ? -2 : 2
        }
        if releaseStartMs >= 0 {
            // Release: the stretched leaf snaps back over a few frames.
            let age = now - releaseStartMs
            pose.leafPull = releaseFrom * max(0, 1 - age / 300)
            if age > 900 { releaseStartMs = -1 }
            return
        }
        if pullDistance > 0 { pose.leafPull = min(1, pullDistance / Self.pullFullVp) }
    }

    private func drawAmbientMarks(_ activity: PiboPixelActivity, _ pose: PiboPixelPose, _ cx: Int,
                                  _ groundY: Int, _ elapsed: Double) {
        let size = piboPixelBodySize(pose.bodyStage)
        let headY = groundY - size[1] * 2
        if activity == .sleeping {
            drawPixelZzz(frame, cx + size[0] + 4, headY + 4, elapsed)
        } else if activity == .dataUnknown {
            drawPixelQuestion(frame, cx + size[0], headY - 4, elapsed)
        }
        if pose.trick == PiboPixelTrick.hum.rawValue { drawPixelNotes(frame, cx + size[0] - 2, headY - 2, elapsed) }
    }

    private func headPoint() -> [Int] {
        let size = piboPixelBodySize(look.bodyStage)
        let directed = director.isConfigured
        let x = directed ? Int(pixelDayRound(actor.x)) : Int(pixelDayRound(Double(layout.width) / 2))
        let feet = directed ? Int(pixelDayRound(actor.y)) - actor.lift : layout.groundY
        return [x, feet - size[1] * 2 - 6]
    }

    private func sourcePoint(_ source: Int) -> [Int] {
        let fractions: [Double] = [0.2, 0.42, 0.64]
        let fx = fractions[max(0, min(2, source))]
        return [Int(pixelDayRound(Double(layout.width) * fx)), Int(pixelDayRound(Double(layout.height) * 0.12))]
    }

    private func drawMealMat(_ elapsed: Double) {
        drawPixelMealMat(frame, layout, look.mealStickers, look.mealFresh, elapsed)
    }

    /// The find out on display stands at its spot, unless Pibo has it in its hands right now.
    private func drawDisplayedFind(_ actor: PixelActorFrame, _ feetY: Double, _ front: Bool) {
        if look.displayedFind < 0 || actor.carrying == look.displayedFind { return }
        let at = pixelFindSpot(layout, look.scene)
        if (Double(at[1]) > feetY) != front { return }
        let half = PIXEL_FIND_SIZE / 2
        // A little stump to stand it on, so it reads as put out on purpose.
        PixelArt.drawShadow(frame, cx: Double(at[0]), y: Double(at[1]), halfW: 5)
        frame.fillRect(at[0] - 4, at[1] - 4, 9, 1, .woodLight)
        frame.fillRect(at[0] - 4, at[1] - 3, 9, 2, .woodMid)
        frame.fillRect(at[0] - 4, at[1] - 1, 9, 1, .woodDark)
        frame.set(at[0] - 1, at[1] - 4, .acornCap)
        drawPixelFind(frame, look.displayedFind, at[0] - half, at[1] - 4 - PIXEL_FIND_SIZE)
    }

    /// A disguised Pibo's look-alikes: the same thing with no face. A tapped one wobbles.
    private func drawDecoys(_ actor: PixelActorFrame, _ elapsed: Double, _ now: Double, _ front: Bool) {
        let director = self.director
        if director.disguise <= 0 { return }
        for (index, spot) in director.decoys.enumerated() {
            if (Double(spot[1]) > actor.depthY) != front { continue }
            let poked = pokedPlace == PixelHotspot.decoy.rawValue + index && now - pokedAt < 700
            let look = PiboFormLook()
            look.form = PiboForm(rawValue: director.disguise) ?? .none
            look.timeMs = elapsed
            look.disguise = 2
            look.reduceMotion = self.look.reduceMotion
            let wobble = poked && !self.look.reduceMotion
                ? (Int((now - pokedAt) / 90) % 2 == 0 ? -1 : 1) : 0
            drawPiboForm(frame, Double(spot[0] + wobble), Double(spot[1]), look)
        }
    }

    /// Hiding: the place is drawn again over Pibo so only its leaf (and maybe an eye) peeks out.
    private func drawCover(_ place: Int, _ scene: PixelDecorScene, _ look: PixelPlaceLook) {
        if let dayPlace = PiboCoreDayPlace(rawValue: Int32(place)) {
            let decor = pixelDecorForPlace(dayPlace)
            if decor >= 0, let id = PixelDecorID(rawValue: decor) {
                let origin = pixelDecorOrigin(layout, id)
                drawPixelDecorAt(frame, id, origin[0], origin[1], scene)
                return
            }
            drawPixelPlaceCover(frame, layout, self.look.scene, dayPlace, look)
        }
    }

    /// Asleep in the tent: two feet at the door and the Zzz drifting out.
    private func drawInsideTent(_ elapsed: Double) {
        guard let door = pixelPlaceSpot(layout, look.scene, .tent) else { return }
        frame.stamp([".ww.", "wwwm", ".mm."], door.x - 5, door.y - 3)
        frame.stamp([".ww.", "wwwm", ".mm."], door.x + 1, door.y - 3)
        drawPixelZzz(frame, door.x + 6, door.y - 14, elapsed)
    }

    // After dark: the campfire, a full moon lamp and the pods' working lamps.
    private func lights(_ mood: PixelMood, _ scene: PixelDecorScene, _ story: PixelSeasonLook,
                        _ storyTwo: PixelSeasonTwoLook) -> [PixelLightSource] {
        var lights: [PixelLightSource] = []
        if mood != .night && mood != .dusk { return lights }
        for light in pixelDecorLights(layout, scene) where light.count >= 3 {
            lights.append(pixelLightSource(light[0], light[1], light[2]))
        }
        if mood != .night { return lights }
        if look.scene == .clearing && story.podFixed {
            let tip = pixelSeasonAntennaTip(layout)
            lights.append(pixelLightSource(tip[0] + 1, tip[1] + 1, 8))
        }
        if look.scene == .creek && storyTwo.oldPodFound && storyTwo.oldPodLit {
            let lamp = pixelOldPodLamp(layout)
            lights.append(pixelLightSource(lamp[0], lamp[1], 9))
        }
        return lights
    }

    // --- Shooting stars ------------------------------------------------------------------

    private func updateShootingStar(_ now: Double, _ mood: PixelMood) {
        if let star {
            let t = (now - star.startMs) / Self.starFlightMs
            if t >= 1 {
                self.star = nil
                return
            }
            let head = drawPixelShootingStar(frame, star.x, star.y, t)
            star.headX = head[0]
            star.headY = head[1]
            return
        }
        guard let due = shootingStarDue, now - lastStarCheck >= Self.starCheckMs, !look.reduceMotion else { return }
        lastStarCheck = now
        if !due(mood == .night) { return }
        let flight = StarFlight()
        flight.startMs = now
        flight.x = Int(pixelDayRound(Double(layout.width) * 0.8))
        flight.y = Int(pixelDayRound(Double(layout.horizonY) * 0.18))
        star = flight
    }

    // --- Scene travel --------------------------------------------------------------------

    private func travelling(_ now: Double) -> Bool {
        if travelStart < 0 { return false }
        if now - travelStart < Self.travelPanMs { return true }
        travelStart = -1
        return false
    }

    /// Pibo has walked off the edge and the scene changed: keep the old scene's last frame and
    /// pan from it along a stretch of trail to the new one. Reduce Motion keeps the hard cut.
    private func beginTravel(from: PiboCoreDayScene, to: PiboCoreDayScene) {
        shownScene = Int(to.rawValue)
        if look.reduceMotion || frame.width <= 0 || travelStart >= 0 { return }
        if travelFrom.width != frame.width || travelFrom.height != frame.height {
            travelFrom = PixelFrame(frame.width, frame.height)
            travelTrail = PixelFrame(frame.width, frame.height)
            travelView = PixelFrame(frame.width, frame.height)
        }
        travelFrom.copyFrom(frame)
        var trail = world()
        trail.scene = PIXEL_TRAIL_SCENE
        trail.trailFrom = Int(from.rawValue)
        trail.trailTo = Int(to.rawValue)
        drawPixelForestStatic(travelTrail, layout, Self.forestSeed, mood(), trail)
        travelStart = now
    }

    /// Lays [new scene | trail | old scene] side by side and looks at the part the pan has
    /// reached: Pibo left through the left edge, so the view follows to the left. The sky is
    /// too far away to move; it turns into the new scene's sky halfway.
    private func composeTravel(_ now: Double) {
        let t = min(1, (now - travelStart) / Self.travelPanMs)
        let eased = t * t * (3 - 2 * t)
        let w = frame.width
        let offset = Int(pixelDayRound((1 - eased) * Double(w) * 2))
        let fresh = frame.data
        let trail = travelTrail.data
        let old = travelFrom.data
        let sky = t < 0.5 ? old : fresh
        var view = travelView.data
        for y in 0..<frame.height {
            let row = y * w
            if y < layout.horizonY {
                for vx in 0..<w { view[row + vx] = sky[row + vx] }
                continue
            }
            for vx in 0..<w {
                let x = offset + vx
                if x < w {
                    view[row + vx] = fresh[row + x]
                } else if x < w * 2 {
                    view[row + vx] = trail[row + x - w]
                } else {
                    view[row + vx] = old[row + x - w * 2]
                }
            }
        }
        travelView.data = view
        frame.copyFrom(travelView)
    }

    // Where small life lives in this scene: the squirrel's tree, water for fish, flowers.
    private func refreshAnchors() {
        var anchors = PixelAmbientAnchors()
        let g = layout.groundY
        let scene = look.scene
        let tree = pixelNaturalBox(layout, scene, scene == .hill ? .loneTree : .bigTree)
        if let tree {
            anchors.treeHole = scene == .hill ? [tree.x + 12, tree.y + 18] : [tree.x + 14, tree.y + 30]
        }
        if scene == .creek {
            if let bank = pixelNaturalBox(layout, .creek, .creekBank) {
                anchors.water = [bank.x + bank.w / 2, bank.y + 8]
            }
        } else if scene == .clearing && look.ownedDecor.contains(PixelDecorID.pond.rawValue) {
            let pond = pixelDecorOrigin(layout, .pond)
            anchors.water = [pond[0] + 12, pond[1] + 4]
        }
        if scene == .hill {
            if let field = pixelNaturalBox(layout, .hill, .flowerField) {
                anchors.flowers = [[field.x + 14, field.y + 10], [field.x + field.w - 12, field.y + 12]]
            }
        } else if scene == .clearing && look.ownedDecor.contains(PixelDecorID.flowerBed.rawValue) {
            let bed = pixelDecorOrigin(layout, .flowerBed)
            anchors.flowers = [[bed[0] + 6, bed[1]], [bed[0] + 16, bed[1] + 2]]
        } else {
            anchors.flowers = [[Int(pixelDayRound(Double(layout.width) * 0.3)), g + 24],
                               [Int(pixelDayRound(Double(layout.width) * 0.7)), g + 30]]
        }
        anchors.squirrelPokedAt = self.anchors.squirrelPokedAt
        anchors.fishPokedAt = self.anchors.fishPokedAt
        self.anchors = anchors
    }
}

/// Hosts the pixel stage, ticking it at the approved rate and scaling by a whole number.
struct PixelStageView: View {
    var look: PixelStageRenderer.Look
    var debugHour: Int?

    @State private var image: CGImage?
    @State private var scale: Int = 3
    @State private var start = Date()
    #if DEBUG
    @State private var day: HomeDayController?
    #endif

    private let renderer = PixelStageRenderer()
    private let timer = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.95, green: 0.96, blue: 0.94)
                if let image {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: CGFloat(image.width * scale),
                               height: CGFloat(image.height * scale))
                }
            }
            .onAppear {
                redraw(size: proxy.size)
                #if DEBUG
                startDay(proxy.size)
                #endif
            }
            .onChange(of: proxy.size) { _, size in redraw(size: size) }
        }
        .ignoresSafeArea()
        .onReceive(timer) { _ in
            let now = Date().timeIntervalSince(start) * 1000
            var current = look
            if let debugHour { current.hour = debugHour }
            image = renderer.render(size: lastSize, scale: scale, now: now, look: current)
        }
        .onDisappear {
            #if DEBUG
            day?.stop()
            #endif
        }
    }

    @State private var lastSize: CGSize = .zero

    private func redraw(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        lastSize = size
        scale = max(1, Int(size.width) / PixelStageRenderer.targetWidth)
        var current = look
        if let debugHour { current.hour = debugHour }
        image = renderer.render(size: size, scale: scale, now: 0, look: current)
    }

    #if DEBUG
    /// A standalone stage has no Home around it: give the director a plain environment so
    /// Pibo still lives its day (walks, sits, hides) while the art is being worked on.
    private func startDay(_ size: CGSize) {
        guard day == nil else { return }
        let days = PiboDayStore()
        let growth = GrowthStore()
        let controller = HomeDayController(director: renderer.director)
        let hour = debugHour ?? Calendar.current.component(.hour, from: Date())
        var deps = HomeDayDependencies(
            stateID: { "stable" },
            hour: { Double(hour) },
            weather: { .clear },
            ownedDecor: { [] },
            hammock: { false },
            observer: { false },
            growth: { growth },
            days: { days },
            dayCount: { 3 },
            stepsToday: { 4200 },
            hasStepsData: { true },
            sleepHours: { 7.4 },
            mindfulMinutes: { 0 },
            lastWorkout: { nil },
            overlays: { HomeDayOverlays() },
            appActive: { true },
            voiceBusy: { false },
            decorLine: { _ in },
            speak: { line in LPLog.day.info("\(line.text, privacy: .public)") },
            boCollected: { 2 },
            bodyBands: { [1, 1] },
            claimStoryLine: { true },
            setStoryWaiting: { _ in },
            lastMealAt: { -1 },
            mealsToday: { [] },
            openMeal: { _, _ in }
        )
        deps.appActive = { true }
        controller.bind(deps)
        renderer.brain = controller
        day = controller
        controller.start()
        controller.onStageLayout(renderer.currentLayout)
    }
    #endif
}

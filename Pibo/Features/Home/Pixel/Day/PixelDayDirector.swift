import Foundation
import PiboCore

// Plays Pibo's day on the stage (decision 058). Core decides what Pibo does next, where
// and for how long (through `PixelDayBrain`); the director turns each decision into a
// short script of beats — walk there, do it, maybe roam — and runs scripted moments:
// noticing you, greeting, hiding, exploring off-screen, travelling between scenes.
// Walking speed and the shape of each path are presentation and live here.
//
// Ported from HarmonyPibo `pixel/day/PixelDayDirector.ets`.

/// What Core chose for Pibo to do next.
final class PixelDayPlan {
    var activity: PiboDayActivity = .idle
    var place: PiboCoreDayPlace = .ground
    var durationMs: Double = 12000
    var eager = false
    /// A find Pibo has in its hands while it does this (decision 065's PlayFind), or −1.
    var carry = -1

    init() {}
}

/// What the director needs from outside: Core's next choice and a few facts.
protocol PixelDayBrain: AnyObject {
    /// Core's `day_choose`/`day_invite`: what to do after `previous`.
    func next(previous: PiboDayActivity) -> PixelDayPlan?
    /// Tired or sleepy Pibo walks slowly everywhere.
    func slow() -> Bool
}

/// What the director tells the stage about.
struct PixelDayEvents {
    var onFindPresented: ((Int) -> Void)?
    var onHideTimedOut: (() -> Void)?
    var onArrivedBack: ((Int) -> Void)?
    var onSceneSwitch: (() -> Void)?
    /// An activity Pibo chose (or was invited to) ran to its end.
    var onActivityDone: ((PiboDayActivity) -> Void)?
    /// Decision 061: the form did not change back at the end.
    var onShapeStuck: ((Int) -> Void)?
    /// A stuck form came back, helped by you or by itself.
    var onShapeBack: ((_ form: Int, _ helped: Bool) -> Void)?
}

/// One step of a season beat (decision 059): walk somewhere, act something out, slip
/// inside the pod for a moment, or run a callback (a line, a prop appearing).
enum PixelStoryStepKind: Int {
    case walk = 0
    case act = 1
    case inside = 2
    case teleport = 3
    case call = 4
}

final class PixelStoryStep {
    var kind: PixelStoryStepKind = .act
    var x: Double = 0
    var y: Double = 0
    var gait: PiboDayGait = .walk
    var pose: PiboStoryPose = .none
    var durationMs: Double = 0
    var facing: Double = 0
    /// Set or clear what Pibo holds when the step starts (-2 leaves it).
    var carry = -2
    var call: (() -> Void)?

    init() {}
}

func pixelStoryWalk(_ x: Double, _ y: Double, gait: PiboDayGait = .walk) -> PixelStoryStep {
    let step = PixelStoryStep()
    step.kind = .walk
    step.x = x
    step.y = y
    step.gait = gait
    return step
}

func pixelStoryAct(_ pose: PiboStoryPose, _ durationMs: Double, facing: Double = 0,
                   carry: Int = -2) -> PixelStoryStep {
    let step = PixelStoryStep()
    step.kind = .act
    step.pose = pose
    step.durationMs = durationMs
    step.facing = facing
    step.carry = carry
    return step
}

func pixelStoryInside(_ durationMs: Double, carry: Int = -2) -> PixelStoryStep {
    let step = PixelStoryStep()
    step.kind = .inside
    step.durationMs = durationMs
    step.carry = carry
    return step
}

func pixelStoryTeleport(_ x: Double, _ y: Double) -> PixelStoryStep {
    let step = PixelStoryStep()
    step.kind = .teleport
    step.x = x
    step.y = y
    return step
}

func pixelStoryCall(_ fn: @escaping () -> Void) -> PixelStoryStep {
    let step = PixelStoryStep()
    step.kind = .call
    step.call = fn
    return step
}

/// Everything the stage needs to draw Pibo this frame.
final class PixelActorFrame {
    var x: Double = 0
    var y: Double = 0
    /// Pixels above `y` when perched on something.
    var lift = 0
    /// The y used for depth against decorations.
    var depthY: Double = 0
    var visible = true
    /// Inside the tent: only marks at the door.
    var inside = false
    /// The place whose art is redrawn over Pibo while it hides there (-1 none).
    var coverPlace = -1
    var activity: PiboDayActivity = .idle
    var place: PiboCoreDayPlace = .ground
    var gait: PiboDayGait = .still
    var facing: Double = 0
    var carrying = -1
    var noticing = false
    var waving = false
    var refusing = false
    var lying = false
    /// Swing sway in pixels, shared with the swing's art.
    var sway = 0
    var hiding = false
    /// The acted pose of a season beat (none outside one).
    var story: PiboStoryPose = .none
    /// How long the current activity has run and has left (0 outside one).
    var elapsedMs: Double = 0
    var remainingMs: Double = 0
    /// A feeling playing now (`PiboEmote`, 0 none) and how long it has played; likewise a fidget.
    var emote = 0
    var emoteAge: Double = 0
    var fidget = 0
    var fidgetAge: Double = 0
    /// Decision 061: the shape it has taken (`PiboForm`, 0 none), the phase of the change
    /// (`PixelShapePhase`) and how long that phase has run.
    var form = 0
    var formPhase = 0
    var formAge: Double = 0

    init() {}
}

private enum BeatKind: Int {
    case walk = 0
    case `do` = 1
    case wait = 2
    case offstage = 3
    case teleport = 4
    case call = 5
}

private struct WaitFlags {
    var noticing = false
    var waving = false
    var refusing = false
    var facing: Double = 0

    static let none = WaitFlags()
}

private final class Beat {
    var kind: BeatKind = .wait
    var x = 0
    var y = 0
    var gait: PiboDayGait = .walk
    var durationMs: Double = 0
    var activity: PiboDayActivity = .idle
    var place: PiboCoreDayPlace = .ground
    var roam = false
    var noticing = false
    var waving = false
    var refusing = false
    var facing: Double = 0
    /// Set or clear what Pibo carries when the beat starts (-2 leaves it).
    var carry = -2
    var hide = false
    var call: (() -> Void)?
    var startedAt: Double = -1
    /// Part of a season beat: nothing else interrupts it.
    var scripted = false
    var story: PiboStoryPose = .none
    /// Inside the pod: out of sight until the beat ends.
    var inside = false

    init() {}
}

private let SPEED_PX_PER_S: [Double] = [0, 7, 13, 30]
private let MAX_STEP_MS: Double = 250
private let OFFSTAGE_EXPLORE_MS: Double = 20000
private let NOTICE_MS: Double = 800
// Long enough for the second tap of a double tap to land on the same spot.
private let TOUCH_HOLD_MS: Double = 900

private let ROAMING: [PiboDayActivity] = [
    .stroll, .slowWalk, .run, .chaseBeetle, .chaseButterfly, .umbrella, .puddleJump,
    .circleWindmill, .hopStones, .balanceLog,
    // Life echoes (decision 060) that happen on the move.
    .jog, .hike, .countSteps, .yawning, .nightWatch,
]
/// Forms that get about while held: a bike rides, a sneaker hops, a spring bounces along.
private let ROAMING_FORMS: [Int] = [PiboForm.bike.rawValue, PiboForm.sneaker.rawValue, PiboForm.spring.rawValue]
/// Roaming echoes that stop for their last few seconds (a jog ends hands on hips).
private let WIND_DOWN: [PiboDayActivity] = [.jog]
private let WIND_DOWN_MS: Double = 3500
/// Points in the lap round the meal mat.
private let SNIFF_LAP = 8

func pixelDayRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }
func pixelDayRoundInt(_ x: Double) -> Int { Int(pixelDayRound(x)) }

final class PixelDayDirector {
    private var layout = PixelForestLayout()
    private var scene: PiboCoreDayScene = .clearing
    private weak var brain: PixelDayBrain?
    var events = PixelDayEvents()
    private var beats: [Beat] = []
    private let rng = PixelRandom(58)
    private var x: Double = 0
    private var y: Double = 0
    private var facing: Double = 0
    private var carrying = -1
    private var hidingAt = -1
    private var offstage = false
    private var lastMs: Double = -1
    private var previous: PiboDayActivity = .idle
    private var current: PiboDayActivity = .idle
    private var currentPlace: PiboCoreDayPlace = .ground
    private var spot: PixelSpot?
    private var roamIndex = 0
    /// Where the last queued walk ends, so the next one knows where it starts from.
    private var plannedY: Double = 0
    private var configured = false
    private var holdUntil: Double = 0
    private var hideFind = -1
    /// Season two's bridge is whole: crossings take it instead of the stepping stones.
    private var bridge = false
    private var emoteKind = 0
    private var emoteAt: Double = 0
    private var fidgetKind = 0
    private var fidgetAt: Double = 0
    // Decision 061: the shape it is in, and the beat a change lasts for.
    private let shape = PixelShape()
    private var shapeBeat: Beat?
    /// Decision 065: a hide in disguise — the form, and where the look-alikes stand.
    private var disguiseForm = 0
    private var decoySpots: [[Int]] = []
    private var roamTargetCache: [Int] = []
    private var roamCacheIndex = -1

    func setBrain(_ brain: PixelDayBrain) {
        self.brain = brain
    }

    /// Called when the stage knows its size or the scene changes; keeps Pibo in view.
    func configure(_ layout: PixelForestLayout, _ scene: PiboCoreDayScene) {
        let sameScene = configured && scene == self.scene
        if sameScene && (layout.width != self.layout.width || layout.groundY != self.layout.groundY) {
            // The stage was laid out again at another size: carry Pibo over into the new
            // coordinates and re-plan, since every queued target was measured on the old stage.
            x = pixelDayRound(x * Double(layout.width) / Double(max(1, self.layout.width)))
            y = pixelDayRound(Double(layout.groundY) + (y - Double(self.layout.groundY)) *
                         Double(layout.height) / Double(max(1, self.layout.height)))
            // SwiftUI can first report a short provisional stage. Fixed-size
            // places may lie beyond that temporary viewport; scaling that
            // offset must not strand Pibo below the final forest for seconds.
            let bounds = pixelWalkBounds(layout, scene)
            y = min(Double(bounds.maxY), max(Double(bounds.minY), y))
            dropBeats()
        }
        self.layout = layout
        self.scene = scene
        if !configured || !sameScene {
            x = pixelDayRound(Double(layout.width) / 2)
            y = Double(layout.groundY)
            dropBeats()
            hidingAt = -1
            shape.clear()
            shapeBeat = nil
            clearDisguise()
        }
        configured = true
    }

    var isConfigured: Bool { configured }

    func setBridge(_ whole: Bool) {
        bridge = whole
    }

    /// Plays a feeling (decision 060) over whatever Pibo is doing.
    func feel(_ emote: Int, _ now: Double) {
        if emote <= 0 { return }
        emoteKind = emote
        emoteAt = now
        fidgetKind = 0
    }

    /// Plays a small idle motion, unless a feeling is showing.
    func fidget(_ fidget: Int, _ now: Double) {
        if fidget <= 0 || feeling(now) { return }
        fidgetKind = fidget
        fidgetAt = now
    }

    // --- Shape (decision 061) ------------------------------------------------------------

    /// Changes (or tries to) when the next beat of `activity` begins, for as long as it lasts.
    func shapeFor(_ activity: PiboDayActivity, form: Int, tryOnly: Bool, tryMs: Double, stuck: Bool,
                  releaseMs: Double) {
        if form <= 0 { return }
        shape.armFor(activity.rawValue, form: form, tryOnly: tryOnly, holdMs: tryMs, stuck: stuck,
                     releaseMs: releaseMs)
    }

    /// Slips into `form` at `startAt` for `holdMs`, wherever it is (a sneeze).
    func shapeAt(_ form: Int, _ startAt: Double, _ holdMs: Double) {
        if form <= 0 { return }
        shape.changeAt(form: form, startAt: startAt, holdMs: holdMs)
    }

    /// A double tap while it is stuck: helps it back. Returns true when it was stuck.
    func helpBack(_ now: Double) -> Bool {
        shape.help(now)
    }

    /// The form it is in now (`PiboForm`, 0 none), including the puffs in and out.
    var form: Int { shape.showing ? shape.form : 0 }

    var stuck: Bool { shape.phase == .stuck }

    private func stepShape(_ now: Double) {
        // The beat a change was linked to has ended, finished or been dropped.
        if let linked = shapeBeat, beats.isEmpty || beats[0] !== linked {
            shapeBeat = nil
            shape.beatEnded(now)
            if shape.phase == .stuck { events.onShapeStuck?(shape.form) }
        }
        shape.step(now)
        let ended = shape.takeEnding()
        if ended != .onTime {
            events.onShapeBack?(shape.endedForm, ended == .helped)
        }
    }

    func feeling(_ now: Double) -> Bool {
        emoteKind > 0 && now - emoteAt < piboEmoteDuration(PiboEmote(rawValue: emoteKind) ?? .none)
    }

    /// Moving about on its own (walking or roaming), for the stumble fidget.
    var walking: Bool {
        guard let beat = beats.first else { return false }
        return beat.kind == .walk || (beat.kind == .do && beat.roam)
    }

    /// The activity Pibo finished last.
    var lastFinished: PiboDayActivity { previous }

    var hiding: Bool { hidingAt >= 0 }

    var hidingPlace: Int { hidingAt }

    /// The form Pibo hides as (0 when it hides behind a place) and its look-alikes.
    var disguise: Int { hiding ? disguiseForm : 0 }

    var decoys: [[Int]] { hiding ? decoySpots : [] }

    var busyScripted: Bool {
        beats.contains { $0.kind == .offstage || $0.hide || $0.call != nil || $0.scripted }
    }

    /// A season beat is playing.
    var performing: Bool { beats.contains { $0.scripted } }

    var activity: PiboDayActivity { current }

    /// The place Pibo is busy at right now (-1 while walking or in a scripted moment).
    var doingAt: Int {
        guard let beat = beats.first, beat.kind == .do, beat.startedAt >= 0 else { return -1 }
        return Int(beat.place.rawValue)
    }

    var position: (x: Double, y: Double) { (x, y) }

    /// Drops whatever Pibo planned, e.g. when its state changes (it fell asleep).
    func replan() {
        if busyScripted { return }
        dropBeats()
    }

    // --- Commands -----------------------------------------------------------------------

    /// An accepted invitation: go there now and do it.
    func go(_ plan: PixelDayPlan) {
        if hiding || offstage || performing { return }
        dropBeats()
        push(wait(400, WaitFlags(noticing: true)))
        planBeats(plan, invited: true)
    }

    /// A declined invitation: shake its head toward the place.
    func refuse(_ place: PiboCoreDayPlace) {
        let spot = pixelPlaceSpot(layout, scene, place)
        let facing: Double = spot == nil ? 0 : (Double(spot!.x) < x ? -1 : 1)
        beats.insert(wait(1400, WaitFlags(refusing: true, facing: facing)), at: 0)
    }

    /// A finger on Pibo: it stops where it is, so a moving Pibo can still take a double tap.
    func touched(_ now: Double) {
        holdUntil = max(holdUntil, now + TOUCH_HOLD_MS)
    }

    /// A double tap: stop and enjoy it for a moment.
    func patted(_ now: Double) {
        holdUntil = max(holdUntil, now + 1200)
    }

    /// The greeting when Home opens. `find` is a find brought back while you were away.
    func greet(_ style: PiboCoreDayGreet, find: Int, hideSpot: PiboCoreDayPlace, hideMs: Double,
               disguise: Int = 0, decoys: Int = 0, seed: Int = 0) {
        dropBeats()
        let front = frontSpot()
        let fromEdge = find >= 0
        if fromEdge { enterFromEdge(find) }
        switch style {
        case .hide:
            dropBeats()
            if disguise > 0 { hideAs(disguise, decoys, seed, find, hideMs) }
            if !hiding && beats.isEmpty { hideAt(hideSpot, find, hideMs) }
        case .sleepyStir:
            push(wait(1600, WaitFlags(refusing: true)))
        case .runOver, .showFind:
            if !fromEdge { push(wait(NOTICE_MS, WaitFlags(noticing: true))) }
            push(walkTo(Double(front[0]), Double(front[1]), .run))
            if fromEdge && style == .showFind {
                push(wait(2600, WaitFlags(waving: false, facing: 0)))
                push(call { [weak self] in self?.presentFind(find) })
                putAway()
            } else {
                push(wait(1600, WaitFlags(waving: true)))
                if fromEdge { putAway() }
            }
        case .peek:
            if fromEdge { putAway() }
            push(wait(NOTICE_MS, WaitFlags(noticing: true)))
            push(wait(1500, WaitFlags(waving: true)))
            if fromEdge { push(call { [weak self] in self?.presentFind(find) }) }
        case .none:
            if fromEdge {
                putAway()
                push(call { [weak self] in self?.presentFind(find) })
            }
        }
    }

    /// Hide-and-seek: crouch behind the place until found or Core's hide time runs out.
    /// A find brought back meanwhile stays in Pibo's hands until it pops out.
    func hideAt(_ place: PiboCoreDayPlace, _ find: Int, _ hideMs: Double) {
        guard let spot = pixelHideSpot(layout, scene, place) else { return }
        hideFind = find
        let hide = Beat()
        hide.kind = .teleport
        hide.x = spot.x
        hide.y = spot.y
        hide.carry = find
        push(hide)
        let wait = self.wait(hideMs, WaitFlags(facing: 0))
        wait.hide = true
        wait.place = place
        wait.activity = .hide
        push(wait)
        push(call { [weak self] in
            guard let self else { return }
            self.hidingAt = -1
            self.hideFind = -1
            self.events.onHideTimedOut?()
        })
        popOut(find)
    }

    /// Decision 065: hide as a forest thing among look-alikes, holding still in that shape
    /// until found or the hide time runs out; then it puffs back on its own.
    func hideAs(_ form: Int, _ decoys: Int, _ seed: Int, _ find: Int, _ hideMs: Double) {
        let spots = pixelDisguiseSpots(layout, scene, decoys, seed, form == PiboForm.fish.rawValue)
        if spots.isEmpty { return }
        hideFind = find
        disguiseForm = form
        decoySpots = Array(spots.dropFirst())
        let hide = Beat()
        hide.kind = .teleport
        hide.x = spots[0][0]
        hide.y = spots[0][1]
        hide.carry = -1
        push(hide)
        push(call { [weak self] in
            guard let self else { return }
            self.shape.changeAt(form: form, startAt: self.lastMs, holdMs: hideMs)
        })
        let wait = self.wait(hideMs, WaitFlags(facing: 0))
        wait.hide = true
        // 101 is `PixelHotspot.disguise`: no Core place draws over a disguised Pibo.
        wait.place = PiboCoreDayPlace(rawValue: Int32(PixelHotspot.disguise.rawValue)) ?? .ground
        wait.activity = .hide
        push(wait)
        push(call { [weak self] in
            guard let self else { return }
            self.hidingAt = -1
            self.hideFind = -1
            self.clearDisguise()
            self.events.onHideTimedOut?()
        })
        popOut(find)
    }

    private func clearDisguise() {
        disguiseForm = 0
        decoySpots = []
    }

    /// Found you: pop out and wave.
    func found() {
        if !hiding { return }
        hidingAt = -1
        if disguiseForm > 0 { shape.release(lastMs) }
        clearDisguise()
        dropBeats()
        carrying = hideFind
        push(wait(500, WaitFlags(noticing: true)))
        popOut(hideFind)
        hideFind = -1
    }

    private func popOut(_ find: Int) {
        let front = frontSpot()
        push(wait(1400, WaitFlags(waving: find < 0)))
        push(walkTo(Double(front[0]), Double(front[1]), .run))
        if find >= 0 {
            push(wait(2000, WaitFlags(facing: 0)))
            push(call { [weak self] in self?.presentFind(find) })
            putAway()
        }
    }

    /// Opening Home: Pibo is already somewhere, in the middle of something.
    func settle() {
        guard let brain, !busyScripted else { return }
        dropBeats()
        guard let plan = brain.next(previous: previous) else { return }
        let spot = plan.place == .ground ? groundSpot() : pixelPlaceSpot(layout, scene, plan.place)
        guard let spot else { return }
        x = Double(spot.x)
        y = Double(spot.y)
        offstage = false
        planBeats(plan, invited: false)
    }

    /// A trip earned by your steps: walk off the edge, come back with the find.
    func explore(_ item: Int) {
        if hiding || performing { return }
        dropBeats()
        let edge = edgePoint()
        push(walkTo(Double(edge[0] + 30), Double(edge[1]), .walk, .explore))
        push(walkTo(Double(edge[0]), Double(edge[1]), .walk, .explore))
        let away = Beat()
        away.kind = .offstage
        away.durationMs = OFFSTAGE_EXPLORE_MS
        push(away)
        enterFromEdge(item)
        let front = frontSpot()
        push(walkTo(Double(front[0]), Double(front[1]), .walk))
        push(wait(2400, WaitFlags(facing: 0)))
        push(call { [weak self] in self?.events.onArrivedBack?(item) })
        putAway()
    }

    /// Walk off to another scene; `onSceneSwitch` fires while Pibo is off-screen.
    func travel() {
        dropBeats()
        hidingAt = -1
        let edge = edgePoint()
        push(walkTo(Double(edge[0]), Double(edge[1]), .walk, .explore))
        push(call { [weak self] in self?.events.onSceneSwitch?() })
    }

    /// After the scene switched: walk in from the edge.
    func arrive() {
        dropBeats()
        let edge = edgePoint()
        let enter = Beat()
        enter.kind = .teleport
        enter.x = edge[0]
        enter.y = edge[1]
        push(enter)
        push(walkTo(pixelDayRound(Double(layout.width) * 0.4), Double(edge[1] - 6), .walk))
    }

    /// Plays a season beat now. Returns false (and plays nothing) while Pibo is hiding,
    /// off exploring or already in another scripted moment, unless `interrupt` is set by a
    /// moment that hands over to the beat (the lost screw carried back from a trip).
    @discardableResult
    func perform(_ steps: [PixelStoryStep], interrupt: Bool = false) -> Bool {
        if !configured || steps.isEmpty { return false }
        if !interrupt && (hiding || offstage || busyScripted) { return false }
        dropBeats()
        spot = nil
        for step in steps {
            let beat: Beat
            switch step.kind {
            case .walk:
                beat = walkTo(step.x, step.y, step.gait)
            case .teleport:
                beat = Beat()
                beat.kind = .teleport
                beat.x = pixelDayRoundInt(step.x)
                beat.y = pixelDayRoundInt(step.y)
            case .call:
                beat = call(step.call ?? {})
            default:
                beat = wait(step.durationMs, WaitFlags(facing: step.facing))
                beat.story = step.pose
                beat.inside = step.kind == .inside
            }
            beat.carry = step.carry
            beat.scripted = true
            push(beat)
        }
        return true
    }

    // --- Frame ---------------------------------------------------------------------------

    func step(_ now: Double, hold: Bool) -> PixelActorFrame {
        let dt = lastMs < 0 ? 0 : max(0, min(MAX_STEP_MS, now - lastMs))
        lastMs = now
        let frame = PixelActorFrame()
        if !configured { return frame }
        if beats.isEmpty { refill() }
        var beat = beats.first
        // Instant beats resolve in the same frame.
        var guardCount = 0
        while let instant = beat, (instant.kind == .teleport || instant.kind == .call), guardCount < 8 {
            beats.removeFirst()
            if instant.kind == .teleport {
                x = Double(instant.x)
                y = Double(instant.y)
                offstage = false
            } else if let fn = instant.call {
                fn()
            }
            if instant.carry != -2 { carrying = instant.carry }
            if beats.isEmpty { refill() }
            beat = beats.first
            guardCount += 1
        }
        stepShape(now)
        let paused = hold || now < holdUntil || shape.holdsStill
        frame.gait = .still
        frame.activity = current
        frame.place = currentPlace
        if let beat {
            if beat.startedAt < 0 {
                beat.startedAt = now
                if beat.carry != -2 { carrying = beat.carry }
                if beat.hide { hidingAt = Int(beat.place.rawValue) }
                if beat.kind == .do {
                    current = beat.activity
                    currentPlace = beat.place
                    if !shape.showing && shape.beatStarted(beat.activity.rawValue, now: now) {
                        shapeBeat = beat
                    }
                }
            }
            frame.activity = beat.kind == .walk ? beat.activity
                : (beat.kind == .do ? beat.activity : (beat.hide ? .hide : current))
            switch beat.kind {
            case .walk:
                if !paused {
                    frame.gait = moveToward(Double(beat.x), Double(beat.y), beat.gait, dt) ? .still : beat.gait
                }
                if frame.gait == .still && !paused { beats.removeFirst() }
                // Stopped on the way (a pat holds it): it stands. The activity it is walking to
                // (sleep, a seat, a nap) only takes over its pose once it gets there.
                if frame.gait == .still { frame.activity = .idle }
            case .do:
                if paused { beat.startedAt += dt }
                let remaining = beat.durationMs - (now - beat.startedAt)
                let windingDown = WIND_DOWN.contains(beat.activity) && remaining < WIND_DOWN_MS
                let formRoams = ROAMING_FORMS.contains(shape.form) && shape.phase == .hold
                if (beat.roam || formRoams) && !paused && !windingDown {
                    frame.gait = roam(beat, dt)
                }
                frame.elapsedMs = now - beat.startedAt
                frame.remainingMs = max(0, remaining)
                if now - beat.startedAt >= beat.durationMs { finishDo(beat) }
            case .wait:
                frame.story = beat.story
                if beat.inside { frame.visible = false }
                frame.noticing = beat.noticing
                frame.waving = beat.waving
                frame.refusing = beat.refusing
                if beat.facing != 0 || beat.noticing || beat.waving { facing = beat.facing }
                if now - beat.startedAt >= beat.durationMs { beats.removeFirst() }
            case .offstage:
                offstage = true
                if now - beat.startedAt >= beat.durationMs {
                    beats.removeFirst()
                }
            default:
                break
            }
        }
        frame.x = x
        frame.y = y
        frame.depthY = y
        frame.facing = facing
        frame.carrying = carrying
        frame.visible = frame.visible && !offstage
        frame.hiding = hidingAt >= 0
        frame.coverPlace = hidingAt
        let atSpot = spot != nil && frame.gait == .still &&
            abs(x - Double(spot!.x)) <= 1 && abs(y - Double(spot!.y)) <= 1
        if atSpot, let spot, let beat, beat.kind == .do {
            frame.lift = spot.lift
            frame.depthY = Double(spot.depth)
            frame.inside = spot.kind == .inside
            // Only sleep lies down; everything else Pibo does awake, it does sitting or standing.
            frame.lying = beat.activity == .sleep
            if spot.facing != 0 { frame.facing = Double(spot.facing) }
            if beat.activity == .swing {
                frame.sway = pixelDayRoundInt(sin(now / 700) * 4)
                frame.x += Double(frame.sway)
            }
        }
        if frame.hiding { frame.activity = .hide }
        if shape.phase != .none {
            frame.form = shape.form
            frame.formPhase = shape.phase.rawValue
            frame.formAge = now - shape.at
        }
        if feeling(now) {
            frame.emote = emoteKind
            frame.emoteAge = now - emoteAt
        } else {
            emoteKind = 0
            if fidgetKind > 0 && now - fidgetAt < piboFidgetDuration(PiboFidget(rawValue: fidgetKind) ?? .none) {
                frame.fidget = fidgetKind
                frame.fidgetAge = now - fidgetAt
            } else {
                fidgetKind = 0
            }
        }
        return frame
    }

    // --- Internals -----------------------------------------------------------------------

    private func refill() {
        guard let brain else { return }
        guard let plan = brain.next(previous: previous) else {
            push(wait(4000, .none))
            return
        }
        planBeats(plan, invited: false)
    }

    private func planBeats(_ plan: PixelDayPlan, invited: Bool) {
        let spot = plan.place == .ground ? groundSpot() : pixelPlaceSpot(layout, scene, plan.place)
        guard let spot else {
            push(wait(3000, .none))
            return
        }
        self.spot = spot
        let slow = brain?.slow() ?? false
        let gait: PiboDayGait = plan.eager ? .run : (slow ? .slow : .walk)
        let roaming = ROAMING.contains(plan.activity)
        let rollStart = plan.activity == .rollDownHill
        push(walkTo(Double(spot.x), Double(spot.y), gait, invited ? .idle : plan.activity))
        let doing = Beat()
        doing.kind = .do
        doing.activity = plan.activity
        doing.place = plan.place
        doing.durationMs = plan.durationMs
        doing.roam = roaming || rollStart || plan.activity == .sniffMeal
        doing.carry = plan.carry >= 0 ? plan.carry : -2
        roamIndex = 0
        push(doing)
        if plan.carry < 0 { return }
        // A find played with goes back where it came from: its display spot, or the basket.
        if plan.place == .findSpot {
            let down = wait(600, WaitFlags(facing: 1))
            push(down)
            let empty = call {}
            empty.carry = -1
            push(empty)
        } else {
            putAway()
        }
    }

    private func finishDo(_ beat: Beat) {
        beats.removeFirst()
        previous = beat.activity
        spot = nil
        events.onActivityDone?(beat.activity)
    }

    private func push(_ beat: Beat) {
        if beats.isEmpty { plannedY = y }
        if beat.kind == .walk && scene == .creek {
            // Across the creek only over the stepping stones.
            for point in pixelCreekCrossing(layout, pixelDayRoundInt(plannedY), beat.y, bridge) {
                let hop = walkTo(Double(point[0]), Double(point[1]),
                                 beat.gait == .run ? .walk : beat.gait, beat.activity)
                hop.scripted = beat.scripted
                beats.append(hop)
            }
        }
        beats.append(beat)
        if beat.kind == .walk || beat.kind == .teleport { plannedY = Double(beat.y) }
    }

    private func wait(_ durationMs: Double, _ flags: WaitFlags) -> Beat {
        let beat = Beat()
        beat.kind = .wait
        beat.durationMs = durationMs
        beat.noticing = flags.noticing
        beat.waving = flags.waving
        beat.refusing = flags.refusing
        beat.facing = flags.facing
        return beat
    }

    private func walkTo(_ x: Double, _ y: Double, _ gait: PiboDayGait,
                        _ activity: PiboDayActivity = .idle) -> Beat {
        let beat = Beat()
        beat.kind = .walk
        beat.x = pixelDayRoundInt(x)
        beat.y = pixelDayRoundInt(y)
        beat.gait = gait
        beat.activity = activity
        return beat
    }

    /// Forgets the plan. Whatever Pibo carried is already on the shelf (the store records a
    /// find when the trip is due), so an interrupted put-away never leaves it in its hands.
    private func dropBeats() {
        beats = []
        carrying = -1
    }

    private func call(_ fn: @escaping () -> Void) -> Beat {
        let beat = Beat()
        beat.kind = .call
        beat.call = fn
        return beat
    }

    private func enterFromEdge(_ item: Int) {
        let edge = edgePoint()
        let enter = Beat()
        enter.kind = .teleport
        enter.x = edge[0]
        enter.y = edge[1]
        enter.carry = item
        push(enter)
    }

    private func putAway() {
        let basket = pixelBasketBox(layout)
        push(walkTo(Double(basket.x + basket.w + 10), Double(basket.y + basket.h), .walk))
        let drop = wait(700, WaitFlags(facing: -1))
        drop.carry = -2
        push(drop)
        let empty = call {}
        empty.carry = -1
        push(empty)
    }

    private func presentFind(_ item: Int) {
        events.onFindPresented?(item)
    }

    private func frontSpot() -> [Int] {
        // Close to the viewer, but never past where the scene can be walked (the creek's water).
        let bounds = pixelWalkBounds(layout, scene)
        return [pixelDayRoundInt(Double(layout.width) / 2), min(layout.groundY + 22, bounds.maxY)]
    }

    private func edgePoint() -> [Int] {
        [-26, pixelEdgeY(layout, scene)]
    }

    private func groundSpot() -> PixelSpot {
        let bounds = pixelWalkBounds(layout, scene)
        var spot = PixelSpot()
        spot.x = rng.int(bounds.minX, bounds.maxX)
        spot.y = rng.int(bounds.minY, bounds.maxY)
        spot.depth = spot.y
        return spot
    }

    /// Returns true once arrived.
    private func moveToward(_ tx: Double, _ ty: Double, _ gait: PiboDayGait, _ dt: Double) -> Bool {
        let dx = tx - x
        let dy = ty - y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance < 0.75 {
            x = tx
            y = ty
            return true
        }
        if abs(dx) > 0.5 { facing = dx < 0 ? -1 : 1 }
        let speed = gait.rawValue < SPEED_PX_PER_S.count ? SPEED_PX_PER_S[gait.rawValue] : 13
        let travel = speed * dt / 1000
        if travel >= distance {
            x = tx
            y = ty
            return true
        }
        x += dx / distance * travel
        y += dy / distance * travel
        return false
    }

    /// Roaming activities wander between waypoints shaped by the activity.
    private func roam(_ beat: Beat, _ dt: Double) -> PiboDayGait {
        // Round the mat once, then stay and sniff.
        if beat.activity == .sniffMeal && roamIndex > SNIFF_LAP { return .still }
        let riding = shape.form == PiboForm.bike.rawValue && shape.phase == .hold
        let gait: PiboDayGait = riding ? .run : roamGait(beat.activity)
        let target = roamTarget(beat)
        if moveToward(Double(target[0]), Double(target[1]), gait, dt) { roamIndex += 1 }
        x = (x * 10).rounded() / 10
        return gait
    }

    private func roamGait(_ activity: PiboDayActivity) -> PiboDayGait {
        switch activity {
        case .run, .chaseBeetle, .chaseButterfly, .circleWindmill, .rollDownHill:
            return .run
        case .jog:
            return .run
        case .slowWalk, .balanceLog, .countSteps, .yawning, .nightWatch:
            return .slow
        default:
            return (brain?.slow() ?? false) ? .slow : .walk
        }
    }

    private func roamTarget(_ beat: Beat) -> [Int] {
        let spot = self.spot
        let index = roamIndex
        switch beat.activity {
        case .circleWindmill:
            if let spot {
                let angle = Double(index) * Double.pi / 4
                return [pixelDayRoundInt(Double(spot.x) - 16 + cos(angle) * 18),
                        pixelDayRoundInt(Double(spot.y) - 4 + sin(angle) * 7)]
            }
        case .hopStones:
            let stones = pixelSteppingStones(layout)
            if !stones.isEmpty {
                let i = index % (stones.count * 2)
                let stone = stones[i < stones.count ? i : stones.count * 2 - 1 - i]
                return [stone[0], stone[1] - 1]
            }
        case .puddleJump:
            let puddles = pixelPuddles(layout, scene)
            if !puddles.isEmpty {
                let puddle = puddles[index % puddles.count]
                return [puddle[0], puddle[1]]
            }
        case .balanceLog:
            if let spot {
                return [spot.x + (index % 2 == 0 ? 10 : -10), spot.y]
            }
        case .rollDownHill:
            if let spot {
                return index % 2 == 0
                    ? [pixelDayRoundInt(Double(layout.width) * 0.42), layout.groundY + 18]
                    : [spot.x, spot.y]
            }
        case .jog:
            // Laps: an oval round the middle of the ground, eight points a lap.
            let bounds = pixelWalkBounds(layout, scene)
            let mx = Double(bounds.minX + bounds.maxX) / 2
            let my = Double(bounds.minY + bounds.maxY) / 2
            let angle = Double(index) * Double.pi / 4
            return [pixelDayRoundInt(mx + cos(angle) * Double(bounds.maxX - bounds.minX) * 0.32),
                    pixelDayRoundInt(my + sin(angle) * Double(bounds.maxY - bounds.minY) * 0.3)]
        case .sniffMeal:
            // One slow lap round the mat (the spot is at its left end), back to the spot.
            if let spot {
                if index >= SNIFF_LAP { return [spot.x, spot.y] }
                let angle = Double.pi + Double(index) * Double.pi * 2 / Double(SNIFF_LAP)
                return [pixelDayRoundInt(Double(spot.x) + 17 + cos(angle) * 17),
                        pixelDayRoundInt(Double(spot.y) - 6 + sin(angle) * 8)]
            }
            return [pixelDayRoundInt(x), pixelDayRoundInt(y)]
        case .countSteps:
            // Back and forth in a straight line, counting.
            if let spot {
                return [spot.x + (index % 2 == 0 ? 22 : -22), spot.y]
            }
        default:
            break
        }
        if roamTargetCache.isEmpty || roamCacheIndex != index {
            let bounds = pixelWalkBounds(layout, scene)
            // Chasing stays near where it started; strolls use the whole clearing.
            let near = beat.activity == .chaseBeetle || beat.activity == .chaseButterfly
            let cx = near && spot != nil ? Double(spot!.x) : Double(bounds.minX + bounds.maxX) / 2
            let half = near ? 22.0 : Double(bounds.maxX - bounds.minX) / 2
            roamTargetCache = [
                pixelDayRoundInt(max(Double(bounds.minX), min(Double(bounds.maxX), cx + rng.range(-half, half)))),
                rng.int(bounds.minY, bounds.maxY),
            ]
            roamCacheIndex = index
        }
        return roamTargetCache
    }
}

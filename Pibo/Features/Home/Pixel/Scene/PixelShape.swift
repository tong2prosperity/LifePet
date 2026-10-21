import Foundation

// Pibo's shape on the stage (decision 061). Core decides the form, whether it only
// tries, how long it holds and whether it gets stuck; this tracks where the change is
// right now — puffing into the form, holding it, stuck in it, puffing back — so the
// director can hold Pibo still and the stage can draw the right thing.
//
// Ported from HarmonyPibo `pixel/day/PixelShape.ets`.

enum PixelShapePhase: Int {
    case none = 0
    /// The puff into the form; the form shows from halfway.
    case `in` = 1
    case hold = 2
    /// The echo ended and it cannot change back: it wriggles until helped or it pops.
    case stuck = 3
    /// The puff back; Pibo shows from halfway.
    case out = 4
    /// It puffs up to change, nothing happens.
    case attempt = 5
}

/// One puff of the change, in or out.
let PIXEL_SHAPE_POOF_MS: Double = 450

/// How a stuck form came back.
enum PixelShapeReturn: Int {
    /// It ended on time.
    case onTime = 0
    /// You double-tapped it.
    case helped = 1
    /// Nobody helped; it popped back by itself.
    case byItself = 2
}

final class PixelShape {
    var form: Int = 0
    var phase: PixelShapePhase = .none
    /// When the current phase began.
    var at: Double = 0
    /// The hold ends at this time; 0 when it lasts as long as the activity it is linked to.
    var holdUntil: Double = 0
    var stuck: Bool = false
    var releaseMs: Double = 0
    private var tryMs: Double = 0
    /// Set when a stuck form ends, read once by the director.
    var ended: PixelShapeReturn = .onTime
    var endedForm: Int = 0
    /// A change waiting for its activity's beat to begin.
    var pendingActivity: Int = -1
    private var pendingForm: Int = 0
    private var pendingTry: Bool = false
    private var pendingStuck: Bool = false
    private var pendingReleaseMs: Double = 0
    private var pendingTryMs: Double = 0
    /// A change waiting for a moment (after a sneeze).
    private var startAt: Double = 0
    private var startHoldMs: Double = 0

    /// Arms a change for when the activity's beat starts.
    func armFor(_ activity: Int, form: Int, tryOnly: Bool, holdMs: Double, stuck: Bool,
                releaseMs: Double) {
        pendingActivity = activity
        pendingForm = form
        pendingTry = tryOnly
        pendingTryMs = holdMs
        pendingStuck = stuck
        pendingReleaseMs = releaseMs
    }

    /// A change at `startAt` that holds for `holdMs` on its own (a sneeze).
    func changeAt(form: Int, startAt: Double, holdMs: Double) {
        if showing { return }
        self.form = form
        self.startAt = startAt
        startHoldMs = holdMs
    }

    /// The activity's beat began: start what was armed for it.
    func beatStarted(_ activity: Int, now: Double) -> Bool {
        if pendingActivity != activity { return false }
        pendingActivity = -1
        form = pendingForm
        stuck = pendingStuck
        releaseMs = pendingReleaseMs
        holdUntil = 0
        if pendingTry {
            tryMs = pendingTryMs
            enter(.attempt, now)
        } else {
            enter(.in, now)
        }
        return true
    }

    /// The linked activity ended (or was dropped): change back, or get stuck.
    func beatEnded(_ now: Double) {
        if phase != .in && phase != .hold { return }
        if holdUntil > 0 { return }
        if stuck {
            enter(.stuck, now)
        } else {
            enter(.out, now)
        }
    }

    /// Found while hiding in this shape (decision 065): puff back now.
    func release(_ now: Double) {
        if phase != .in && phase != .hold { return }
        holdUntil = 0
        enter(.out, now)
    }

    /// A double tap while stuck. Returns true when it helped.
    func help(_ now: Double) -> Bool {
        if phase != .stuck { return false }
        finishStuck(.helped, now)
        return true
    }

    /// Advances the phases; call once a frame.
    func step(_ now: Double) {
        if startAt > 0 && now >= startAt && phase == .none {
            startAt = 0
            stuck = false
            holdUntil = now + PIXEL_SHAPE_POOF_MS + startHoldMs
            enter(.in, now)
        }
        let age = now - at
        switch phase {
        case .in:
            if age >= PIXEL_SHAPE_POOF_MS { enter(.hold, now) }
        case .hold:
            if holdUntil > 0 && now >= holdUntil { enter(.out, now) }
        case .stuck:
            if age >= releaseMs { finishStuck(.byItself, now) }
        case .out:
            if age >= PIXEL_SHAPE_POOF_MS { reset() }
        case .attempt:
            if age >= tryMs { reset() }
        default:
            break
        }
    }

    /// The form is on screen (or puffing in or out of it).
    var showing: Bool {
        phase == .in || phase == .hold || phase == .stuck || phase == .out
    }

    /// Pibo stays where it is: stuck, trying, or a sneeze shape.
    var holdsStill: Bool {
        phase == .stuck || phase == .attempt || (showing && holdUntil > 0)
    }

    /// Takes the ending of a stuck form, once.
    func takeEnding() -> PixelShapeReturn {
        let ending = ended
        ended = .onTime
        return ending
    }

    func clear() {
        pendingActivity = -1
        startAt = 0
        reset()
    }

    private func finishStuck(_ how: PixelShapeReturn, _ now: Double) {
        ended = how
        endedForm = form
        stuck = false
        enter(.out, now)
    }

    private func enter(_ phase: PixelShapePhase, _ now: Double) {
        self.phase = phase
        at = now
    }

    private func reset() {
        phase = .none
        form = 0
        stuck = false
        holdUntil = 0
    }
}

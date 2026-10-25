import Foundation

// Presentation only: which motion to play comes from Core's animation state ID; this file
// decides how that motion looks frame by frame. No health thresholds or timing rules here.
//
// Ported from HarmonyPibo `pixel/character/PiboPixelMotion.ets`.

enum PiboPixelActivity: Int {
    case dataUnknown = 0
    case sleeping = 1
    case waking = 2
    case stable = 3
    case energetic = 4
    case tired = 5
    case celebrate = 6
}

enum PiboPixelTrick: Int {
    case none = 0
    case stretch = 1
    case countStones = 2
    case hum = 3
    case roll = 4
}

enum PiboPixelMimic: Int {
    case none = 0
    case run = 1
    case swim = 2
    case bike = 3
    case yoga = 4
    case generic = 5
}

// Core's appearance and body-cue answers, already resolved; the motion layer only draws them.
final class PiboPixelLook {
    var bodyStage: Int = 2
    var leafStage: Int = 0
    var accessoryMask: Int = 0
    /// Core trick bits: stretch 1, count stones 2, hum 4, roll 8.
    var trickMask: Int = 0
    var leafGrowth: Double = 1
    var leafRipe: Bool = false
    var nightGlow: Bool = false
    /// Core sleep band: -1 unknown, 0 short, 1 usual, 2 well rested.
    var sleepBand: Int = -1
    var flexing: Bool = false
    var mimic: PiboPixelMimic = .none
}

private let TRICK_CYCLE_MS: Double = 26000
private let TRICK_PLAY_MS: Double = 2600
private let TRICK_BITS: [Int] = [1, 2, 4, 8]
private let TRICKS: [PiboPixelTrick] = [.stretch, .countStones, .hum, .roll]

/// Which unlocked trick plays at `timeMs`, rotating through them once per idle cycle.
func piboPixelTrickAt(_ trickMask: Int, _ timeMs: Double) -> PiboPixelTrick {
    var unlocked: [PiboPixelTrick] = []
    for (index, trick) in TRICKS.enumerated() where (trickMask & TRICK_BITS[index]) != 0 {
        unlocked.append(trick)
    }
    if unlocked.isEmpty { return .none }
    let t = max(0, timeMs) + 7000
    if t.truncatingRemainder(dividingBy: TRICK_CYCLE_MS) >= TRICK_PLAY_MS { return .none }
    return unlocked[jsFloor(t / TRICK_CYCLE_MS) % unlocked.count]
}

// Pixel motion runs on whole frames; smooth tweening between them reads as blur.
let PIBO_PIXEL_FPS: Int = 10
let PIBO_PIXEL_FRAME_MS: Double = 1000 / Double(PIBO_PIXEL_FPS)
let PIBO_PIXEL_PAT_MS: Double = 700

private func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }
private func jsRoundInt(_ x: Double) -> Int { Int(jsRound(x)) }
private func jsFloor(_ x: Double) -> Int { Int(x.rounded(.down)) }

func piboPixelActivity(_ animationStateID: String) -> PiboPixelActivity {
    let id = animationStateID.lowercased()
    if id.contains("celebrate") { return .celebrate }
    if id.contains("sleeping") { return .sleeping }
    if id.contains("waking") { return .waking }
    if id.contains("energetic") { return .energetic }
    if id.contains("tired") || id == "weak" || id.contains("resting") { return .tired }
    if id.contains("data-unknown") { return .dataUnknown }
    return .stable
}

private func step(_ timeMs: Double) -> Double {
    return Double(jsFloor(max(0, timeMs) / PIBO_PIXEL_FRAME_MS)) * PIBO_PIXEL_FRAME_MS
}

private func wave(_ timeMs: Double, _ periodMs: Double) -> Double {
    return sin(timeMs.truncatingRemainder(dividingBy: periodMs) / periodMs * Double.pi * 2)
}

// Short blink every `periodMs`, offset so state changes don't line blinks up.
private func blinking(_ timeMs: Double, _ periodMs: Double) -> Bool {
    return (timeMs + 900).truncatingRemainder(dividingBy: periodMs) < 150
}

private func hop(_ pose: PiboPixelPose, _ t: Double, _ periodMs: Double, _ height: Double) {
    let phase = t.truncatingRemainder(dividingBy: periodMs) / periodMs
    if phase < 0.2 {
        pose.squash = 0.22 // crouch
    } else if phase < 0.75 {
        let air = (phase - 0.2) / 0.55
        pose.lift = jsRound(sin(air * Double.pi) * height)
        pose.squash = air < 0.5 ? -0.18 : -0.06
        pose.armsUp = true
    } else if phase < 0.85 {
        pose.squash = 0.18 // land
    }
}

func piboPixelPose(_ activity: PiboPixelActivity, timeMs: Double, patAgeMs: Double = -1,
                   reduceMotion: Bool = false, look: PiboPixelLook? = nil) -> PiboPixelPose {
    let t = reduceMotion ? 0 : step(timeMs)
    let pose = PiboPixelPose()
    pose.twinkle = Double(jsFloor(t / PIBO_PIXEL_FRAME_MS))
    let sway = wave(t, 2400)
    pose.sproutSway = reduceMotion ? 0 : (sway > 0.35 ? 1 : (sway < -0.35 ? -1 : 0))
    switch activity {
    case .sleeping:
        pose.lying = true
        pose.eyes = .closed
        pose.sprout = .flat
        pose.sproutSway = 0
        pose.squash = wave(t, 3200) > 0 ? 0.04 : 0
    case .waking:
        pose.squash = 0.06
        pose.eyes = t.truncatingRemainder(dividingBy: 4200) < 2600 ? .sleepy : .wink
        pose.armsUp = t.truncatingRemainder(dividingBy: 6000) > 4800 // a slow stretch now and then
        if pose.armsUp { pose.squash = -0.12 }
    case .energetic:
        pose.eyes = .happy
        if !reduceMotion { hop(pose, t, 1100, 5) }
    case .celebrate:
        pose.eyes = .happy
        pose.blush = true
        pose.armsUp = true
        if !reduceMotion { hop(pose, t, 800, 8) }
    case .tired:
        pose.eyes = blinking(t, 2600) ? .closed : .sleepy
        pose.sprout = .droop
        pose.squash = 0.12 + (wave(t, 4000) > 0 ? 0.04 : 0)
        pose.lean = 1
    case .dataUnknown:
        pose.eyes = .dot
        pose.lean = t.truncatingRemainder(dividingBy: 5000) < 2500 ? -1 : 1
        pose.lookX = pose.lean
    default:
        pose.eyes = blinking(t, 3400) ? .closed : .open
        pose.squash = wave(t, 2800) > 0.5 ? 0.04 : 0
    }
    if activity == .celebrate { pose.abs = true }
    if let look = look { applyLook(pose, activity, look, t, reduceMotion) }
    if patAgeMs >= 0 && patAgeMs < PIBO_PIXEL_PAT_MS {
        applyPat(pose, reduceMotion ? 0 : step(patAgeMs))
    }
    return pose
}

private func awake(_ activity: PiboPixelActivity) -> Bool {
    return activity == .stable || activity == .energetic || activity == .celebrate || activity == .waking
}

// Growth appearance, then today's body cues, then an idle trick or workout mimic.
private func applyLook(_ pose: PiboPixelPose, _ activity: PiboPixelActivity, _ look: PiboPixelLook,
                       _ t: Double, _ reduceMotion: Bool) {
    pose.bodyStage = look.bodyStage
    pose.leafStage = look.leafStage
    pose.accessoryMask = look.accessoryMask
    pose.leafGrowth = look.leafGrowth
    pose.leafRipe = look.leafRipe
    pose.nightGlow = look.nightGlow
    if activity == .sleeping { return }
    if look.sleepBand == 0 { pose.eyeBags = true }
    if look.sleepBand == 2 && pose.eyes == .open && activity != .tired {
        pose.eyes = .star
    }
    if look.flexing && awake(activity) {
        pose.abs = true
        // Shows off now and then rather than holding the pose.
        if !reduceMotion && t.truncatingRemainder(dividingBy: 9000) < 1800 { pose.arms = .flex }
    }
    if reduceMotion || activity != .stable { return }
    if look.mimic != .none && t.truncatingRemainder(dividingBy: 15000) < 4500 {
        applyMimic(pose, look.mimic, t)
        return
    }
    applyTrick(pose, piboPixelTrickAt(look.trickMask, t), t)
}

private func applyTrick(_ pose: PiboPixelPose, _ trick: PiboPixelTrick, _ t: Double) {
    pose.trick = trick.rawValue
    switch trick {
    case .stretch:
        pose.armsUp = true
        pose.squash = -0.2
        pose.eyes = .closed
    case .countStones:
        // Looks down at the pile and nods once per stone.
        pose.lookX = t.truncatingRemainder(dividingBy: 1200) < 600 ? -1 : 0
        pose.squash = t.truncatingRemainder(dividingBy: 600) < 300 ? 0.06 : 0
        pose.eyes = .open
    case .hum:
        pose.eyes = .happy
        pose.lean = t.truncatingRemainder(dividingBy: 800) < 400 ? -1 : 1
    case .roll:
        // A roll in pixels: lean hard one way, squash flat, spring back.
        let phase = t.truncatingRemainder(dividingBy: 1300) / 1300
        pose.lean = phase < 0.5 ? -4 : 4
        pose.squash = phase < 0.25 || (phase > 0.5 && phase < 0.75) ? 0.25 : 0.05
        pose.eyes = .dizzy
    default:
        break
    }
}

private func applyMimic(_ pose: PiboPixelPose, _ mimic: PiboPixelMimic, _ t: Double) {
    pose.mimic = mimic.rawValue
    pose.blush = true
    switch mimic {
    case .run:
        pose.lean = 2
        pose.lift = t.truncatingRemainder(dividingBy: 300) < 150 ? 2 : 0
        pose.squash = t.truncatingRemainder(dividingBy: 300) < 150 ? -0.08 : 0.06
    case .swim:
        // Dry-land swimming: lying on the belly, paddling.
        pose.lying = true
        pose.eyes = .happy
        pose.lift = t.truncatingRemainder(dividingBy: 600) < 300 ? 1 : 0
    case .bike:
        pose.lean = 1
        pose.lift = t.truncatingRemainder(dividingBy: 400) < 200 ? 1 : 0
        pose.squash = 0.1
    case .yoga:
        // Tree pose: tall, arms up, wobbling.
        pose.armsUp = true
        pose.squash = -0.18
        pose.eyes = .closed
        pose.lean = t.truncatingRemainder(dividingBy: 1600) < 800 ? -1 : 1
    default:
        pose.arms = .flex
        pose.abs = true
    }
}

// Double-tap reaction layered on any state: squash, rebound, happy face, blush.
private func applyPat(_ pose: PiboPixelPose, _ ageMs: Double) {
    pose.blush = true
    if pose.lying {
        pose.eyes = ageMs < 400 ? .wink : pose.eyes
        return
    }
    pose.eyes = .happy
    pose.lift = 0
    if ageMs < 120 {
        pose.squash = 0.28
    } else if ageMs < 300 {
        pose.squash = -0.16
        pose.lift = 3
        pose.armsUp = true
    } else if ageMs < 420 {
        pose.squash = 0.12
    } else {
        pose.squash = 0
    }
}

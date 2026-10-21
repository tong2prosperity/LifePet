import Foundation

// How each of Core's day activities looks (decision 058), layered over the state pose.
// The director says what Pibo is doing and whether it is on the move; this file only
// turns that into feet, arms, eyes and props frame by frame.
//
// Ported from HarmonyPibo `pixel/character/PiboPixelDay.ets`.

enum PiboDayGait: Int {
    case still = 0
    case slow = 1
    case walk = 2
    case run = 3
}

/// What Pibo does in a season beat (decision 059): small acted moments, not cutscenes.
enum PiboStoryPose: Int {
    case none = 0
    /// Patting the pod beside it.
    case patPod = 1
    /// Digging a little hole and patting it flat.
    case dig = 2
    /// One arm up at a star.
    case point = 3
    /// Bent over the paper, writing.
    case write = 4
    /// Up on its toes twisting the antenna straight.
    case reach = 5
    /// Crouched, looking at the sprout for a long time.
    case crouch = 6
    /// Looking back at you, the way it does when it wants you to tap something.
    case beckon = 7
    // Season two, "小溪那边".
    /// Hammering a plank down.
    case hammer = 8
    /// Sitting with the old notebook open, reading.
    case read = 9
    /// Crossing out a line in the notebook and writing a new one.
    case correct = 10
    /// Carrying a plank under one arm.
    case carryPlank = 11
}

/// Core's day activity (Core `PiboDayActivity`). Declared here because the Swift twin of
/// `models/PiboDayValues.ets` does not exist yet; move it there when it does.
enum PiboDayActivity: Int {
    case idle = 0
    case stroll = 1
    case run = 2
    case swing = 3
    case chaseBeetle = 4
    case circleWindmill = 5
    case splash = 6
    case sitStool = 7
    case sortStones = 8
    case waterFlowers = 9
    case slowWalk = 10
    case sitRest = 11
    case napTree = 12
    case sleep = 13
    case stretch = 14
    case washFace = 15
    case sitQuestion = 16
    case umbrella = 17
    case puddleJump = 18
    case waitBeetle = 19
    case stargaze = 20
    case warmFire = 21
    case explore = 22
    case skipStones = 23
    case watchFish = 24
    case balanceLog = 25
    case hopStones = 26
    case smellFlowers = 27
    case rollDownHill = 28
    case lookout = 29
    case chaseButterfly = 30
    case playSnow = 31
    case hide = 32
    case peek = 33
    // Life echoes (decision 060), chosen by Core's `echo_choose`.
    case jog = 34
    case airBike = 35
    case paddle = 36
    case treePose = 37
    case jumpingJacks = 38
    case hike = 39
    case coolDown = 40
    case countSteps = 41
    case morningExercise = 42
    case yawning = 43
    case nightWatch = 44
    case picnic = 45
    case roastMushroom = 46
    case meditate = 47
    // Decision 065.
    case sniffMeal = 48
    case playFind = 49
    case rowBoat = 50
    case flyKite = 51
    case useTelescope = 52
}

final class PiboDayPoseInput {
    /// A season beat's acted pose; wins over the activity while it plays.
    var story: PiboStoryPose = .none
    var activity: PiboDayActivity = .idle
    var gait: PiboDayGait = .still
    var facing: Double = 0
    /// A find in Pibo's hands (-1 none).
    var carrying: Int = -1
    /// Shaking its head at an invitation.
    var refusing: Bool = false
    /// Waving hello.
    var waving: Bool = false
    /// The startled "!" moment of noticing you.
    var noticing: Bool = false
    /// Lying down on the spot (bed, nest, stargazing).
    var lying: Bool = false
    /// How long the current activity has run and how long it has left, for poses that
    /// change over an activity (a jog ends hands on hips, a picnic ends patting the belly).
    var elapsedMs: Double = 0
    var remainingMs: Double = 0
}

private let GAIT_PERIOD_MS: [Double] = [0, 640, 420, 240]

private func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }
private func jsRoundInt(_ x: Double) -> Int { Int(jsRound(x)) }
private func jsFloor(_ x: Double) -> Int { Int(x.rounded(.down)) }

private func stepPhase(_ t: Double, _ period: Double) -> Double {
    return period <= 0 ? 0 : t.truncatingRemainder(dividingBy: period) / period
}

private func walkCycle(_ pose: PiboPixelPose, _ input: PiboDayPoseInput, _ t: Double) {
    let gaitIndex = input.gait.rawValue
    let period = gaitIndex >= 0 && gaitIndex < GAIT_PERIOD_MS.count ? GAIT_PERIOD_MS[gaitIndex] : 420
    let phase = stepPhase(t, period)
    pose.stride = phase < 0.5 ? 1 : -1
    pose.lookX = input.facing
    pose.lean = input.facing * (input.gait == .run ? 2 : 1)
    pose.sproutSway = -input.facing
    if input.gait == .run {
        pose.lift = phase < 0.25 || (phase >= 0.5 && phase < 0.75) ? 2 : 0
        pose.squash = pose.lift > 0 ? -0.08 : 0.06
    } else {
        pose.lift = 0
        pose.squash = phase.truncatingRemainder(dividingBy: 0.5) < 0.25 ? 0.03 : 0
    }
}

private func hopTo(_ pose: PiboPixelPose, _ t: Double, _ period: Double, _ height: Double) {
    let phase = stepPhase(t, period)
    if phase < 0.2 {
        pose.squash = 0.2
        pose.lift = 0
    } else if phase < 0.8 {
        let air = (phase - 0.2) / 0.6
        pose.lift = jsRound(sin(air * Double.pi) * height)
        pose.squash = -0.14
    } else {
        pose.squash = 0.14
        pose.lift = 0
    }
}

/// Layers the day activity over `pose`. Eyes from the state pose (sleepy, star, bags)
/// are kept unless the activity needs its own.
func applyPiboDayPose(_ pose: PiboPixelPose, _ input: PiboDayPoseInput, _ t: Double,
                      _ reduceMotion: Bool) {
    let time = reduceMotion ? 0 : t
    if input.lying {
        pose.lying = true
        pose.sitting = false
    }
    let moving = input.gait != .still && !reduceMotion
    if moving {
        walkCycle(pose, input, time)
    } else if input.facing != 0 && !pose.lying {
        pose.lookX = input.facing
    }
    switch input.activity {
    case .swing:
        pose.sitting = true
        pose.eyes = .happy
        pose.blush = true
        pose.armsUp = jsFloor(time / 900) % 2 == 0
    case .chaseBeetle, .chaseButterfly:
        pose.eyes = .happy
        if input.activity == .chaseButterfly {
            pose.armsUp = jsFloor(time / 300) % 2 == 0
        } else if !moving {
            pose.squash = 0.14
            pose.lookX = input.facing
        }
    case .run, .circleWindmill:
        pose.eyes = .happy
    case .splash, .puddleJump:
        pose.eyes = .happy
        pose.blush = true
        if !moving && !reduceMotion {
            hopTo(pose, time, input.activity == .splash ? 700 : 900, 4)
        }
    case .sitStool, .sitRest:
        if !moving {
            pose.sitting = true
            pose.squash = max(pose.squash, 0.08)
        }
    case .sortStones:
        if !moving {
            pose.sitting = true
            pose.lookX = input.facing != 0 ? input.facing : -1
            pose.squash = time.truncatingRemainder(dividingBy: 600) < 300 ? 0.1 : 0.04
            pose.eyes = .open
        }
    case .waterFlowers:
        if !moving {
            pose.watering = true
            pose.lean = input.facing != 0 ? input.facing : 1
            pose.lookX = pose.lean
            pose.eyes = time.truncatingRemainder(dividingBy: 2400) < 1600 ? .happy : .open
        }
    case .napTree:
        if !moving {
            pose.sitting = true
            pose.eyes = .closed
            pose.sprout = .droop
            pose.lean = -1
            pose.squash = 0.14 + (time.truncatingRemainder(dividingBy: 3200) < 1600 ? 0.03 : 0)
        }
    case .sleep:
        pose.lying = true
        pose.eyes = .closed
    case .stretch:
        if !moving && time.truncatingRemainder(dividingBy: 5000) < 2600 {
            pose.armsUp = true
            pose.squash = -0.2
            pose.eyes = .closed
        }
    case .washFace:
        if !moving {
            pose.arms = .hug
            pose.squash = 0.12 + (time.truncatingRemainder(dividingBy: 500) < 250 ? 0.04 : 0)
            pose.eyes = .closed
            pose.lean = input.facing
        }
    case .sitQuestion:
        if !moving {
            pose.sitting = true
            pose.eyes = .dot
            pose.lookX = time.truncatingRemainder(dividingBy: 5000) < 2500 ? -1 : 1
        }
    case .umbrella:
        pose.umbrella = true
        if !moving {
            pose.eyes = time.truncatingRemainder(dividingBy: 4000) < 3000 ? .open : .happy
        }
    case .waitBeetle, .watchFish:
        if !moving {
            pose.sitting = true
            pose.eyes = .open
            pose.lookX = input.facing
            pose.lean = input.facing
        }
    case .stargaze:
        // Sitting with its face turned up: lying flat read as flopping over, the same as sleep.
        if !moving {
            pose.sitting = true
            pose.eyes = time.truncatingRemainder(dividingBy: 7000) < 6200 ? .open : .closed
            pose.lookUp = true
        }
    case .warmFire:
        if !moving {
            pose.sitting = true
            pose.arms = .hug
            pose.blush = true
            pose.lookX = input.facing
            pose.eyes = time.truncatingRemainder(dividingBy: 6000) < 4200 ? .happy : .open
        }
    case .skipStones:
        if !moving {
            let throwing = time.truncatingRemainder(dividingBy: 1800) < 500
            pose.armsUp = throwing
            pose.lean = throwing ? input.facing * 2 : 0
            pose.lookX = input.facing
            pose.eyes = throwing ? .open : .happy
        }
    case .balanceLog:
        pose.armsUp = true
        pose.lean = time.truncatingRemainder(dividingBy: 1400) < 700 ? -1 : 1
        pose.eyes = .open
    case .hopStones:
        pose.eyes = .happy
        if !moving && !reduceMotion { hopTo(pose, time, 800, 5) }
    case .smellFlowers:
        if !moving {
            // A long sniff, then a sneeze.
            let sneeze = time.truncatingRemainder(dividingBy: 6000) > 5400
            pose.squash = sneeze ? 0.26 : 0.12
            pose.eyes = sneeze ? .closed : .happy
            pose.blush = true
        }
    case .rollDownHill:
        if moving {
            let phase = time.truncatingRemainder(dividingBy: 600) / 600
            pose.lean = phase < 0.5 ? -4 : 4
            pose.squash = 0.2
            pose.eyes = .dizzy
            pose.stride = 0
        } else {
            pose.eyes = .happy
        }
    case .lookout:
        if !moving {
            pose.squash = -0.08
            pose.arms = .flex
            pose.lookX = time.truncatingRemainder(dividingBy: 6000) < 3000 ? -1 : 1
            pose.lookUp = time.truncatingRemainder(dividingBy: 9000) > 7000
        }
    case .playSnow:
        if !moving {
            pose.squash = 0.16
            pose.armsUp = time.truncatingRemainder(dividingBy: 1000) < 500
            pose.eyes = .happy
            pose.blush = true
        }
    // Decision 065.
    case .sniffMeal:
        if !moving {
            // Nose down to the sticker, a sniff, a look up at you.
            let sniff = time.truncatingRemainder(dividingBy: 1800) < 1100
            pose.lean = input.facing != 0 ? input.facing : 1
            pose.squash = sniff
                ? 0.14 + (time.truncatingRemainder(dividingBy: 300) < 150 ? 0.03 : 0)
                : 0.04
            pose.lookX = sniff ? pose.lean : 0
            pose.eyes = sniff ? .closed : .happy
            pose.blush = !sniff
        }
    case .playFind:
        if !moving {
            pose.eyes = .happy
            pose.lookX = time.truncatingRemainder(dividingBy: 3000) < 1500 ? -1 : 1
        }
    case .rowBoat:
        if !moving {
            // Sitting in the boat, rocking with it, watching the water.
            pose.sitting = true
            pose.lean = time.truncatingRemainder(dividingBy: 1800) < 900 ? -1 : 1
            pose.lookX = time.truncatingRemainder(dividingBy: 7000) < 3500 ? -1 : 1
            pose.eyes = time.truncatingRemainder(dividingBy: 5000) < 4300 ? .open : .happy
        }
    case .flyKite:
        if !moving {
            pose.armsUp = true
            pose.lookUp = true
            pose.lookX = -1
            pose.lean = time.truncatingRemainder(dividingBy: 1200) < 600 ? 0 : 1
            pose.eyes = .happy
        }
    case .useTelescope:
        if !moving {
            // One eye to the glass, now and then looking up with both.
            let looking = time.truncatingRemainder(dividingBy: 6000) < 4600
            pose.lean = input.facing != 0 ? input.facing : -1
            pose.lookX = pose.lean
            pose.lookUp = !looking
            pose.eyes = looking ? .squint : .open
        }
    case .peek, .hide:
        if !moving {
            pose.lookX = time.truncatingRemainder(dividingBy: 2400) < 1200 ? -1 : 1
            pose.eyes = .open
        }
    default:
        applyEchoPose(pose, input, time, moving, reduceMotion)
    }
    if input.story != .none && (!moving || input.story == .carryPlank) {
        applyStoryPose(pose, input, time)
    }
    if input.carrying >= 0 && !pose.lying && input.story != .reach {
        pose.holding = input.carrying
        pose.arms = .hug
        pose.armsUp = false
        pose.watering = false
        // Playing with a find: a little hop with it now and then.
        if input.activity == .playFind && !moving && !reduceMotion
            && time.truncatingRemainder(dividingBy: 2000) < 450 {
            pose.lift = max(pose.lift, 3)
            pose.squash = -0.1
        }
    }
    if input.noticing {
        pose.eyes = .open
        pose.squash = -0.12
        pose.lift = max(pose.lift, 1)
        pose.lookX = 0
    }
    if input.waving && !pose.lying {
        pose.armsUp = jsFloor(time / 260) % 2 == 0
        pose.eyes = .happy
        pose.lookX = 0
    }
    if input.refusing {
        pose.lean = jsFloor(time / 160) % 2 == 0 ? -2 : 2
        pose.lookX = pose.lean > 0 ? 1 : -1
        pose.eyes = .closed
        pose.armsUp = false
    }
}

/// Ends of an activity: the last few seconds of a jog or a picnic look different.
private let WIND_DOWN_MS: Double = 3500

/// Life echoes (decision 060): Pibo's own version of what you did today.
private func applyEchoPose(_ pose: PiboPixelPose, _ input: PiboDayPoseInput, _ time: Double,
                           _ moving: Bool, _ reduceMotion: Bool) {
    let facing: Double = input.facing != 0 ? input.facing : 1
    let ending = input.remainingMs > 0 && input.remainingMs < WIND_DOWN_MS
    switch input.activity {
    case .jog:
        pose.headband = true
        if moving {
            pose.eyes = .closed
            pose.arms = .flex
        } else {
            // Done: hands on hips, panting.
            pose.arms = .hips
            pose.mouth = .tongue
            pose.sweat = true
            pose.squash = time.truncatingRemainder(dividingBy: 500) < 250 ? 0.1 : 0.02
            pose.eyes = .happy
        }
    case .airBike:
        if !moving {
            // Sitting back, pedalling the air faster and faster, then dizzy.
            pose.sitting = true
            pose.lean = -1
            let fast = input.elapsedMs > 6000
            let period: Double = fast ? 140 : 300
            // Up on an invisible saddle, so the feet can go round underneath.
            pose.stride = jsFloor(time / period) % 2 == 0 ? 4 : -4
            pose.lift = 3
            pose.arms = .hug
            pose.mouth = fast ? .open : .none
            pose.eyes = ending ? .dizzy : (fast ? .closed : .open)
            if ending && !reduceMotion { pose.lean = jsFloor(time / 150) % 2 == 0 ? -2 : 2 }
        }
    case .paddle:
        if !moving {
            // Doggy paddle: low and wide, arms going in turn; on the grass it is a dry swim.
            pose.squash = 0.24
            pose.armsUp = jsFloor(time / 260) % 2 == 0
            pose.lean = jsFloor(time / 260) % 2 == 0 ? -1 : 1
            pose.eyes = .squint
            pose.mouth = jsFloor(time / 520) % 2 == 0 ? .open : .none
            pose.blush = true
        }
    case .treePose:
        if !moving {
            // One foot up, hands together overhead, wobbling, then steady and pleased.
            pose.footUp = facing
            pose.reachBoth = true
            pose.armsUp = false
            pose.squash = -0.12
            let steady = input.elapsedMs > 5000
            pose.lean = steady
                ? 0
                : (jsFloor(time / 380) % 4 == 0 ? -2 : (jsFloor(time / 380) % 4 == 2 ? 2 : 0))
            pose.eyes = steady ? .happy : .dot
        }
    case .jumpingJacks:
        if !moving && !reduceMotion {
            let out = jsFloor(time / 330) % 2 == 0
            pose.feetWide = out
            pose.armsUp = out
            pose.lift = out ? 2 : 0
            pose.squash = out ? -0.08 : 0.12
            // Loses count halfway: stops, looks puzzled, starts over.
            let lost = input.elapsedMs > 5000 && input.elapsedMs < 6800
            if lost {
                pose.feetWide = false
                pose.armsUp = false
                pose.lift = 0
                pose.squash = 0
                pose.eyes = .uneven
            } else {
                pose.eyes = .closed
            }
        }
    case .hike:
        pose.accessoryMask = pose.accessoryMask | 4
        if moving {
            pose.eyes = .open
            pose.lookUp = time.truncatingRemainder(dividingBy: 3000) < 800
        } else {
            pose.held = .map
            pose.eyes = .dot
            pose.lookX = time.truncatingRemainder(dividingBy: 4000) < 2000 ? -1 : 1
        }
    case .coolDown:
        if !moving {
            pose.sitting = true
            pose.sweat = time.truncatingRemainder(dividingBy: 4000) < 2600
            let drinking = time.truncatingRemainder(dividingBy: 5200) > 4000
            pose.held = drinking ? .cup : .fan
            pose.propPhase = drinking ? 1 : Double(jsFloor(time / 220))
            pose.eyes = drinking ? .closed : .happy
            pose.mouth = drinking ? .none : .tongue
            pose.squash = 0.12
        }
    case .countSteps:
        // Big careful steps, eyes on its feet; now and then it loses count and starts over.
        pose.eyes = .dot
        if moving {
            pose.lookX = facing
            pose.squash = time.truncatingRemainder(dividingBy: 640) < 320 ? -0.06 : 0.04
        } else {
            pose.eyes = .uneven
            pose.lookUp = true
        }
    case .morningExercise:
        if !moving && !reduceMotion {
            // Arms up, side bends, a little twirl: the leaf stands extra tall.
            let beat = jsFloor(time / 600) % 4
            pose.armsUp = beat == 0 || beat == 2
            pose.lean = beat == 1 ? -3 : (beat == 3 ? 3 : 0)
            pose.lookX = beat == 1 ? -1 : (beat == 3 ? 1 : 0)
            pose.squash = pose.armsUp ? -0.16 : 0.04
            pose.sprout = .upright
            pose.sproutSway = 0
            pose.eyes = .happy
            pose.leafGrowth = min(1, pose.leafGrowth + 0.15)
        }
    case .yawning:
        pose.sprout = .droop
        pose.eyes = .sleepy
        if time.truncatingRemainder(dividingBy: 5000) > 3600 {
            pose.mouth = .yawn
            pose.eyes = .closed
            pose.squash = -0.12
            if !moving { pose.armsUp = true }
        }
    case .nightWatch:
        // On patrol with a lantern and a nightcap, nodding off between steps.
        pose.nightCap = true
        pose.held = .lantern
        let nod = !moving && time.truncatingRemainder(dividingBy: 4200) > 2800
        pose.eyes = nod ? .closed : .sleepy
        if nod {
            pose.lean = facing
            pose.squash = 0.1
        }
    case .picnic:
        if !moving {
            pose.sitting = true
            if ending {
                // Full: pats its belly.
                pose.arms = .hug
                pose.squash = 0.16 + (time.truncatingRemainder(dividingBy: 600) < 300 ? 0.04 : 0)
                pose.eyes = .happy
                pose.blush = true
            } else {
                let bite = time.truncatingRemainder(dividingBy: 1600) < 700
                pose.held = .berry
                pose.propPhase = bite ? 1 : 0
                pose.mouth = bite ? .chew : .none
                pose.eyes = bite ? .closed : .open
            }
        }
    case .roastMushroom:
        if !moving {
            pose.sitting = true
            pose.held = .skewer
            pose.lookX = facing
            pose.lean = facing
            let sniff = time.truncatingRemainder(dividingBy: 4000) > 3000
            pose.eyes = sniff ? .closed : .happy
            pose.lookUp = sniff
            pose.blush = true
        }
    case .meditate:
        if !moving {
            // Eyes shut, the body slowly swelling and settling with each breath.
            pose.sitting = true
            pose.eyes = .closed
            pose.arms = .hug
            let breath = (sin(time / 4000 * Double.pi * 2) + 1) / 2
            pose.squash = reduceMotion ? 0.06 : 0.02 + breath * 0.1
            pose.sprout = .upright
            pose.lookX = 0
        }
    default:
        break
    }
}

private func applyStoryPose(_ pose: PiboPixelPose, _ input: PiboDayPoseInput, _ time: Double) {
    let facing: Double = input.facing != 0 ? input.facing : 1
    pose.lying = false
    switch input.story {
    case .patPod:
        pose.lookX = facing
        pose.lean = facing
        pose.armsUp = jsFloor(time / 380) % 2 == 0
        pose.eyes = .happy
    case .dig:
        let scoop = jsFloor(time / 300) % 2 == 0
        pose.lookX = facing
        pose.lean = scoop ? facing * 2 : facing
        pose.squash = scoop ? 0.18 : 0.08
        pose.arms = .hug
        pose.eyes = .open
    case .point:
        pose.lookUp = true
        pose.reach = facing
        pose.lookX = facing
        pose.eyes = time.truncatingRemainder(dividingBy: 4000) < 3400 ? .open : .happy
    case .write:
        pose.sitting = true
        pose.lean = facing
        pose.lookX = facing
        pose.arms = .hug
        pose.eyes = .dot
        pose.squash = 0.1 + (time.truncatingRemainder(dividingBy: 700) < 350 ? 0.03 : 0)
    case .reach:
        // Twisting the antenna on the low pod: leaning over, one arm out, screwing it in.
        let twist = jsFloor(time / 240) % 2 == 0
        pose.reach = facing
        pose.reachLow = true
        pose.lean = facing * (twist ? 3 : 2)
        pose.lookX = facing
        pose.squash = twist ? 0.1 : 0.04
        pose.eyes = .closed
    case .crouch:
        pose.sitting = true
        pose.squash = 0.16
        pose.lookX = facing
        pose.lean = facing
        pose.eyes = time.truncatingRemainder(dividingBy: 5200) < 4600 ? .open : .happy
    case .beckon:
        pose.lookX = 0
        pose.armsUp = jsFloor(time / 500) % 2 == 0
        pose.eyes = .open
        pose.blush = true
    case .hammer:
        let hit = jsFloor(time / 260) % 2 == 0
        pose.sitting = true
        pose.held = .hammer
        pose.propPhase = hit ? 0 : 1
        pose.lookX = facing
        pose.lean = hit ? facing : facing * 2
        pose.squash = hit ? 0.06 : 0.14
        pose.eyes = hit ? .open : .squint
    case .read:
        pose.sitting = true
        pose.held = .notebook
        pose.lookX = 0
        pose.eyes = time.truncatingRemainder(dividingBy: 3000) < 2600 ? .dot : .open
        pose.squash = 0.08
    case .correct:
        pose.sitting = true
        pose.held = .notebook
        pose.lean = facing
        pose.lookX = facing
        pose.eyes = .dot
        pose.squash = 0.1 + (time.truncatingRemainder(dividingBy: 500) < 250 ? 0.03 : 0)
    case .carryPlank:
        pose.held = .plank
        pose.lookX = facing
        pose.eyes = .happy
    default:
        break
    }
}

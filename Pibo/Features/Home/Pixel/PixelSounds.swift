import Foundation
import PiboCore

// The pixel Home's short cues: what changed on the stage → which sound. Plain values, so
// the pixel layer can ask for a cue without knowing about playback.
//
// Ported from HarmonyPibo `models/PiboPixelSoundValues.ets` and `pixel/audio/PixelStageSounds.ets`.
// The files live in `Resources/Audio/PixelSFX/px_<rawValue>.m4a`; HarmonyOS renders them
// with `tools/render_pixel_sfx.mjs`.

enum PiboPixelSound: String, CaseIterable {
    case shapeIn = "shape_in"
    case shapeOut = "shape_out"
    case shapeTry = "shape_try"
    case shapeStrain = "shape_strain"
    case shapeHelped = "shape_helped"
    case shapeSelfBack = "shape_self_back"
    case sneeze
    case formStone = "form_stone"
    case formMushroom = "form_mushroom"
    case formBike = "form_bike"
    case formFish = "form_fish"
    case formSapling = "form_sapling"
    case formSpring = "form_spring"
    case formPillow = "form_pillow"
    case formLamp = "form_lamp"
    case formBowl = "form_bowl"
    case formSneaker = "form_sneaker"
    case emoteSurprised = "emote_surprised"
    case emoteShy = "emote_shy"
    case emoteProud = "emote_proud"
    case emotePuzzled = "emote_puzzled"
    case emoteSulky = "emote_sulky"
    case emoteBored = "emote_bored"
    case emoteMoved = "emote_moved"
    case emoteShiver = "emote_shiver"
    case emoteHot = "emote_hot"
    case fidgetYawn = "fidget_yawn"
    case fidgetStumble = "fidget_stumble"
    case fidgetHiccup = "fidget_hiccup"
    case sceneClearing = "scene_clearing"
    case sceneCreek = "scene_creek"
    case sceneHill = "scene_hill"
    case stateSleeping = "state_sleeping"
    case stateWaking = "state_waking"
    case stateStable = "state_stable"
    case stateEnergetic = "state_energetic"
    case stateTired = "state_tired"
    case stateDataUnknown = "state_data_unknown"
    case stateCelebrate = "state_celebrate"
    case badgeRead = "badge_read"
    case reportPrint = "report_print"
    case cameraSnap = "camera_snap"
    case switchClick = "switch_click"

    var assetName: String { "px_\(rawValue)" }
}

/// The mix, on the same scale as the Home cues (at most 0.3). Cues that come by themselves
/// (a scene, a feeling, a fidget) sit lower than the ones a tap or a change asks for.
func piboPixelSoundVolume(_ sound: PiboPixelSound) -> Float {
    switch sound {
    case .shapeStrain, .badgeRead, .switchClick, .fidgetHiccup, .fidgetYawn, .fidgetStumble:
        return 0.14
    case .sceneClearing, .sceneCreek, .sceneHill,
         .stateSleeping, .stateWaking, .stateStable, .stateEnergetic, .stateTired, .stateDataUnknown:
        return 0.16
    case .emoteSurprised, .emoteShy, .emoteProud, .emotePuzzled, .emoteSulky, .emoteBored,
         .emoteMoved, .emoteShiver, .emoteHot, .reportPrint:
        return 0.18
    default:
        return 0.26
    }
}

/// At night and while Pibo sleeps everything is quieter.
let PIBO_PIXEL_SOUND_HUSH: Float = 0.55

private let FORM_SOUNDS: [PiboPixelSound] = [
    .formStone, .formMushroom, .formBike, .formFish, .formSapling,
    .formSpring, .formPillow, .formLamp, .formBowl, .formSneaker
]

/// Each shape has its own voice: a stone thunks, a bike rings, a fish blubs.
func piboFormSound(_ form: Int) -> PiboPixelSound? {
    let index = form - PiboForm.stone.rawValue
    return index >= 0 && index < FORM_SOUNDS.count ? FORM_SOUNDS[index] : nil
}

func piboEmoteSound(_ emote: Int) -> PiboPixelSound? {
    switch PiboEmote(rawValue: emote) {
    case .surprised: .emoteSurprised
    case .shy: .emoteShy
    case .proud: .emoteProud
    case .puzzled: .emotePuzzled
    case .sulky: .emoteSulky
    case .bored: .emoteBored
    case .moved: .emoteMoved
    case .sneeze: .sneeze
    case .shiver: .emoteShiver
    case .hot: .emoteHot
    default: nil
    }
}

/// Only the fidgets you would hear; a blink or a look around stays silent.
func piboFidgetSound(_ fidget: Int) -> PiboPixelSound? {
    switch PiboFidget(rawValue: fidget) {
    case .yawn: .fidgetYawn
    case .stumble: .fidgetStumble
    case .hiccup: .fidgetHiccup
    default: nil
    }
}

func piboSceneSound(_ scene: Int) -> PiboPixelSound? {
    switch PiboCoreDayScene(rawValue: Int32(clamping: scene)) {
    case .clearing: .sceneClearing
    case .creek: .sceneCreek
    case .hill: .sceneHill
    default: nil
    }
}

/// Keyed by the stage's `PiboPixelActivity` (0 data unknown … 6 celebrate).
private let STATE_SOUNDS: [PiboPixelSound] = [
    .stateDataUnknown, .stateSleeping, .stateWaking, .stateStable,
    .stateEnergetic, .stateTired, .stateCelebrate
]

func piboStateSound(_ activity: Int) -> PiboPixelSound? {
    activity >= 0 && activity < STATE_SOUNDS.count ? STATE_SOUNDS[activity] : nil
}

// MARK: - The observer

/// What the stage's actor did since the last frame.
struct PixelSoundActor {
    var form = 0
    var formPhase = 0
    var formAge: Double = 0
    var emote = 0
    var fidget = 0
}

/// Watches the stage frame by frame and says which cue a change deserves: the puff of a
/// shape and the shape's own voice, a stuck shape straining, a feeling or an audible fidget,
/// a new scene, a new Core state. Pure: the stage plays what it returns.
final class PixelStageSounds {
    /// Matches the stage's strain puff: one try to change back every 2.4 s.
    private static let strainEveryMs: Double = 2400

    private var primed = false
    private var phase = PixelShapePhase.none
    private var emote = 0
    private var fidget = 0
    private var strainCycle = -1
    private var scene = -1
    private var state = -1

    /// The first frame only sets the baseline, so opening Home in the middle of something
    /// stays quiet.
    func observe(_ actor: PixelSoundActor) -> [PiboPixelSound] {
        var cues: [PiboPixelSound] = []
        let phase = PixelShapePhase(rawValue: actor.formPhase) ?? .none
        if primed {
            if phase != self.phase {
                if phase == .in { cues.append(.shapeIn) }
                if phase == .hold && self.phase == .in, let voice = piboFormSound(actor.form) {
                    cues.append(voice)
                }
                // From a stuck shape, Home plays how it came back (helped or by itself).
                if phase == .out && self.phase != .stuck { cues.append(.shapeOut) }
                if phase == .attempt { cues.append(.shapeTry) }
            }
            if phase == .stuck {
                let cycle = Int(actor.formAge / Self.strainEveryMs)
                if cycle != strainCycle && self.phase == .stuck { cues.append(.shapeStrain) }
                strainCycle = cycle
            }
            if actor.emote != emote && actor.emote > 0, let voice = piboEmoteSound(actor.emote) {
                cues.append(voice)
            }
            if actor.fidget != fidget && actor.fidget > 0, let voice = piboFidgetSound(actor.fidget) {
                cues.append(voice)
            }
        }
        if phase != .stuck { strainCycle = -1 }
        primed = true
        self.phase = phase
        self.emote = actor.emote
        self.fidget = actor.fidget
        return cues
    }

    /// Arriving in a scene. The first scene of a visit is not an arrival.
    func sceneChanged(_ scene: Int) -> PiboPixelSound? {
        let first = self.scene < 0
        let changed = scene != self.scene
        self.scene = scene
        return first || !changed ? nil : piboSceneSound(scene)
    }

    /// The Core state Pibo shows (as the stage's `PiboPixelActivity`). The first one is not
    /// a change; coming down from a celebration is not news either.
    func stateChanged(_ activity: Int) -> PiboPixelSound? {
        let first = state < 0
        let changed = activity != state
        let settling = state == PiboPixelActivity.celebrate.rawValue
        state = activity
        return first || !changed || settling ? nil : piboStateSound(activity)
    }
}

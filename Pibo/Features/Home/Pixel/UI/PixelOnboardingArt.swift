import SwiftUI

// The pixel first run (decision 059): the forest at dusk with the pod tipped into the
// ground and Pibo peeking out from behind it, and three small pictures for what you can do
// here. Drawn with the stage's own generators so the first look matches Home.
//
// Ported from HarmonyPibo `pixel/ui/PixelOnboardingArt.ets`.

private let ONBOARDING_FOREST_SEED: Int = 2026

// Decision 065 (061 §5): the first look is a stone by the pod that blinks, then puffs back
// into Pibo. Times from when the welcome first shows.
private let STONE_BLINK_AT_MS: Double = 900
private let STONE_BLINK_MS: Double = 380
let ONBOARDING_POOF_AT_MS: Double = 2300
private let ONBOARDING_POOF_MS: Double = 450
/// After this the welcome is still: Pibo peeking out from behind the pod.
let ONBOARDING_INTRO_MS: Double = ONBOARDING_POOF_AT_MS + ONBOARDING_POOF_MS

/// The art for each line of the overview.
enum PixelOnboardingIcon: Int {
    case together = 0
    case grow = 1
    case life = 2
}

/// The pod sits higher than on Home, between the text above and the buttons below.
private func welcomeLayout(_ width: Int, _ height: Int) -> PixelForestLayout {
    var shifted = pixelForestLayout(width, height)
    shifted.groundY = PixelMath.round(Double(height) * 0.6) - 50
    return shifted
}

/// `ageMs` is how long the welcome has been showing; from `ONBOARDING_INTRO_MS` on (and
/// under Reduce Motion, which passes it) Pibo is itself.
func paintOnboardingForest(_ frame: PixelFrame, ageMs: Double = ONBOARDING_INTRO_MS) {
    let layout = pixelForestLayout(frame.width, frame.height)
    drawPixelForestStatic(frame, layout, ONBOARDING_FOREST_SEED, .dusk)
    let stage = welcomeLayout(frame.width, frame.height)
    let pod = pixelSeasonBoxes(stage, PixelSeasonLook())[0]
    let poof = (ageMs - ONBOARDING_POOF_AT_MS) / ONBOARDING_POOF_MS
    if ageMs < ONBOARDING_INTRO_MS && poof < 0.5 {
        // A stone in front of the pod, with eyes that open once and shut again.
        let stone = PiboFormLook()
        stone.form = .stone
        stone.disguise = 2
        if ageMs >= STONE_BLINK_AT_MS && ageMs < STONE_BLINK_AT_MS + STONE_BLINK_MS { stone.disguise = 0 }
        drawPixelSeason(frame, stage, PixelSeasonLook(), -1, true)
        drawPiboForm(frame, Double(pod.x + pod.w + 4), Double(pod.base + 2), stone)
        if poof >= 0 { drawPiboPoof(frame, Double(pod.x + pod.w + 4), Double(pod.base - 6), poof) }
        return
    }
    // Peeking: the hull hides Pibo's lower half; it leans out toward its right edge.
    let pose = PiboPixelPose()
    pose.bodyStage = 0
    pose.leafGrowth = 0.4
    pose.lean = 2
    pose.eyes = .open
    pose.blush = true
    drawPiboPixel(frame, Double(pod.x + pod.w - 7), Double(pod.base - 4), pose)
    // Pibo is behind the pod, so the pod is drawn over it.
    drawPixelSeason(frame, stage, PixelSeasonLook(), -1, true)
    if poof >= 0 && poof < 1 {
        drawPiboPoof(frame, Double(pod.x + pod.w - 7), Double(pod.base - 10), poof)
    }
}

func paintOnboardingIcon(_ frame: PixelFrame, icon: PixelOnboardingIcon) {
    let pose = PiboPixelPose()
    pose.bodyStage = 1
    let cx = (Double(frame.width) / 2).rounded()
    let ground = Double(frame.height - 3)
    switch icon {
    case .together:
        pose.eyes = .happy
        pose.blush = true
        pose.armsUp = true
        pose.leafGrowth = 0.5
    case .grow:
        pose.leafGrowth = 1
        pose.leafRipe = true
        pose.twinkle = 3
        pose.lookUp = true
    case .life:
        pose.stride = 1
        pose.lookX = 1
        pose.lean = 1
        pose.leafGrowth = 0.6
        pose.holding = 0
    }
    drawPiboPixel(frame, cx, ground, pose)
}

/// The welcome's forest, ticking through the stone → Pibo puff.
struct PixelOnboardingForestView: View {
    var ageMs: Double = ONBOARDING_INTRO_MS
    var logicalWidth = 120
    var logicalHeight = 200

    var body: some View {
        PixelCanvas(logicalWidth: logicalWidth, logicalHeight: logicalHeight,
                    mood: .dusk,
                    revision: Int(ageMs / 60),
                    fitPhysicalPixels: true) { frame in
            paintOnboardingForest(frame, ageMs: ageMs)
        }
    }
}

/// One of the three overview pictures. ArkTS draws it into a 40 × 48 canvas.
struct PixelOnboardingIconView: View {
    var icon: PixelOnboardingIcon = .together
    var logicalWidth = 40
    var logicalHeight = 48

    var body: some View {
        PixelCanvas(logicalWidth: logicalWidth, logicalHeight: logicalHeight,
                    revision: icon.rawValue) { frame in
            paintOnboardingIcon(frame, icon: icon)
        }
    }
}

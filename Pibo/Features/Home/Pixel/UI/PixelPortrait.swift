import PiboCore
import SwiftUI

// A small forest with Pibo in it: the share card's background, the login page's banner and
// the scene chips beside the share card. Everything is drawn by the stage's own generators,
// so the picture always matches Home.
//
// Ported from HarmonyPibo `pixel/ui/PixelPortrait.ets`.

/// The light a share scene is painted in. HarmonyOS keys this off the scene id string; iOS
/// has `PiboFlatWorldScene`, so the cases map one to one.
func pixelPortraitMood(_ scene: PiboFlatWorldScene) -> PixelMood {
    switch scene {
    case .nightClouds: .night
    case .rainGorge: .rain
    case .coralDusk, .dawnCreek: .dusk
    case .riverValley: .day
    }
}

/// The forest with Pibo standing two thirds across, facing in.
func paintPixelPortrait(_ frame: PixelFrame, scene: PiboFlatWorldScene,
                        stateID: String = "pibo-state-stable-forest-idle",
                        look appearance: PiboPixelLook = PiboPixelLook()) {
    let mood = pixelPortraitMood(scene)
    let layout = pixelForestLayout(frame.width, frame.height)
    drawPixelForestStatic(frame, layout, 2026, mood)
    drawPixelForestLife(frame, layout, 2026, mood, mood == .rain, 0)
    drawPiboPixel(frame, (Double(frame.width) * 0.66).rounded(), Double(layout.groundY),
                  piboPixelPose(piboPixelActivity(stateID), timeMs: 0, patAgeMs: -1,
                                reduceMotion: true, look: appearance))
}

/// A static portrait at any size (the canvas scales by whole pixels).
struct PixelPortraitView: View {
    var scene: PiboFlatWorldScene = .riverValley
    var stateID: String = "pibo-state-stable-forest-idle"
    var appearance = PiboPixelLook()
    /// ArkUI's portrait is 106 × 142 logical px whatever the frame; the canvas shrinks it.
    var logicalWidth = 106
    var logicalHeight = 142

    var body: some View {
        PixelCanvas(logicalWidth: logicalWidth, logicalHeight: logicalHeight,
                    mood: pixelPortraitMood(scene),
                    revision: scene.resourceName.count + stateID.count,
                    fitPhysicalPixels: true) { frame in
            paintPixelPortrait(frame, scene: scene, stateID: stateID, look: appearance)
        }
    }
}

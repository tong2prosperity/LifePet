import SwiftUI

// The settings page's header picture: Pibo's pod with Pibo beside it, tools in hand. The
// antenna is bent until season one fixes it; with the forest sound on, it sends little
// waves.
//
// Ported from HarmonyPibo `pixel/ui/PodPanelArt.ets`.

let POD_PANEL_W: Int = 96
let POD_PANEL_H: Int = 48
private let POD_GROUND_Y: Int = 42
private let POD_PANEL_X: Int = 16

func paintPodPanel(_ frame: PixelFrame, podFixed: Bool, soundOn: Bool, tick: Int) {
    frame.clear(.skyLow)
    frame.fillRect(0, Double(POD_GROUND_Y), Double(frame.width),
                   Double(frame.height - POD_GROUND_Y), .groundMid)
    frame.fillRect(0, Double(POD_GROUND_Y), Double(frame.width), 1, .groundLight)
    for x in stride(from: 3, to: frame.width, by: 7) { frame.set(x, POD_GROUND_Y - 1, .grassTip) }

    var look = PixelSeasonLook()
    look.podFixed = podFixed
    look.timeMs = Double(tick * 400)
    drawPixelPodAt(frame, POD_PANEL_X, POD_GROUND_Y + 1, look)

    if soundOn {
        // Two arcs either side of the antenna's tip, the outer one every other beat. Bent
        // over, the tip hangs lower and to the right.
        let tip = pixelPodTipAt(POD_PANEL_X, POD_GROUND_Y + 1)
        let lx = podFixed ? tip[0] : tip[0] + 4
        let ly = podFixed ? tip[1] : tip[1] + 5
        for k in 0..<3 {
            frame.set(lx - 2, ly - 1 + k, .sun)
            frame.set(lx + 3, ly - 1 + k, .sun)
            if tick % 2 == 0 {
                frame.set(lx - 4, ly - 2 + k * 2, .sun)
                frame.set(lx + 5, ly - 2 + k * 2, .sun)
            }
        }
    }

    let pose = PiboPixelPose()
    pose.bodyStage = 0
    pose.leafGrowth = 0.8
    pose.held = .hammer
    pose.propPhase = Double(tick % 4)
    pose.arms = .rest
    pose.lookX = -1
    pose.eyes = podFixed ? .happy : .open
    drawPiboPixel(frame, 66, Double(POD_GROUND_Y + 1), pose)
}

/// The panel as a static picture (settings header, about page).
struct PixelPodPanelView: View {
    var podFixed = false
    var soundOn = false
    var tick = 0

    var body: some View {
        PixelCanvas(logicalWidth: POD_PANEL_W, logicalHeight: POD_PANEL_H,
                    revision: (podFixed ? 1 : 0) + (soundOn ? 2 : 0) + tick * 4) { frame in
            paintPodPanel(frame, podFixed: podFixed, soundOn: soundOn, tick: tick)
        }
        .aspectRatio(CGFloat(POD_PANEL_W) / CGFloat(POD_PANEL_H), contentMode: .fit)
        .overlay { Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2) }
        .accessibilityHidden(true)
    }
}

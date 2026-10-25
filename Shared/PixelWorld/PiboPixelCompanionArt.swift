import CoreGraphics
import Foundation

/// Small platform canvases use the phone's exact character rasterizer. The input
/// carries resolved Core semantics; this file only chooses coordinates and inks.
enum PiboPixelCompanionArt {
    struct Look {
        var stateID = "dataUnknown"
        var bodyStage = 0
        var leafStage = 0
        var accessoryMask = 0
        var progress: Double = 0
        var ripe = false
        var form = 0
        var stuck = false
        var holding = -1
        var thought = false
        var leafPull: Double = 0
    }

    static func image(look: Look, time: Double = 0, patAge: Double = -1,
                      mood: PixelMood = .day, reduceMotion: Bool = false) -> CGImage? {
        PixelImageRenderer.render(logicalWidth: 88, logicalHeight: 88, palette: PixelPalette.rgb(mood)) { frame in
            draw(frame, look: look, time: time, patAge: patAge, mood: mood, reduceMotion: reduceMotion)
        }
    }

    static func draw(_ frame: PixelFrame, look: Look, time: Double, patAge: Double,
                     mood: PixelMood, reduceMotion: Bool) {
        frame.clear()
        // A little moss island, without a rectangular sky on an OLED watch.
        let cx = frame.width / 2
        let ground = 64
        for y in -7...7 {
            for x in -35...35 where Double(x * x) / 1225 + Double(y * y) / 49 <= 1 {
                frame.set(cx + x, ground + y + 3, y < 0 ? .groundLight : .groundMid)
            }
        }
        frame.fillRect(cx - 25, ground - 8, cx - 23, ground + 1, .woodDark)
        frame.fillRect(cx - 29, ground - 9, cx - 19, ground - 4, .woodLight)
        frame.fillRect(cx - 28, ground - 8, cx - 20, ground - 5, .signFace)
        for x in [-20, 23] {
            frame.set(cx + x, ground + 1, .flowerA)
            frame.set(cx + x, ground + 2, .leafMid)
        }
        if mood == .night {
            let tick = reduceMotion ? 0 : Int(time / 600)
            for (i, p) in [[13, 12], [66, 15], [74, 36], [21, 29]].enumerated() {
                frame.set(p[0], p[1], (tick + i) % 3 == 0 ? .glow : .cloudShade)
            }
        }
        let activity = activity(look.stateID)
        let badge = PiboPixelBadge(rawValue: activity.rawValue + 1) ?? .dataUnknown
        if let form = PiboForm(rawValue: look.form), form != .none {
            let formLook = PiboFormLook()
            formLook.form = form
            formLook.timeMs = reduceMotion ? 0 : time
            formLook.stuck = look.stuck
            formLook.reduceMotion = reduceMotion
            formLook.badge = badge
            drawPiboForm(frame, Double(cx), Double(ground), formLook)
        } else {
            let body = PiboPixelLook()
            body.bodyStage = look.bodyStage
            body.leafStage = look.leafStage
            body.accessoryMask = look.accessoryMask
            body.leafGrowth = look.progress
            body.leafRipe = look.ripe
            let pose = piboPixelPose(activity, timeMs: time, patAgeMs: patAge,
                                     reduceMotion: reduceMotion, look: body)
            pose.badge = badge
            pose.leafPull = look.leafPull
            pose.holding = look.holding
            drawPiboPixel(frame, Double(cx), Double(ground), pose)
        }
        if activity == .sleeping { drawPixelZzz(frame, cx + 14, 25, reduceMotion ? 0 : time) }
        else if activity == .dataUnknown { drawPixelQuestion(frame, cx + 15, 20, reduceMotion ? 0 : time) }
        else if look.thought {
            let y = 18 - (reduceMotion ? 0 : Int(time / 600) % 2)
            frame.fillRect(cx + 15, y, cx + 24, y + 6, .cloudShade)
            frame.fillRect(cx + 16, y + 1, cx + 23, y + 5, .cloudLight)
            frame.set(cx + 14, y + 7, .bodyLight)
            let phase = reduceMotion ? 3 : Int(time / 400) % 4
            for dot in 0..<phase { frame.set(cx + 17 + dot * 2, y + 3, .eye) }
        }
    }

    static func forestImage(look: Look, mood: PixelMood, width: Int, height: Int) -> CGImage? {
        PixelImageRenderer.render(logicalWidth: width, logicalHeight: height, palette: PixelPalette.rgb(mood)) { frame in
            let layout = pixelForestLayout(width, height)
            drawPixelForestStatic(frame, layout, 7919, mood)
            let body = PiboPixelLook()
            body.bodyStage = look.bodyStage
            body.leafStage = look.leafStage
            body.accessoryMask = look.accessoryMask
            body.leafGrowth = look.progress
            body.leafRipe = look.ripe
            let pose = piboPixelPose(activity(look.stateID), timeMs: 0, reduceMotion: true, look: body)
            pose.badge = PiboPixelBadge(rawValue: activity(look.stateID).rawValue + 1) ?? .dataUnknown
            drawPiboPixel(frame, Double(width / 2), Double(layout.groundY + 10), pose)
        }
    }

    static func activity(_ state: String) -> PiboPixelActivity {
        switch state {
        case "sleeping": .sleeping
        case "waking": .waking
        case "stable": .stable
        case "energetic": .energetic
        case "tired": .tired
        default: .dataUnknown
        }
    }
}

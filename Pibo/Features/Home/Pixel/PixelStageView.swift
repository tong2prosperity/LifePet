import Combine
import PiboCore
import SwiftUI

/// Draws the pixel home stage: the cached forest, its living layers, the places and
/// decorations, Pibo itself, then lamps and effects.
///
/// Ported from the `renderFrame` order in HarmonyPibo `pixel/PixelStage.ets`. This is the
/// presentation half only — the day director, hit regions, sounds and gestures land on top
/// of it, so a scene can be drawn without any of them.
@MainActor
final class PixelStageRenderer {
    /// Logical width the stage aims for; the integer scale follows from the view size.
    static let targetWidth = 136
    static let forestSeed = 2026
    private static let windMs: Double = 1200
    private static let windRainMs: Double = 500

    private var frame = PixelFrame(1, 1)
    private var staticFrames = [PixelFrame(1, 1), PixelFrame(1, 1)]
    private var staticDrawn = [false, false]
    private var staticKey = ""
    private var layout = PixelForestLayout()
    private var palette = PixelPalette.rgb(.day)
    private let imageRenderer = PixelImageRenderer()

    private(set) var scale: Int = 1

    /// Everything the picture depends on besides time. Change one and the next frame is a
    /// full redraw; the static forest is cached per mood and wind step.
    struct Look {
        var hour: Int
        var raining: Bool
        var scene: PiboCoreDayScene
        var activity: PiboPixelActivity
        var reduceMotion: Bool
        var bodyStage: Int
        var leafStage: Int
        var accessoryMask: Int
        var trickMask: Int
        var leafGrowth: Double
        var leafRipe: Bool
        var ownedDecor: [Int]
        var hammock: Bool
        var observer: Bool

        init(hour: Int = Calendar.current.component(.hour, from: Date()),
             raining: Bool = false,
             scene: PiboCoreDayScene = .clearing,
             activity: PiboPixelActivity = .stable,
             reduceMotion: Bool = false,
             bodyStage: Int = 2,
             leafStage: Int = 0,
             accessoryMask: Int = 0,
             trickMask: Int = 0,
             leafGrowth: Double = 1,
             leafRipe: Bool = false,
             ownedDecor: [Int] = [],
             hammock: Bool = false,
             observer: Bool = false) {
            self.hour = hour
            self.raining = raining
            self.scene = scene
            self.activity = activity
            self.reduceMotion = reduceMotion
            self.bodyStage = bodyStage
            self.leafStage = leafStage
            self.accessoryMask = accessoryMask
            self.trickMask = trickMask
            self.leafGrowth = leafGrowth
            self.leafRipe = leafRipe
            self.ownedDecor = ownedDecor
            self.hammock = hammock
            self.observer = observer
        }
    }

    func mood(for look: Look) -> PixelMood {
        pixelMoodFor(look.hour, look.raining)
    }

    /// Rebuilds the frame for a view of `size` in points at `scale`.
    func render(size: CGSize, scale: Int, elapsedMs: Double, look: Look) -> CGImage? {
        let pixelWidth = max(1, Int(size.width) / max(1, scale))
        let pixelHeight = max(1, Int(size.height) / max(1, scale))
        if frame.width != pixelWidth || frame.height != pixelHeight {
            frame = PixelFrame(pixelWidth, pixelHeight)
            staticFrames = [PixelFrame(pixelWidth, pixelHeight), PixelFrame(pixelWidth, pixelHeight)]
            staticDrawn = [false, false]
            staticKey = ""
            layout = pixelForestLayout(pixelWidth, pixelHeight)
        }
        self.scale = scale

        let mood = mood(for: look)
        let season = PiboCoreDayRules.season(month: Calendar.current.component(.month, from: Date()))
        let wind = look.reduceMotion ? 0
            : Int(elapsedMs / (look.raining ? Self.windRainMs : Self.windMs)) % 2
        var world = PixelWorldLook(scene: look.scene, season: season, snow: false, wind: wind)
        world.wind = wind

        let key = "\(mood.rawValue):\(world.key())"
        if key != staticKey {
            staticDrawn = [false, false]
            palette = PixelPalette.rgb(mood)
            staticKey = key
        }
        if !staticDrawn[wind] {
            drawPixelForestStatic(staticFrames[wind], layout, Self.forestSeed, mood, world)
            staticDrawn[wind] = true
        }

        let elapsed = look.reduceMotion ? 0 : elapsedMs
        frame.copyFrom(staticFrames[wind])
        drawPixelForestLife(frame, layout, Self.forestSeed, mood, look.raining, elapsed, true)

        var placeLook = PixelPlaceLook(season: season, snow: false, timeMs: elapsed, wind: wind)
        placeLook.basketFull = false
        var decor = PixelDecorScene()
        decor.owned = look.ownedDecor
        decor.hammock = look.hammock
        decor.observer = look.observer
        decor.timeMs = elapsed
        decor.mood = mood
        decor.dayCount = 1
        decor.windmillSpeed = 0

        let feetY = layout.groundY
        drawPixelPlaces(frame, layout, look.scene, placeLook, feetY, false)
        if look.raining { drawPixelPuddles(frame, layout, look.scene, elapsed) }
        drawPixelDecorBack(frame, layout, decor, feetY)

        let pose = piboPixelPose(look.activity, timeMs: elapsed, look: pixelLook(look))
        pose.badge = piboPixelBadgeFor(look.activity.rawValue)
        drawPiboPixel(frame, Double(layout.width) / 2, Double(feetY), pose)

        drawPixelPlaces(frame, layout, look.scene, placeLook, feetY, true)
        drawPixelDecorFront(frame, layout, decor, feetY)

        var lights: [PixelLightSource] = []
        for light in pixelDecorLights(layout, decor) where light.count >= 3 {
            lights.append(pixelLightSource(light[0], light[1], light[2]))
        }
        if !lights.isEmpty, mood == .night || mood == .dusk {
            applyPixelLight(frame, lights)
        }

        return imageRenderer.image(for: frame, palette: palette)
    }

    private func pixelLook(_ look: Look) -> PiboPixelLook {
        let value = PiboPixelLook()
        value.bodyStage = look.bodyStage
        value.leafStage = look.leafStage
        value.accessoryMask = look.accessoryMask
        value.trickMask = look.trickMask
        value.leafGrowth = look.leafGrowth
        value.leafRipe = look.leafRipe
        return value
    }
}

/// Hosts the pixel stage, ticking it at the approved 20 fps and scaling by a whole number.
struct PixelStageView: View {
    var look: PixelStageRenderer.Look
    var debugHour: Int?

    @State private var image: CGImage?
    @State private var scale: Int = 3
    @State private var start = Date()

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
            .onAppear { redraw(size: proxy.size) }
            .onChange(of: proxy.size) { _, size in redraw(size: size) }
        }
        .ignoresSafeArea()
        .onReceive(timer) { _ in
            let elapsed = Date().timeIntervalSince(start) * 1000
            var current = look
            if let debugHour { current.hour = debugHour }
            image = renderer.render(size: lastSize, scale: scale, elapsedMs: elapsed, look: current)
        }
    }

    @State private var lastSize: CGSize = .zero

    private func redraw(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        lastSize = size
        scale = max(1, Int(size.width) / PixelStageRenderer.targetWidth)
        var current = look
        if let debugHour { current.hour = debugHour }
        image = renderer.render(size: size, scale: scale, elapsedMs: 0, look: current)
    }
}

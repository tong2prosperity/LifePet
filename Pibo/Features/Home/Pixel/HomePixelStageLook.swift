import Foundation
import PiboCore

// Everything Home knows, arranged the way the pixel stage wants it. The stage itself
// knows nothing about stores: `PixelStageRenderer.Look` is a plain value, and this file is
// the one place that reads the environment into it.
//
// Mirrors the props HarmonyOS passes to `PixelStage` in
// `components/home/HomeForestScene.ets`.

/// One frame's worth of Home facts, already resolved to values the renderer can compare.
@MainActor
struct HomePixelStageInput {
    /// −1 asks the renderer to read the clock.
    var hour: Int = -1
    var raining = false
    var scene: PiboCoreDayScene = .clearing
    var season: Int = 0
    var snow = false
    var reduceMotion = false
    var animationStateID = ""
    var achievementResponse: PiboAnimationAchievementKind?
    /// Pibo stays where it is while it talks, answers, or looks at a meal.
    var holdPibo = false
    var wishPromptActive = false

    var growth: GrowthStore
    var cues: PiboCoreGrowthBodyCues?
    var mimic = 0
    /// How far the `bo` on Pibo's leaf has grown (0…1) and whether one is ripe.
    var boProgress: Double = 0
    var leafRipe = false

    var decor: DecorStore
    var hammock = false
    var observer = false
    var grass = false
    var cake = false
    var dayCount = 1

    var day: HomeDayController?
    var days: PiboDayStore
    var timeline: PiboTimelineStore? = nil
    var ambient: UInt32 = 0
    var foodLook = 0
    var foodOnRight = false

    var look: PixelStageRenderer.Look {
        var look = PixelStageRenderer.Look()
        look.hour = hour
        look.raining = raining
        look.scene = scene
        look.season = season
        look.snow = snow
        look.reduceMotion = reduceMotion
        look.animationStateID = animationStateID
        look.achievementResponse = achievementResponse
        // PixelDayDirector owns all hiding, indoor and offstage presentation.
        // Do not project the retired companion clip's global body-hide flag here.
        look.holdPibo = holdPibo
        look.wishPromptActive = wishPromptActive

        // Growth (decision 057). Before Core's first answer the appearance is nil; the
        // renderer's defaults are the honest "not known yet" picture.
        if let appearance = growth.appearance {
            look.bodyStage = appearance.bodyStage
            look.leafStage = appearance.leafStage
            look.accessoryMask = Int(appearance.accessoryMask)
            look.trickMask = Int(appearance.trickMask)
        }
        look.leafGrowth = boProgress
        look.leafRipe = leafRipe
        look.sleepBand = cues?.sleepBand ?? -1
        look.flexing = cues?.flexing ?? false
        look.mimic = mimic

        // The forest around it.
        look.ownedDecor = decor.ownedIn(Int(scene.rawValue)).map { Int($0.rawValue) }
        look.hammock = hammock
        look.observer = observer
        look.grass = grass
        look.cake = cake
        look.flowers = cues?.flowers ?? 0
        look.footprints = cues?.footprintSegments ?? 0
        look.windmillSpeed = cues?.windmillSpeed ?? 0
        look.moonLamp = cues?.moonLamp ?? 0
        let stoneBeats = timeline?.beatsToldIn("stones") ?? 0
        look.stones = PiboCoreDecor.stoneCount(stoneBeatsTold: stoneBeats)
        let beetleBeats = timeline?.beatsToldIn("beetle") ?? 0
        let trace = PiboCoreDecor.beetleTrace(beetleBeatsTold: beetleBeats, localHour: max(0, hour))
        look.beetles = trace.count
        look.beetleSpot = trace.spotted
        look.beetleOnLeaf = trace.onLeaf
        look.firstMarkers = Int(PiboCoreDecor.firstMarkers(recordedMask: timeline?.recordedMask ?? 0))
        look.dayCount = dayCount

        // The story's things (decisions 059/062), as the day controller last read them.
        look.podFixed = day?.storyPodFixed ?? false
        look.sproutStage = day?.storySprout ?? 0
        look.mailbox = day?.storyMailbox ?? 0
        look.planks = day?.storyPlanks ?? 0
        look.oldPod = day?.storyOldPod ?? 0
        look.farLight = day?.storyFarLight ?? false
        look.ambientMask = PiboCoreAmbient(rawValue: ambient)
        look.basketFull = !days.finds.isEmpty

        // The meal mat and the shelf's display spot (decision 065).
        look.mealStickers = day?.mealStickers ?? []
        look.mealFresh = day?.mealFresh ?? false
        look.displayedFind = days.displayedIn(Int(scene.rawValue))
        look.foodLook = foodLook
        look.foodOnRight = foodOnRight
        return look
    }
}

import PiboCore
import SwiftUI

// The stage's tap targets (decision 058/065). HarmonyOS lays transparent `Rect`s over the
// canvas and lets ArkUI route the taps; SwiftUI gets one gesture on the whole stage, so the
// same boxes are computed here and the topmost one under the finger wins.
//
// Ported from HarmonyPibo `pixel/PixelStage.ets` (`updateHitRegions` and the handlers).

/// What a tap landed on.
enum PixelStageTarget: Equatable {
    /// Pibo itself: a double tap pats it, a single tap glances at the badge.
    case actor
    /// The leaf above Pibo's head: a pull harvests a ripe bo.
    case leaf
    /// A Core place, or a `PixelHotspot` value (basket, decoys, meal stickers, story things).
    case place(Int)
    /// A decoration or an ornament, by `PixelDecorID` raw value.
    case decor(Int)
    /// The shooting star.
    case star
}

struct PixelStageHit: Equatable {
    var target: PixelStageTarget
    var x: Int
    var y: Int
    var w: Int
    var h: Int

    func contains(_ px: Double, _ py: Double) -> Bool {
        px >= Double(x) && px < Double(x + w) && py >= Double(y) && py < Double(y + h)
    }

    var center: (x: Int, y: Int) { (x + w / 2, y + h / 2) }
}

extension PixelStageRenderer {
    /// Pibo's body and the leaf above it (ArkTS `updateActorHits`). The leaf sits directly
    /// above the body so a pull never steals a pat.
    var actorHits: (body: PixelStageHit, leaf: PixelStageHit) {
        let size = piboPixelBodySize(currentLook.bodyStage)
        let configured = director.isConfigured
        let x = configured ? actor.x : Double(currentLayout.width) / 2
        let feet = configured ? actor.y - Double(actor.lift) : Double(currentLayout.groundY)
        let bodyTop = feet - 2 - Double(size[1] * 2)
        let pad = 6.0
        let body = PixelStageHit(
            target: .actor,
            x: Int((x - Double(size[0]) - pad).rounded(.down)),
            y: Int((bodyTop - 2).rounded(.down)),
            w: Int(((Double(size[0]) + pad) * 2).rounded(.down)),
            h: Int((Double(size[1] * 2 + 4) + pad).rounded(.down))
        )
        let leaf = PixelStageHit(target: .leaf,
                                 x: Int((x - 10).rounded(.down)),
                                 y: Int((bodyTop - 22).rounded(.down)),
                                 w: 20, h: 20)
        return (body, leaf)
    }

    /// Every tappable box, back to front: the last one under the finger wins.
    func stageHits() -> [PixelStageHit] {
        let layout = currentLayout
        let look = currentLook
        var hits: [PixelStageHit] = []

        // The star is a full-width band up to where it is, so it is easy to catch.
        if starVisible {
            hits.append(PixelStageHit(target: .star, x: 0, y: 0,
                                      w: layout.width, h: max(1, starHead.y)))
        }

        for box in pixelDecorHitBoxes(layout, currentDecorScene) {
            hits.append(PixelStageHit(target: .decor(box.id.rawValue),
                                      x: box.x, y: box.y, w: box.w, h: box.h))
        }

        for box in pixelPlaceBoxes(layout, look.scene) {
            hits.append(PixelStageHit(target: .place(box.place),
                                      x: box.x - 2, y: box.y - 2, w: box.w + 4, h: box.h + 4))
        }

        if look.displayedFind >= 0 {
            let spot = pixelFindSpotBox(layout, look.scene)
            hits.append(PixelStageHit(target: .place(spot.place),
                                      x: spot.x, y: spot.y, w: spot.w, h: spot.h))
        }

        if look.scene == .clearing {
            // The mat, then each sticker on top of it (later hits sit above earlier ones).
            let mat = pixelMealMatBox(layout)
            hits.append(PixelStageHit(target: .place(mat.place),
                                      x: mat.x - 2, y: mat.y + 6, w: mat.w + 4, h: mat.h - 4))
            for box in pixelMealStickerBoxes(layout, look.mealStickers.count) {
                hits.append(PixelStageHit(target: .place(box.place),
                                          x: box.x - 1, y: box.y - 2, w: box.w + 2, h: box.h + 2))
            }
        }

        // A disguised Pibo's look-alikes can be tapped (the real one is Pibo's own box).
        if director.disguise > 0 {
            for (index, spot) in director.decoys.enumerated() where spot.count >= 2 {
                hits.append(PixelStageHit(target: .place(PixelHotspot.decoy.rawValue + index),
                                          x: spot[0] - 9, y: spot[1] - 16, w: 18, h: 18))
            }
        }

        if look.scene == .clearing {
            var season = PixelSeasonLook()
            season.podFixed = look.podFixed
            season.sprout = look.sproutStage
            season.mailbox = look.mailbox
            season.snow = look.snow
            for box in pixelSeasonBoxes(layout, season) {
                hits.append(PixelStageHit(target: .place(box.id),
                                          x: box.x - 3, y: box.y - 4, w: box.w + 6, h: box.h + 6))
            }
        }

        if look.scene == .creek {
            // The old pod is tappable; the bridge is ground to walk on, not a button.
            var two = PixelSeasonTwoLook()
            two.planks = look.planks
            two.oldPodFound = look.oldPod >= 1
            two.oldPodLit = look.oldPod >= 2
            two.farLight = look.farLight
            two.snow = look.snow
            for box in pixelSeasonTwoBoxes(layout, two) where box.id != PIXEL_SEASON_BRIDGE {
                hits.append(PixelStageHit(target: .place(box.id),
                                          x: box.x - 3, y: box.y - 4, w: box.w + 6, h: box.h + 6))
            }
        }

        // Pibo last: it stands in front of everything it can stand in front of.
        if look.piboVisible {
            let actorHits = actorHits
            hits.append(actorHits.body)
            hits.append(actorHits.leaf)
        }
        return hits
    }

    /// The topmost box under a point in logical pixels.
    func hit(at px: Double, _ py: Double) -> PixelStageHit? {
        stageHits().last { $0.contains(px, py) }
    }

    /// A tap on the leaf's column: the pull gesture only arms there.
    func leafHit(at px: Double, _ py: Double) -> Bool {
        actorHits.leaf.contains(px, py)
    }
}

// MARK: - Labels

/// The few look values the labels need.
struct PixelStageLabelLook {
    var leafRipe = false
    var mailbox = 0
    var oldPod = 0
}

/// What a tap target is called, for VoiceOver (ArkTS `placeLabel` / `decorLabel`).
func pixelStageLabel(_ target: PixelStageTarget, _ look: PixelStageLabelLook) -> String {
    switch target {
    case .actor:
        return AppLocalization.text("Pibo")
    case .leaf:
        return look.leafRipe ? AppLocalization.text("成熟的 bo，可以收取")
            : AppLocalization.text("头顶的 bo")
    case .star:
        return AppLocalization.text("流星")
    case .decor(let id):
        return AppLocalization.text(pixelDecorLabel(id))
    case .place(let place):
        if place == PIXEL_SEASON_MAILBOX && look.mailbox >= 2 {
            return AppLocalization.text("信箱，有一封信")
        }
        if place == PIXEL_SEASON_POD && look.oldPod >= 1 {
            return AppLocalization.text("Pibo 的小舱，打开旧笔记")
        }
        if place >= PixelHotspot.mealSticker.rawValue && place < PixelHotspot.decoy.rawValue {
            return AppLocalization.text("食物贴纸，打开这一餐")
        }
        if place >= PixelHotspot.decoy.rawValue && place < PixelHotspot.decoy.rawValue + 8 {
            return AppLocalization.text("这个东西")
        }
        return AppLocalization.text(pixelPlaceLabel(place))
    }
}

private let PIXEL_PLACE_LABELS: [Int: String] = [
    Int(PiboCoreDayPlace.mossNest.rawValue): "苔藓窝",
    Int(PiboCoreDayPlace.bigTree.rawValue): "大树",
    Int(PiboCoreDayPlace.tallGrass.rawValue): "草丛",
    Int(PiboCoreDayPlace.trailSign.rawValue): "路牌，打开地图",
    Int(PiboCoreDayPlace.creekBank.rawValue): "小溪",
    Int(PiboCoreDayPlace.steppingStones.rawValue): "跳石",
    Int(PiboCoreDayPlace.fallenLog.rawValue): "倒下的木头",
    Int(PiboCoreDayPlace.reeds.rawValue): "芦苇",
    Int(PiboCoreDayPlace.flowerField.rawValue): "花田",
    Int(PiboCoreDayPlace.loneTree.rawValue): "山坡上的树",
    Int(PiboCoreDayPlace.bigRock.rawValue): "大石头",
    Int(PiboCoreDayPlace.hilltop.rawValue): "山顶",
    PixelHotspot.basket.rawValue: "Pibo 的收藏篮",
    PIXEL_SEASON_POD: "Pibo 的小舱",
    PIXEL_SEASON_SPROUT: "Pibo 种下的苗",
    PIXEL_SEASON_MAILBOX: "信箱",
    PIXEL_SEASON_OLD_POD: "对岸的旧舱",
    Int(PiboCoreDayPlace.mealMat.rawValue): "野餐垫",
    Int(PiboCoreDayPlace.findSpot.rawValue): "摆出来的收藏品",
]

private func pixelPlaceLabel(_ place: Int) -> String {
    PIXEL_PLACE_LABELS[place] ?? ""
}

private let PIXEL_DECOR_LABELS: [String] = [
    "蘑菇凳", "名牌", "石头堆", "花圃", "风车", "月亮灯", "小池塘", "秋千", "篝火", "帐篷",
    "吊床", "状态观测仪", "草丛", "纪念日蛋糕", "第一次拍拍的记号", "第一枚 bo 的记号",
    "第一晚吊床的记号", "第一顿饭的记号", "小船", "风筝", "望远镜",
]

private func pixelDecorLabel(_ id: Int) -> String {
    PIXEL_DECOR_LABELS.indices.contains(id) ? PIXEL_DECOR_LABELS[id] : ""
}

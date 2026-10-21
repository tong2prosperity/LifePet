import Foundation

// One-shot moments Home asks the pixel stage to play. Like `PiboStageCommandController`,
// these stay imperative so a celebration never becomes a reactive Home prop.
//
// Ported from HarmonyPibo `pixel/PixelStageEffects.ets`.

enum PixelStageMoment: Int {
    case patHearts = 0
    case xpPop = 1
    case awayOrbs = 2
    case levelUp = 3
    case wishStamp = 4
    case heartUp = 5
    case boCollected = 6
    case dizzy = 7
    case starWish = 8
    case bloom = 9
    case celebrate = 10
    case sourcePop = 11
}

/// Which health source an orb flies from: 0 sleep, 1 steps, 2 activity.
protocol PixelStageMomentTarget: AnyObject {
    func playMoment(_ moment: PixelStageMoment, value: Double, source: Int)
    /// The last rendered frame around Pibo, for the daily polaroid.
    func snapshot() -> PixelSnapshot?
}

/// Logical-resolution RGBA pixels, row-major, no upscale.
struct PixelSnapshot {
    var width = 0
    var height = 0
    var rgba: [UInt8] = []
}

final class PixelStageEffects {
    private weak var target: PixelStageMomentTarget?
    private var queued: [(moment: PixelStageMoment, value: Double, source: Int)] = []

    func attach(_ target: PixelStageMomentTarget) {
        self.target = target
        let queued = self.queued
        self.queued = []
        for item in queued {
            target.playMoment(item.moment, value: item.value, source: item.source)
        }
    }

    func detach(_ target: PixelStageMomentTarget) {
        if self.target === target { self.target = nil }
    }

    /// Nil while no stage is on screen.
    func snapshot() -> PixelSnapshot? {
        target?.snapshot()
    }

    func play(_ moment: PixelStageMoment, value: Double = 0, source: Int = -1) {
        if let target {
            target.playMoment(moment, value: value, source: source)
            return
        }
        // Keep only a few so a long background stint does not replay a backlog.
        queued.append((moment, value, source))
        if queued.count > 4 { queued.removeFirst() }
    }
}

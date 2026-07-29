import Observation
import SpriteKit
import SwiftUI

/// Imperative boundary for one-shot stage effects. Commands do not participate
/// in SwiftUI state diffing, so triggering an effect cannot invalidate Home's
/// SpriteKit subtree.
@MainActor
@Observable
final class PiboStageCommandController {
    @ObservationIgnored private weak var scene: PiboStageScene?

    func attach(scene: PiboStageScene) {
        guard self.scene !== scene else { return }
        self.scene = scene
    }

    func detach(scene: PiboStageScene) {
        guard self.scene === scene else { return }
        self.scene = nil
    }

    func playEnergyGain() {
        scene?.playEnergyGain()
    }

    func playSproutGrowth(from start: Double, to target: Double) {
        scene?.playSproutGrowth(from: start, to: target)
    }

    func playPluck(color: Color) {
        scene?.playPluck(color: SKColor(color))
    }

    func playTurnAway() {
        scene?.playTurnAway()
    }

    /// 运动完成 → 秀肌肉 → 娇羞 → 回常驻态。是否该演由 Core 判（深眠里被叫醒
    /// 秀肌肉会读成 bug），这里只负责播。
    func playWorkoutCelebration() {
        scene?.playWorkoutCelebration()
    }

    func playSproutCloseup(
        growthFrom start: Double,
        growthTo target: Double,
        onPhase: @escaping (SproutCloseupPhase) -> Void
    ) {
        scene?.playSproutCloseup(growthFrom: start, growthTo: target, onPhase: onPhase)
    }
}

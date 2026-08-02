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
    @ObservationIgnored private var pendingBoProgress: BoProgressMilestone?

    /// Reserved capability seams. They remain nil in this release, so the bo
    /// progress effect performs no audio or haptic system calls.
    @ObservationIgnored var playBoProgressSound: ((BoProgressMilestone) -> Void)?
    @ObservationIgnored var playBoProgressHaptic: ((BoProgressMilestone) -> Void)?

    func attach(scene: PiboStageScene) {
        guard self.scene !== scene else { return }
        self.scene = scene
        if let pendingBoProgress {
            self.pendingBoProgress = nil
            _ = scene.playBoProgressFeedback(pendingBoProgress)
        }
    }

    func detach(scene: PiboStageScene) {
        guard self.scene === scene else { return }
        self.scene = nil
    }

    func playEnergyGain() {
        scene?.playEnergyGain()
    }

    /// Returns true once the request is accepted by the stage boundary. If the
    /// SpriteKit scene is temporarily detached, keep only the latest milestone
    /// until Home attaches it again.
    @discardableResult
    func playBoProgressFeedback(_ milestone: BoProgressMilestone) -> Bool {
        guard let scene else {
            pendingBoProgress = max(pendingBoProgress ?? milestone, milestone)
            return true
        }
        return scene.playBoProgressFeedback(milestone)
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
    func playAchievement(_ stateID: String) {
        scene?.playAchievement(stateID)
    }

    func playWorkoutCelebration() {
        playAchievement("pigu")
    }

    func transitionAnimation(
        to stateID: String,
        intent: PiboCoreAnimationAdapter.TransitionIntent
    ) {
        scene?.transitionAnimation(to: stateID, intent: intent)
    }

    func playSproutCloseup(
        growthFrom start: Double,
        growthTo target: Double,
        onPhase: @escaping (SproutCloseupPhase) -> Void
    ) {
        scene?.playSproutCloseup(growthFrom: start, growthTo: target, onPhase: onPhase)
    }
}

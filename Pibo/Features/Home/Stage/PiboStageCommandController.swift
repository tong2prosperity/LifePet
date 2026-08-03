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

    func transitionAnimation(
        to stateID: String,
        intent: PiboCoreAnimationAdapter.TransitionIntent
    ) {
        scene?.transitionAnimation(to: stateID, intent: intent)
    }

    #if DEBUG
    /// 走查用：重播当前状态的登场与连招。
    func replayAnimationIntro() {
        scene?.replayAnimationIntro()
    }

    /// 走查用：成果态改演完整连招，用来对比首页的保持呼吸。
    func setPlaysAchievementCombo(_ enabled: Bool) {
        scene?.setPlaysAchievementCombo(enabled)
    }
    #endif

    func playSproutCloseup(
        growthFrom start: Double,
        growthTo target: Double,
        onPhase: @escaping (SproutCloseupPhase) -> Void
    ) {
        scene?.playSproutCloseup(growthFrom: start, growthTo: target, onPhase: onPhase)
    }
}

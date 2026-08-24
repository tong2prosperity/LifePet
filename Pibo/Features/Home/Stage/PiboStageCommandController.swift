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
    @ObservationIgnored private var pendingBoProgress: BoProgressPresentation?
    @ObservationIgnored private var ornamentConstruction: (enabled: Bool, selected: PiboOrnament.ID?) = (false, nil)
    @ObservationIgnored private var ornamentPreview: PiboOrnament.ID?
    @ObservationIgnored private var pendingOrnamentReveal: PiboOrnament.ID?

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
        scene.setOrnamentConstructionMode(
            enabled: ornamentConstruction.enabled,
            selected: ornamentConstruction.selected
        )
        scene.setOrnamentPlacementPreview(ornamentPreview)
        if let pendingOrnamentReveal {
            scene.prepareOrnamentReveal(pendingOrnamentReveal)
        }
    }

    func detach(scene: PiboStageScene) {
        guard self.scene === scene else { return }
        self.scene = nil
    }

    func playEnergyGain() {
        scene?.playEnergyGain()
    }

    func playSproutTouch() {
        scene?.playSproutTouch()
    }

    /// Returns true once the request is accepted by the stage boundary. If the
    /// SpriteKit scene is temporarily detached, keep only the latest presentation
    /// until Home attaches it again.
    @discardableResult
    func playBoProgressFeedback(_ presentation: BoProgressPresentation) -> Bool {
        guard let scene else {
            if pendingBoProgress.map({ presentation.milestone >= $0.milestone }) ?? true {
                pendingBoProgress = presentation
            }
            return true
        }
        return scene.playBoProgressFeedback(presentation)
    }

    func playSproutGrowth(from start: Double, to target: Double) {
        scene?.playSproutGrowth(from: start, to: target)
    }

    func playPluck() {
        scene?.playPluck()
    }

    func playTurnAway() {
        scene?.playTurnAway()
    }

    func playContextualAction(_ action: PiboCoreAnimationAdapter.ContextualAction) {
        scene?.playContextualAction(action)
    }

    func cancelContextualAction() {
        scene?.cancelContextualAction()
    }

    func transitionAnimation(
        to stateID: String,
        intent: PiboCoreAnimationAdapter.TransitionIntent
    ) {
        scene?.transitionAnimation(to: stateID, intent: intent)
    }

    func performAnimationEvent(_ stateID: String) {
        scene?.performAnimationEvent(stateID)
    }

    func setOrnamentConstructionMode(enabled: Bool, selected: PiboOrnament.ID?) {
        ornamentConstruction = (enabled, selected)
        scene?.setOrnamentConstructionMode(enabled: enabled, selected: selected)
    }

    func setOrnamentPlacementPreview(_ id: PiboOrnament.ID?) {
        ornamentPreview = id
        scene?.setOrnamentPlacementPreview(id)
    }

    func prepareOrnamentReveal(_ id: PiboOrnament.ID) {
        pendingOrnamentReveal = id
        scene?.prepareOrnamentReveal(id)
    }

    func ornamentTargetFrame(_ id: PiboOrnament.ID) -> CGRect? {
        // Window/global coordinates, matching SwiftUI's `.global` space.
        scene?.ornamentTargetFrame(id)
    }

    func completeOrnamentReveal(_ id: PiboOrnament.ID) {
        pendingOrnamentReveal = nil
        scene?.completeOrnamentReveal(id)
    }

    func cancelOrnamentPresentation() {
        ornamentConstruction = (false, nil)
        ornamentPreview = nil
        pendingOrnamentReveal = nil
        scene?.cancelOrnamentPresentation()
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

import Foundation
import Combine
import SwiftUI
import SpriteKit
import UIKit

/// Owns the heavyweight SpriteKit scene behind SwiftUI's lazy `@StateObject`
/// storage. A reference value placed directly in an `@State` initial value is
/// still constructed whenever a transient `PiboStageView` value is created,
/// even though SwiftUI keeps the previously installed state. That used to
/// build and immediately discard a full forest scene during pat reactions.
@MainActor
private final class PiboStageSceneOwner: ObservableObject {
    let scene = PiboStageScene(size: CGSize(width: 390, height: 760))
}

/// SwiftUI bridge to the SpriteKit `PiboStageScene`. Holds one scene for the
/// view's lifetime and forwards theme / state / growth changes. One-shot
/// effects cross the dedicated command boundary instead of SwiftUI state.
struct PiboStageView: View, Equatable {
    let theme: PiboTheme
    let state: PiboActivityState
    var animationStateID: String? = nil
    let commandController: PiboStageCommandController
    /// 魔丸 head growth (「?」卷芽 ⇄ 发芽带叶) — drives which head sprite shows.
    var growth: PiboGrowthStage = .sprouted
    /// Continuous, persisted extension of the sprouted six-bone mesh.
    var sproutGrowthProgress: Double = 1
    /// Theme-neutral local time and weather input.
    var environment: PiboStageEnvironment = .daylight
    /// 用 `bo` 换来、已经解锁的物件。空集 = 只有原始森林。
    var unlockedOrnaments: Set<PiboOrnament.ID> = []
    /// 物件身上被亲手点亮的灯。没有自动夜光 —— 空 = 一盏不亮。
    var litOrnamentLights: [PiboOrnament.ID: Set<Int>] = [:]
    /// Fine-grained renderer controls. Release Home keeps the standard values;
    /// DEBUG exposes them in a collapsible overlay.
    var tuning: StageRenderTuning = .standard
    var onPat: () -> Void = {}
    /// Fired when the head 毛 is dragged past the pull threshold (the 拔毛 gesture).
    var onHairPulled: () -> Void = {}
    /// Fired when a tap lights one of an ornament's lamps (铃兰灯的一盏铃铛).
    var onOrnamentLightTapped: (PiboOrnament.ID, Int) -> Void = { _, _ in }
    /// Suspend the stage when an opaque feature covers Home. The `SpriteView`
    /// itself is detached below; `isPaused` alone does not reliably stop
    /// `SKView`'s display-link/render callbacks while a full-screen cover keeps
    /// the underlying SwiftUI hierarchy alive.
    var isPaused: Bool = false

    // `StateObject` defers the heavyweight scene allocation until SwiftUI
    // installs this view's identity, instead of evaluating it for every
    // transient value produced by `HomeView.body`.
    @StateObject private var sceneOwner = PiboStageSceneOwner()
    @State private var renderController = PiboStageRenderController()

    private var scene: PiboStageScene { sceneOwner.scene }

    private var preferredFramesPerSecond: Int {
        renderController.preferredFramesPerSecond(
            isPaused: isPaused,
            displayMaximum: UIScreen.main.maximumFramesPerSecond
        )
    }

    var body: some View {
        // Drive the scene size from SwiftUI: SpriteView does not honor
        // `.resizeFill` here, so without this the scene stays at its initial size
        // and gets non-uniformly stretched to fill the view (Pibo looks elongated).
        GeometryReader { geo in
            Group {
                if isPaused {
                    // Removing SpriteView from the hierarchy is the reliable
                    // render-loop boundary. `scene` remains retained by @State,
                    // so returning Home does not rebuild its node tree.
                    Color.clear
                } else {
                    // The scene always draws a full-size sky/background, so an
                    // alpha-backed SKView only adds blending and bandwidth.
                    PiboStageRenderView(
                        scene: scene,
                        preferredFramesPerSecond: preferredFramesPerSecond
                    )
                }
            }
            .onAppear {
                configureScene(size: geo.size)
                scene.isPaused = isPaused
            }
            .onChange(of: isPaused) { _, paused in
                // Pause actions immediately as the SKView is detached, then
                // resume the same scene before a new SpriteView presents it.
                scene.isPaused = paused
            }
            .onChange(of: geo.size) { _, newSize in
                if newSize.width > 1, newSize.height > 1 { scene.size = newSize }
            }
            .onChange(of: theme.id) { _, _ in applySceneState() }
            .onChange(of: state) { _, _ in applySceneState() }
            .onChange(of: animationStateID) { _, _ in applySceneState() }
            .onChange(of: growth) { _, _ in applySceneState() }
            .onChange(of: sproutGrowthProgress) { _, value in
                scene.setSproutGrowthProgress(value)
            }
            .onChange(of: environment) { _, value in scene.setEnvironment(value) }
            .onChange(of: unlockedOrnaments) { _, value in scene.setUnlockedOrnaments(value) }
            .onChange(of: litOrnamentLights) { _, value in scene.setLitOrnamentLights(value) }
            .onChange(of: tuning) { _, value in scene.setTuning(value) }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                renderController.refreshLowPowerMode()
                scene.setLowPowerMode(renderController.lowPowerModeEnabled)
            }
            .onDisappear {
                commandController.detach(scene: scene)
            }
        }
    }

    private func configureScene(size: CGSize) {
        if size.width > 1, size.height > 1 { scene.size = size }
        commandController.attach(scene: scene)
        renderController.refreshLowPowerMode()
        scene.setLowPowerMode(renderController.lowPowerModeEnabled)
        scene.onPat = onPat
        scene.onHairPulled = onHairPulled
        scene.onOrnamentLightTapped = onOrnamentLightTapped
        scene.onDirectManipulationChanged = { [weak renderController] active in
            renderController?.setDirectManipulation(
                active: active,
                displayMaximum: UIScreen.main.maximumFramesPerSecond
            )
        }
        applySceneState()
        scene.setSproutGrowthProgress(sproutGrowthProgress)
        scene.setEnvironment(environment)
        scene.setUnlockedOrnaments(unlockedOrnaments)
        scene.setLitOrnamentLights(litOrnamentLights)
        scene.setTuning(tuning)
    }

    private func applySceneState() {
        scene.apply(
            theme: theme,
            state: state,
            animationStateID: animationStateID,
            growth: growth
        )
    }

    static func == (lhs: PiboStageView, rhs: PiboStageView) -> Bool {
        lhs.theme == rhs.theme
            && lhs.state == rhs.state
            && lhs.animationStateID == rhs.animationStateID
            && lhs.growth == rhs.growth
            && lhs.sproutGrowthProgress == rhs.sproutGrowthProgress
            && lhs.environment == rhs.environment
            && lhs.unlockedOrnaments == rhs.unlockedOrnaments
            && lhs.litOrnamentLights == rhs.litOrnamentLights
            && lhs.tuning == rhs.tuning
            && lhs.isPaused == rhs.isPaused
            && lhs.commandController === rhs.commandController
    }
}

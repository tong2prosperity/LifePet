import Foundation
import Combine
import PiboCore
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
    var boGrowthStage: PiboCoreBoGrowthStage = .dormant
    /// Continuous, persisted extension of the sprouted six-bone mesh.
    var sproutGrowthProgress: Double = 1
    /// Theme-neutral local time and weather input.
    var environment: PiboStageEnvironment = .daylight
    /// 森林中的全部共同物件。未拥有的物件由渲染器直接显示为灰态。
    var presentedOrnaments: Set<PiboOrnament.ID> = []
    /// 用 `bo` 换来、已经解锁的物件。空集 = 全部共同物件保持灰态。
    var unlockedOrnaments: Set<PiboOrnament.ID> = []
    /// 物件身上被亲手点亮的灯。没有自动夜光 —— 空 = 一盏不亮。
    var litOrnamentLights: [PiboOrnament.ID: Set<Int>] = [:]
    /// Fine-grained renderer controls. Release Home keeps the standard values;
    /// DEBUG exposes them in a collapsible overlay.
    var tuning: StageRenderTuning = .standard
    var onPat: () -> Void = {}
    /// Fired when the head sprout is released after a tap or gentle drag.
    var onSproutTouched: () -> Void = {}
    /// Fired when a tap lights one of an ornament's lamps (铃兰灯的一盏铃铛).
    var onOrnamentLightTapped: (PiboOrnament.ID, Int) -> Void = { _, _ in }
    /// Fired when a tappable common item in the forest is selected.
    var onOrnamentTapped: (PiboOrnament.ID) -> Void = { _ in }
    /// Suspend the stage when an opaque feature covers Home. The `SpriteView`
    /// itself is detached below; `isPaused` alone does not reliably stop
    /// `SKView`'s display-link/render callbacks while a full-screen cover keeps
    /// the underlying SwiftUI hierarchy alive.
    var isPaused: Bool = false
    /// Moss sheets intentionally leave the forest mounted for spatial
    /// continuity. Their background does not need a 60Hz render loop, so keep
    /// the scene alive at the lower ambient cadence.
    var isObscured: Bool = false

    // `StateObject` defers the heavyweight scene allocation until SwiftUI
    // installs this view's identity, instead of evaluating it for every
    // transient value produced by `HomeView.body`.
    @StateObject private var sceneOwner = PiboStageSceneOwner()
    @State private var renderController = PiboStageRenderController()

    private var scene: PiboStageScene { sceneOwner.scene }

    private var preferredFramesPerSecond: Int {
        renderController.preferredFramesPerSecond(
            isPaused: isPaused,
            isObscured: isObscured,
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
            .onChange(of: presentedOrnaments) { _, _ in applyOrnaments() }
            .onChange(of: unlockedOrnaments) { _, _ in applyOrnaments() }
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
        .accessibilityRepresentation {
            commonItemAccessibilityControls
        }
    }

    /// SpriteKit nodes do not become reliable VoiceOver controls through the
    /// SwiftUI bridge. Mirror Pibo, every grey common object, and owned items.
    @ViewBuilder
    private var commonItemAccessibilityControls: some View {
        VStack {
            Button(PiboCoreAnimationAdapter.accessibilityLabel(for: state)) {
                onPat()
            }
            .accessibilityValue(boGrowthAccessibilityValue)
            Button(AppLocalization.text("查看 bo")) {
                onSproutTouched()
            }
            .accessibilityValue(boGrowthAccessibilityValue)
            .accessibilityHint(AppLocalization.text("成熟后可投入共同物件"))
            ForEach(PiboOrnament.ordered.filter {
                presentedOrnaments.contains($0.id) && !unlockedOrnaments.contains($0.id)
            }) { ornament in
                Button(AppLocalization.format("%@，未唤醒", ornament.localizedName)) {
                    onOrnamentTapped(ornament.id)
                }
                .accessibilityHint(AppLocalization.text("查看功能和唤醒所需的 bo"))
            }
            if unlockedOrnaments.contains(.hammock) {
                Button(AppLocalization.text("打开睡眠回顾")) {
                    onOrnamentTapped(.hammock)
                }
            }
            if unlockedOrnaments.contains(.statusObserver) {
                Button(AppLocalization.text("打开恢复状态")) {
                    onOrnamentTapped(.statusObserver)
                }
            }
            if unlockedOrnaments.contains(.lantern),
               let lights = PiboOrnament.ornament(.lantern)?.placement?.lights {
                ForEach(lights.indices, id: \.self) { index in
                    Button("\(AppLocalization.text("魔法点灯")) \(index + 1)") {
                        onOrnamentLightTapped(.lantern, index)
                    }
                    .disabled(litOrnamentLights[.lantern]?.contains(index) == true)
                }
            }
        }
    }

    private func configureScene(size: CGSize) {
        if size.width > 1, size.height > 1 { scene.size = size }
        commandController.attach(scene: scene)
        renderController.refreshLowPowerMode()
        scene.setLowPowerMode(renderController.lowPowerModeEnabled)
        scene.onPat = onPat
        scene.onSproutTouched = onSproutTouched
        scene.onOrnamentLightTapped = onOrnamentLightTapped
        scene.onOrnamentTapped = onOrnamentTapped
        scene.onDirectManipulationChanged = { [weak renderController] active in
            renderController?.setDirectManipulation(
                active: active,
                displayMaximum: UIScreen.main.maximumFramesPerSecond
            )
        }
        applySceneState()
        scene.setSproutGrowthProgress(sproutGrowthProgress)
        scene.setEnvironment(environment)
        applyOrnaments()
        scene.setLitOrnamentLights(litOrnamentLights)
        scene.setTuning(tuning)
    }

    private func applyOrnaments() {
        scene.setOrnaments(
            presented: presentedOrnaments,
            unlocked: unlockedOrnaments
        )
    }

    private var boGrowthAccessibilityValue: String {
        switch boGrowthStage {
        case .dormant: AppLocalization.text("bo 尚未开始生长")
        case .sprouting: AppLocalization.text("bo 正在发芽")
        case .forming: AppLocalization.text("bo 正在成形")
        case .ripe: AppLocalization.text("bo 已经成熟")
        }
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
            && lhs.boGrowthStage == rhs.boGrowthStage
            && lhs.sproutGrowthProgress == rhs.sproutGrowthProgress
            && lhs.environment == rhs.environment
            && lhs.presentedOrnaments == rhs.presentedOrnaments
            && lhs.unlockedOrnaments == rhs.unlockedOrnaments
            && lhs.litOrnamentLights == rhs.litOrnamentLights
            && lhs.tuning == rhs.tuning
            && lhs.isPaused == rhs.isPaused
            && lhs.isObscured == rhs.isObscured
            && lhs.commandController === rhs.commandController
    }
}

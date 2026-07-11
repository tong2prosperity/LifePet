import Foundation
import Combine
import SwiftUI
import SpriteKit
import UIKit

/// SwiftUI bridge to the SpriteKit `PiboStageScene`. Holds one scene for the
/// view's lifetime and forwards theme / state / growth changes + one-shot
/// effect tokens.
struct PiboStageView: View {
    let theme: PiboTheme
    let state: PiboActivityState
    /// 魔丸 head growth (「?」卷芽 ⇄ 发芽带叶) — drives which head sprite shows.
    var growth: PiboGrowthStage = .sprouted
    /// 当前天气 — 开/关下雨三件套(雨幕 / 地面水花 / 滴在 Pibo 上)。
    var weather: PiboWeather = .clear
    var onPat: () -> Void = {}
    /// Fired when the head 毛 is dragged past the pull threshold (the 拔毛 gesture).
    var onHairPulled: () -> Void = {}
    /// 点击场景内「摄影馆」icon → 弹出露珠相机。
    var onEnterCamera: () -> Void = {}
    /// 点击场景内「健身房」icon → 弹出健康小游戏列表。
    var onEnterGames: () -> Void = {}
    /// Bump to fire the 能量收集 头顶毛 animation.
    var energyGainToken: UUID? = nil
    /// Set to drop a 拔毛 seed of the given color.
    var pluckToken: PluckToken? = nil
    /// Bump to play the 拍一拍 不理睬 turn-away pose.
    var turnAwayToken: UUID? = nil
    /// Bump to run the 发芽 close-up (camera zoom + 毛抖动 → 长出叶片); phases
    /// stream back through `onSproutPhase` so the chrome can sync its captions.
    var sproutToken: UUID? = nil
    var onSproutPhase: (SproutCloseupPhase) -> Void = { _ in }
    /// Suspend the stage when an opaque feature covers Home. The `SpriteView`
    /// itself is detached below; `isPaused` alone does not reliably stop
    /// `SKView`'s display-link/render callbacks while a full-screen cover keeps
    /// the underlying SwiftUI hierarchy alive.
    var isPaused: Bool = false

    // Non-zero initial size so the scene presents + builds immediately;
    // `.resizeFill` then snaps it to the real SpriteView bounds.
    @State private var scene = PiboStageScene(size: CGSize(width: 390, height: 760))
    @State private var renderController = PiboStageRenderController()

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
            .onChange(of: theme.id) { _, _ in scene.apply(theme: theme, state: state, growth: growth) }
            .onChange(of: state) { _, _ in scene.apply(theme: theme, state: state, growth: growth) }
            .onChange(of: growth) { _, _ in scene.apply(theme: theme, state: state, growth: growth) }
            .onChange(of: weather) { _, w in scene.setWeather(w) }
            .onChange(of: energyGainToken) { _, token in
                if token != nil { scene.playEnergyGain() }
            }
            .onChange(of: pluckToken?.id) { _, _ in
                if let pluckToken { scene.playPluck(color: SKColor(pluckToken.color)) }
            }
            .onChange(of: turnAwayToken) { _, token in
                if token != nil { scene.playTurnAway() }
            }
            .onChange(of: sproutToken) { _, token in
                if token != nil { scene.playSproutCloseup(onPhase: onSproutPhase) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                renderController.refreshLowPowerMode()
            }
        }
    }

    private func configureScene(size: CGSize) {
        if size.width > 1, size.height > 1 { scene.size = size }
        scene.onPat = onPat
        scene.onHairPulled = onHairPulled
        scene.onEnterCamera = onEnterCamera
        scene.onEnterGames = onEnterGames
        scene.onDirectManipulationChanged = { [weak renderController] active in
            renderController?.setDirectManipulation(active: active)
        }
        scene.onHighRefreshRequested = { [weak renderController] duration in
            renderController?.requestHighRefresh(for: duration)
        }
        scene.apply(theme: theme, state: state, growth: growth)
        scene.setWeather(weather)
    }
}

/// One-shot 拔毛 effect descriptor — `id` drives the trigger, `color` the seed.
struct PluckToken: Equatable {
    let id: UUID
    let color: Color
}

import SwiftUI
import SpriteKit

/// SwiftUI bridge to the SpriteKit `PiboStageScene`. Holds one scene for the
/// view's lifetime and forwards theme / state / growth changes + one-shot
/// effect tokens.
struct PiboStageView: View {
    let theme: PiboTheme
    let state: PiboActivityState
    /// 魔丸 head growth (「?」卷芽 ⇄ 发芽带叶) — drives which head sprite shows.
    var growth: PiboGrowthStage = .sprouted
    var onPat: () -> Void = {}
    /// Fired when the head 毛 is dragged past the pull threshold (the 拔毛 gesture).
    var onHairPulled: () -> Void = {}
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
    /// Pause the render loop when the stage is fully hidden (e.g. parked on the
    /// 数据二楼) so it isn't running at 60fps behind an opaque panel.
    var isPaused: Bool = false

    // Non-zero initial size so the scene presents + builds immediately;
    // `.resizeFill` then snaps it to the real SpriteView bounds.
    @State private var scene = PiboStageScene(size: CGSize(width: 390, height: 760))

    var body: some View {
        // Drive the scene size from SwiftUI: SpriteView does not honor
        // `.resizeFill` here, so without this the scene stays at its initial size
        // and gets non-uniformly stretched to fill the view (Pibo looks elongated).
        GeometryReader { geo in
            SpriteView(scene: scene, isPaused: isPaused, options: [.allowsTransparency])
                .background(Color.clear)
                .onAppear {
                    scene.size = geo.size
                    scene.onPat = onPat
                    scene.onHairPulled = onHairPulled
                    scene.apply(theme: theme, state: state, growth: growth)
                }
                .onChange(of: geo.size) { _, newSize in
                    if newSize.width > 1, newSize.height > 1 { scene.size = newSize }
                }
                .onChange(of: theme.id) { _, _ in scene.apply(theme: theme, state: state, growth: growth) }
                .onChange(of: state) { _, _ in scene.apply(theme: theme, state: state, growth: growth) }
                .onChange(of: growth) { _, _ in scene.apply(theme: theme, state: state, growth: growth) }
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
        }
    }
}

/// One-shot 拔毛 effect descriptor — `id` drives the trigger, `color` the seed.
struct PluckToken: Equatable {
    let id: UUID
    let color: Color
}

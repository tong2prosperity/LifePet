import SwiftUI
import SpriteKit

/// SwiftUI bridge to the SpriteKit `PiboStageScene`. Holds one scene for the
/// view's lifetime and forwards theme / state changes + one-shot effect tokens.
struct PiboStageView: View {
    let theme: PiboTheme
    let state: PiboActivityState
    var onPat: () -> Void = {}
    /// Bump to fire the 能量收集 头顶毛 animation.
    var energyGainToken: UUID? = nil
    /// Set to drop a 拔毛 seed of the given color.
    var pluckToken: PluckToken? = nil

    // Non-zero initial size so the scene presents + builds immediately;
    // `.resizeFill` then snaps it to the real SpriteView bounds.
    @State private var scene = PiboStageScene(size: CGSize(width: 390, height: 760))

    var body: some View {
        SpriteView(scene: scene, options: [.allowsTransparency])
            .background(Color.clear)
            .onAppear {
                scene.onPat = onPat
                scene.apply(theme: theme, state: state)
            }
            .onChange(of: theme.id) { _, _ in scene.apply(theme: theme, state: state) }
            .onChange(of: state) { _, _ in scene.apply(theme: theme, state: state) }
            .onChange(of: energyGainToken) { _, token in
                if token != nil { scene.playEnergyGain() }
            }
            .onChange(of: pluckToken?.id) { _, _ in
                if let pluckToken { scene.playPluck(color: SKColor(pluckToken.color)) }
            }
    }
}

/// One-shot 拔毛 effect descriptor — `id` drives the trigger, `color` the seed.
struct PluckToken: Equatable {
    let id: UUID
    let color: Color
}

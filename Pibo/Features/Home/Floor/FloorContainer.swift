import SwiftUI

// MARK: - Floor container (pull-up coordinator)

/// Owns the 上滑 `progress` + the drag. The 数据二楼 is **one** rising drawer — a
/// single #E8EEF1 `FloorDome` surface (convex-up domed top, fills down) with the
/// content on top — that translates as a unit, so the domed leading edge travels
/// continuously from a bottom peek (closed) to the ceiling (open). One colour + one
/// shape means no two-tone boundary / floating "lens" mid-drag. Only this view reads
/// `floor.progress`, so a drag re-renders just this thin shell — the stage / chrome /
/// 二楼 bodies are not re-evaluated per frame (they update only when their own inputs
/// change).
struct FloorContainer<Stage: View, Chrome: View, Content: View>: View {
    let floor: FloorModel
    /// Fired when a settle-to-open lands (the drawer fully covers the stage) —
    /// the moment it's safe to pause the SpriteKit loop. Never fires for a
    /// settle that was caught mid-flight.
    var onCovered: () -> Void = {}
    /// Fired the moment the stage may become visible again (a drag armed from
    /// the open floor, or a settle-to-closed started) — resume the loop
    /// *before* anything is revealed, so Pibo is never seen frozen.
    var onRevealing: () -> Void = {}
    @ViewBuilder let stage: Stage
    @ViewBuilder let chrome: Chrome
    @ViewBuilder let content: Content

    @Environment(\.scenePhase) private var scenePhase

    /// `progress` captured at the start of a drag, so partial drags compose.
    @State private var dragBase: CGFloat? = nil
    /// Whether the in-flight drag is allowed to move the floor. Armed only when a
    /// pull starts on the bottom control band (or the floor is already open).
    @State private var dragActive = false
    /// Mirrors "a drag is being tracked" via GestureState, which the system
    /// resets even when the gesture is *cancelled* (interruption, mask change)
    /// — the one case `onEnded` never reports. `dragActive` outliving this
    /// reset means the drag died mid-flight and the floor must self-settle.
    @GestureState private var dragTracking = false

    /// The dome grab band pinned to the very bottom — the only place a pull can
    /// *open* the 二楼. Sized to stay clear of the 露珠相机 button (its bottom
    /// edge sits 96pt above the safe-area bottom: an 88pt spacer + `LP.Spacing.s`).
    /// (Computed, not stored: `FloorContainer` is generic, and Swift forbids
    /// static stored properties in generic types.)
    private static var grabBandHeight: CGFloat { 88 }

    /// The *open*-state grab band over the 二楼 dome ceiling — drag-down here closes
    /// (the history `ScrollView` would otherwise eat the close-drag) and a tap returns
    /// home. Sized to the ceiling crown so normal list scrolling below it is untouched.
    private static var topGrabBandHeight: CGFloat { 100 }

    /// How much of the rising drawer's #E8EEF1 crown peeks above the bottom edge
    /// when closed (the rest of the dome arc bleeds up via the cap's `rise`). The
    /// drawer translates by `(1 − p)·(h − crownReveal)`, so the crown travels
    /// continuously from this bottom peek (closed) to the ceiling (open) — one
    /// surface, no handoff. 42 + `rise` 54 lands the closed apex ~96pt above the
    /// bottom (matching the old closed dome).
    private static var crownReveal: CGFloat { 42 }

    /// Above this progress the opaque drawer covers all but the status-bar sliver of
    /// the stage — the point at which it's safe to pause the SpriteKit render loop.
    private static var coverThreshold: CGFloat { 0.98 }

    /// The shared core of "the container-level drag may move the floor" — the 二楼 is
    /// open enough that a drag-down should close it, or a settle tween is mid-flight
    /// (so a finger can take it over). Single-sourced so the gesture *mask* and the
    /// `onChanged` *arm guard* can't drift (they add their own `dragActive` / `fromBand`
    /// term on top). Reads `floor.progress` / `isAnimating`, same as before.
    private var floorEngaged: Bool { floor.progress > 0.5 || floor.isAnimating }

    var body: some View {
        GeometryReader { geo in
            let h = max(geo.size.height, 1)
            let p = floor.progress
            // The drawer `ignoresSafeArea`, so its travel is in *full-screen* px
            // (h is only the safe-area height). `travel` = full height − the closed
            // crown peek; the drag normalizes by it too, so the finger tracks the
            // crown 1:1. Degrades correctly when insets are 0.
            let travel = h + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom - Self.crownReveal
            // Grab handle screen-Y, lerped from the closed bottom dome (~64pt above
            // the very bottom) to the open ceiling (~just below the status bar). In
            // the GeometryReader's space y=0 sits at the top safe-area edge.
            let closedHandleY = h + geo.safeAreaInsets.bottom - 64
            let handleY = closedHandleY + (14 - closedHandleY) * p
            ZStack {
                // Pibo (+ themed stage) holds place with a hair of parallax; the
                // rising panel *submerges* it bottom-up, so its 下半身 is covered
                // first — never left dangling mid-screen. They always overlap, so
                // there's no uncovered (black) gap.
                stage
                    .offset(y: -p * h * 0.06)

                chrome
                    // No opacity fade — the opaque rising drawer covers the chrome
                    // bottom-up, which is cheaper than offscreen-compositing the chrome
                    // (+ its shadows) every frame. Hit-testing stops once the drawer is up.
                    .allowsHitTesting(p < 0.08)

                // === 数据二楼：单一上升抽屉（body + 历史内容 + #E8EEF1 顶盖 crown）===
                // 整体平移 (1−p)·(h−crownReveal)：关闭时 crown 从底部探头、打开时
                // crown 抵达顶部 —— 一路连续，没有「关闭态 dome + 上升 panel」两段
                // 交接（修复衔接生硬）。crown 在 content 之上绘制，TabView 的不透明
                // 背景再也盖不住它（修复二楼顶部 dome 消失）。
                ZStack(alignment: .top) {
                    // 单一 #E8EEF1 抽屉面：convex-up 圆顶引导边 + 向下填满。一种颜色、
                    // 一个形状 → 上滑全程是连续上升的整面，没有双色边界、也没有缓慢
                    // 关闭时那块"悬浮圆角透镜"（旧 FloorCap 下唇离开底边造成的，与
                    // 最终关闭态不一致）。圆顶下方就是页底，内容（透明）叠在其上。
                    FloorDome(rise: 54)
                        .fill(LP.Fill.bgSurfaceSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .shadow(color: .black.opacity(0.10), radius: 14, y: -3)
                    // 历史页随不透明抽屉整体升起、自然露出 —— 不再用 .opacity 渐变，
                    // 省掉每帧把整页历史画到离屏缓冲再做 alpha 合成的开销（卡顿主因）。
                    // 把「二楼是否打开」写进 content 子树：水面着色器据此停转。`p` 每帧
                    // 在变，但传下去的是阈值布尔，只在跨 0.98 那一刻翻转，故不会逐帧
                    // 重渲染历史页 —— 仅读它的 `WaterSurface` 会响应。
                    content
                        .environment(\.floorIsOpen, p > Self.coverThreshold)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // `.ignoresSafeArea()` must wrap the frame *before* the offset, so the
                // surface is resolved to the full screen (incl. both insets) and only
                // then render-shifted. Applying the offset first defeated the bottom
                // extension — SwiftUI clamped the fill at the safe-area bottom, leaving
                // the ~34pt home-indicator inset painted in the window's #FFFFFF (the
                // "dome 被截断 / 上下底色不一致" gap). Offset is a pure transform here; it
                // never re-clips, so the full-bleed surface stays full-bleed at any p.
                .ignoresSafeArea()
                .offset(y: (1 - p) * travel)
                // 历史页可见时（已上楼），VoiceOver 两指 Z「escape」手势可从任意位置
                // 关闭二楼 —— 滚进卡片后也能关闭，补上原本只在顶/底抓手区的关闭入口。
                .accessibilityAction(.escape) { close() }

                // 抓手箭头：唯一、全程可见的把手，跟着 crown 从「底部 dome」滑到
                // 「顶部 ceiling」（screen-Y 在闭/开两处线性插值），p<0.5 显示 ʌ(上滑)、
                // 否则 ⌄(下拉关闭)。它绑在「在动的 crown」上而非会淡出的图层，所以
                // 拖动中途绝不消失（修复上滑时箭头丢失）。纯视觉，不拦手势。
                Image(systemName: p < 0.5 ? "chevron.compact.up" : "chevron.compact.down")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(LP.Content.quarternary)
                    .position(x: geo.size.width / 2, y: handleY)
                    .allowsHitTesting(false)

                // 抓手区 — invisible grab band over the closed-state crown peek. While
                // closed it carries the *only* pull-up gesture (the container gesture is
                // masked off then), a tap opens, and it's the VoiceOver "上滑查看数据"
                // button. Sits ABOVE the drawer so its taps win over the (hit-disabled)
                // peeking crown; armed only when closed via `allowsHitTesting`.
                grabBand(dragHeight: travel, height: Self.grabBandHeight, alignment: .bottom,
                         armed: p < 0.08, label: AppLocalization.text("上滑查看数据"), onTap: open)

                // 顶部抓手区 — invisible grab band over the open-state ceiling crown:
                // drag-down closes (above the history ScrollView so the close-drag isn't
                // eaten by list scrolling) + tap-to-close + VoiceOver "回到Pibo". Armed
                // only when open.
                grabBand(dragHeight: travel, height: Self.topGrabBandHeight, alignment: .top,
                         armed: p > 0.9, label: AppLocalization.text("回到Pibo"), onTap: close)
            }
            .contentShape(Rectangle())
            // While the floor is closed this container-level gesture is masked
            // OFF (`.subviews`) — a full-screen recognizer would claim (and
            // cancel) any >12pt touch stream, killing the SpriteKit stage's 拖毛
            // drag. The grab band above carries the open gesture instead. Open /
            // settling: full-screen again, so a drag-down anywhere closes and a
            // mid-flight panel can be caught like a sheet. `dragActive` MUST keep
            // the mask at `.all` for the whole drag: a close pull crossing below
            // p = 0.5 would otherwise flip the mask mid-gesture and the system
            // would cancel the drag on the spot — no onEnded, no settle, floor
            // stranded half-open with every control unreachable.
            .gesture(drag(height: travel, fromBand: false),
                     including: dragActive || floorEngaged ? .all : .subviews)
            // Pause the SpriteKit stage whenever it's fully hidden by the drawer —
            // threshold-driven so it also pauses when the user drag-*holds* the floor
            // open (not just on a settle-to-open landing), and resumes the instant a
            // close starts. 0.98 = only the status-bar sliver of the stage is uncovered,
            // so Pibo is never seen frozen. This is the single source of truth for the
            // stage's `isPaused`, replacing the scattered onCovered/onRevealing calls.
            .onChange(of: p > Self.coverThreshold, initial: true) { _, covered in
                if covered { onCovered() } else { onRevealing() }
            }
        }
        // A system interruption (call banner, app switcher) can cancel the drag
        // without `onEnded` ever firing — snap to the nearest floor so the pull
        // never strands half-open with the chrome faded and unreachable.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, dragActive else { return }
            cancelDragAndSettle()
        }
        // Same guarantee for any *in-app* cancellation: GestureState resets when
        // the gesture ends for ANY reason. A normal release clears `dragActive`
        // in `onEnded` first, so this only fires when the drag was cancelled —
        // then the floor must settle itself or it strands half-open.
        .onChange(of: dragTracking) { _, tracking in
            guard !tracking, dragActive else { return }
            cancelDragAndSettle()
        }
    }

    // MARK: Grab bands

    /// One invisible grab band — `Color.clear` over a crown peek. Both the closed
    /// (bottom, opens) and open (top, closes) bands are this same shape; they differ
    /// only in height, alignment, armed predicate, tap action, and a11y label. Shares
    /// the container `drag` so a pull from the band scrubs the floor 1:1.
    @ViewBuilder
    private func grabBand(dragHeight: CGFloat, height: CGFloat, alignment: Alignment,
                          armed: Bool, label: String, onTap: @escaping () -> Void) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .gesture(drag(height: dragHeight, fromBand: true))
            .frame(height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityAction(.default, onTap)
            .allowsHitTesting(armed)
    }

    // MARK: Settle / interruption recovery

    /// A drag died without an `onEnded` (system interruption, or any GestureState
    /// reset). Clear the drag state and snap to the nearer floor so the pull never
    /// strands half-open. Single-sources the C6 robustness contract shared by the
    /// `scenePhase` and `dragTracking` cancellation paths.
    private func cancelDragAndSettle() {
        dragBase = nil
        dragActive = false
        settleAfterInterruption()
    }

    /// Snap to the nearer floor after a cancelled drag. No finger velocity to carry
    /// (the gesture died), so the spring settles from rest. Stage pause/resume is
    /// driven by the `p > coverThreshold` onChange, so this just re-launches it.
    private func settleAfterInterruption() {
        floor.animate(to: floor.progress > 0.5 ? 1 : 0)
    }

    // MARK: Tap open / close

    /// Open the 二楼 — tap / VoiceOver action on the 上滑区域 grab band. A tap has no
    /// finger velocity, so the settle spring runs from rest (v0 = 0) — a decisive
    /// spring-in to fully open, same curve a flick-release lands on.
    private func open() {
        LPHaptics.tap()
        floor.animate(to: 1)
    }

    /// Close the 二楼 — tap / VoiceOver action on the top dome ceiling grab band
    /// (drag-down closes through the shared `drag` path). Mirrors `open()`; stage
    /// resume rides the `p > coverThreshold` onChange as the spring retreats.
    private func close() {
        LPHaptics.tap()
        floor.animate(to: 0)
    }

    // MARK: Drag

    /// Finger-tracking pull; snaps to the nearer floor (or follows a flick) on
    /// release. `minimumDistance` lets taps reach the band's tap-to-open and the
    /// 二楼 controls.
    ///
    /// Two attachment points share this builder: the bottom grab band
    /// (`fromBand` — always armed, only exists while the floor is closed) and
    /// the container itself (armed only when the floor is open **or a settle
    /// spring is mid-flight**, so the panel can be caught anywhere like a sheet
    /// and a drag-down anywhere closes). An un-armed drag is ignored end-to-end.
    private func drag(height h: CGFloat, fromBand: Bool) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragTracking) { _, tracking, _ in tracking = true }
            .onChanged { v in
                if !dragActive {
                    guard fromBand || floorEngaged else { return }
                    floor.stop()               // take over an in-flight tween where it visually is
                    dragBase = floor.progress  // == on-screen position (updated live every frame)
                    dragActive = true
                }
                let base = dragBase ?? floor.progress
                let np = min(1, max(0, base + (-v.translation.height) / h))
                floor.progress = np
            }
            .onEnded { v in
                defer { dragBase = nil; dragActive = false }
                guard dragActive else { return }
                let base = dragBase ?? floor.progress
                let p = min(1, max(0, base + (-v.translation.height) / h))
                // A quick flick commits to that direction even if short; otherwise
                // snap to the nearer floor.
                let flickUp = -v.predictedEndTranslation.height > 150
                let flickDown = v.predictedEndTranslation.height > 150
                let target: CGFloat = flickUp ? 1 : (flickDown ? 0 : (p > 0.5 ? 1 : 0))
                // Carry the release velocity into the settle spring (iOS system feel):
                // finger points/sec ÷ travel → progress units/sec, up = +progress. So a
                // hard flick continues at speed, a gentle release eases in. `v.velocity`
                // is the live drag velocity (iOS 17+); same `h` as `onChanged`'s scale.
                let releaseVelocity = -v.velocity.height / h
                floor.animate(to: target, initialVelocity: releaseVelocity)
            }
    }
}

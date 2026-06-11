import SwiftUI
import SwiftData
import Observation
import QuartzCore

/// Drives the 上滑二楼 pull. Owned by `HomeView` for its lifetime but read **only**
/// by `FloorContainer`, so mutating `progress` during a drag re-renders just the
/// thin transform shell — never the stage / chrome / 二楼 subtrees.
///
/// The settle is a **model-driven spring** (`settle(to:)` writes `progress`
/// every frame) rather than `withAnimation`: the model always equals the visual
/// position, so a finger can catch the panel mid-flight without a jump
/// (`withAnimation` snaps the model to the target instantly and only the
/// presentation lags), the spring can be seeded with the release velocity, and
/// hit-testing — which SwiftUI resolves against model values — always matches
/// what's on screen.
@Observable final class FloorModel {
    var progress: CGFloat = 0
    /// Pibo's 下半身 handle — shown only once the 二楼 is fully open, dropping in
    /// from behind the status bar. Toggled on settle, never mid-drag.
    var feetShown: Bool = false

    @ObservationIgnored private var settleTask: Task<Void, Never>? = nil
    /// True while a settle spring is flying — a drag may catch it from anywhere.
    var isSettling: Bool { settleTask != nil }

    /// A finger took over: stop the spring exactly where it visually is.
    func beginInteraction() {
        settleTask?.cancel()
        settleTask = nil
    }

    /// Spring `progress` toward 0/1. `velocity` is the finger's release speed in
    /// progress-units/s so a flick hands its momentum to the spring seamlessly.
    /// `completion` fires only when the spring lands naturally — never when it
    /// was caught by a new drag or replaced by another settle.
    func settle(to target: CGFloat, velocity: CGFloat = 0, completion: (() -> Void)? = nil) {
        beginInteraction()
        settleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var x = self.progress
            var v = velocity
            let omega = 2 * CGFloat.pi / FloorAnim.panelResponse
            let zeta = FloorAnim.panelDamping
            var last = CACurrentMediaTime()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(8))
                if Task.isCancelled { return }
                let now = CACurrentMediaTime()
                let dt = CGFloat(min(now - last, 1.0 / 30.0))
                last = now
                v += (-(omega * omega) * (x - target) - 2 * zeta * omega * v) * dt
                x += v * dt
                if abs(x - target) < 0.001, abs(v) < 0.02 {
                    self.progress = target
                    self.settleTask = nil
                    completion?()
                    return
                }
                self.progress = x
            }
        }
    }
}

/// Shared spring timings for the 上滑二楼 choreography (used by both the drag
/// settle and the tap-to-open/close paths so they stay identical).
enum FloorAnim {
    /// Panel settle spring constants — consumed by `FloorModel.settle`'s
    /// model-driven spring (the feel of the old `.spring(0.46, 0.86)`).
    static let panelResponse: CGFloat = 0.46
    static let panelDamping: CGFloat = 0.86
    static let feetIn  = Animation.spring(response: 0.52, dampingFraction: 0.6)   // emerge w/ slight overshoot
    static let feetOut = Animation.spring(response: 0.26, dampingFraction: 0.85)
    /// Delay before the feet drop, so they arrive *after* the panel has settled.
    static let feetDelay: TimeInterval = 0.24
}

/// Pibo home (魔丸态) — the SpriteKit stage fills the screen; SwiftUI overlays
/// the chrome: greeting + 与Pibo相识第 N 天, the 露珠相机 button, the 上滑
/// Dashboard handle, 拍一拍 speech, 拔毛, and the 能量收集 flow.
///
/// Per the home spec, there are no stat bars / step cards / star-light — Pibo's
/// state and the head-flower come straight off raw HealthKit + time of day
/// (see `PetStateStore+Mowan`).
struct HomeView: View {
    @Environment(PetStateStore.self) private var store

    @State private var speech: PiboSpeechLine? = nil
    @State private var speechClear: Task<Void, Never>? = nil
    /// 上滑二楼 state — 0 = home floor, 1 = data 二楼. Lives in a model HomeView
    /// owns but does not read, so the drag only re-renders `FloorContainer`.
    @State private var floor = FloorModel()
    /// Pause the stage's 60fps loop while parked on the 二楼. Toggled on settle
    /// (not per frame), so the stage is never re-rendered mid-drag.
    @State private var stagePaused = false
    @State private var showCamera = false
    @State private var showSettings = false
    @State private var energyToken: UUID? = nil
    @State private var pluckToken: PluckToken? = nil
    @State private var turnAwayToken: UUID? = nil
    /// 发芽 close-up trigger + phase (Figma 74:6102: workout detected → 特写
    /// pibo头顶动画 → 能量已收集 pop). See `EnergySproutFlow.swift`.
    @State private var sproutToken: UUID? = nil
    @State private var sproutPhase: SproutFlowPhase = .idle
    /// Greeting / day-label cached once (they're "drawn once per day"): keeps the
    /// header off the per-frame Calendar path while the 二楼 pull-up drags.
    @State private var greetingText: String = ""
    @State private var dayLabelText: String = ""

    @AppStorage(PiboPersistenceKeys.Defaults.onboardingDone) private var onboardingDone: Bool = false

    var body: some View {
        ZStack {
            FloorContainer(
                floor: floor,
                // Pause only once the panel actually covers the stage; resume
                // the moment a closing interaction could reveal it — so Pibo
                // never visibly freezes mid-bob or thaws with a pop.
                onCovered: { stagePaused = true },
                onRevealing: { stagePaused = false },
                stage: {
                    PiboStageView(
                        theme: store.currentTheme,
                        state: store.activityState,
                        growth: store.growthStage,
                        onPat: handlePat,
                        energyGainToken: energyToken,
                        pluckToken: pluckToken,
                        turnAwayToken: turnAwayToken,
                        sproutToken: sproutToken,
                        onSproutPhase: handleSproutPhase,
                        isPaused: stagePaused
                    )
                    .ignoresSafeArea()
                },
                chrome: { chromeContent },
                panel: { secondFloorPanel },
                content: {
                    PiboDashboardView()
                        .environment(store)
                        // ⌄ back to the home floor (Figma plant frames) — also
                        // the accessible close path (the drag isn't reachable
                        // via VoiceOver; the up-chevron opens but nothing closed).
                        .overlay(alignment: .top) { closeHandle }
                }
            )

            // 发芽 close-up captions, synced to the stage phases.
            if sproutPhase == .collecting || sproutPhase == .sprouted {
                VStack(spacing: 0) {
                    SproutCaptionView(text: sproutPhase == .collecting
                                      ? "收集到你的运动能量！"
                                      : "Pibo...发芽了啵！")
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            // 能量已收集 pop — back on the home floor (Figma 70:4549).
            if sproutPhase == .pop {
                EnergyCollectedPop(onDismiss: dismissEnergyPop)
            }
        }
        // No subtree-wide `.animation(value:)` here: an ambient animation that
        // fires while the user is dragging would capture that frame's
        // `floor.progress` change too and make the panel lag the finger for a
        // beat. Speech / sprout transitions animate via explicit `withAnimation`
        // at their mutation sites instead (`show`, `setSproutPhase`).
        .task { await idleMutterLoop() }
        .onAppear {
            greetingText = store.mowanGreeting
            dayLabelText = store.relationshipDayLabel
            // Cold launch with a restored fresh workout (app opened right after
            // a run): give the stage a beat to build, then play the flow.
            if store.pendingWorkout != nil {
                Task {
                    try? await Task.sleep(for: .seconds(0.7))
                    maybeStartEnergyFlow()
                }
            }
        }
        .onChange(of: store.pendingWorkout?.id) { _, id in
            if id != nil { maybeStartEnergyFlow() }
        }
        .fullScreenCover(isPresented: $showCamera) {
            PiboCameraView(onPhotoSaved: handlePhotoSaved).environment(store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(onReset: performReset).environment(store)
        }
    }

    // MARK: Chrome (home greeting / speech / controls)

    /// Whether the 发芽 close-up owns the screen (chrome hides, captions show).
    private var closeupActive: Bool {
        sproutPhase == .collecting || sproutPhase == .sprouted
    }

    /// All the home-floor overlay built as one subtree. `FloorContainer` fades it
    /// out as the 二楼 rises, so it has no per-progress logic of its own.
    private var chromeContent: some View {
        GeometryReader { geo in
            ZStack {
                // Speech bubble floats just above Pibo's head (~30% down).
                if let speech {
                    PiboSpeechBubbleView(line: speech)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.30)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                VStack(spacing: 0) {
                    header
                    Spacer()
                    bottomControls
                }
                .padding(.horizontal, LP.Spacing.l)
            }
            .opacity(closeupActive ? 0 : 1)
            .allowsHitTesting(!closeupActive)
        }
    }

    /// The 二楼 surface — a domed crown over the cool grey-blue panel. Rendered
    /// behind (and risen with) the data content, so the content can fade in on
    /// top of an already-opaque surface.
    private var secondFloorPanel: some View {
        FloorDome(rise: 54)
            .fill(Color(hex: 0xEAEEEF))
            // 球状 lighter dome (Figma Ellipse 24, x−180 / y−655 / 749²): its bottom
            // cap reads as a soft lighter dome behind Pibo's hanging lower body at the
            // top of the opened 二楼 (#F4F8F9 vs the #EAEEEF panel).
            .overlay(alignment: .top) {
                Circle()
                    .fill(LP.Fill.bgSurface)   // #F4F8F9 = grey 100
                    .frame(width: 749, height: 749)
                    .offset(y: -655)
            }
            // CLIP to the dome — without this the 749² circle bleeds far above the
            // crown and paints #F4F8F9 over the whole home scene whenever the panel
            // is only partway up (holding the pull mid-way hid Pibo behind a big
            // light circle). Clipped, the lighter cap only ever shows *inside* the
            // panel, so Pibo stays visible and is submerged from the feet up.
            .clipShape(FloorDome(rise: 54))
            // Crown legibility: panel over the near-white home bg is white-on-white —
            // a soft upward shadow on the clipped dome crown gives the rising edge
            // contrast so the pull reads as "二楼 rising", not "the screen turning white".
            .compositingGroup()
            .shadow(color: .black.opacity(0.10), radius: 14, y: -3)
            .ignoresSafeArea()
    }

    // MARK: Header

    /// Header — faithful to Figma `HomeHeader` (76:6662): the `b4Medium` greeting
    /// (14pt) over the `uiH4` 与Pibo相识的第 N 天 line (28pt), both
    /// `LP.Content.secondary`. Themed homes (Figma 74:6101) slot the 主题名
    /// (桃花时节 / 阿那亚的海风里) between them; the 魔丸 default has none.
    private var header: some View {
        HStack(alignment: .top, spacing: LP.Spacing.s) {
            VStack(alignment: .leading, spacing: LP.Spacing.s) {
                Text(greetingText.isEmpty ? store.mowanGreeting : greetingText)
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Content.secondary)
                if !store.currentTheme.displayName.isEmpty {
                    Text(AppLocalization.text(store.currentTheme.displayName))
                        .lpText(LP.Typography.uiH4)
                        .foregroundStyle(LP.Content.secondary)
                }
                Text(dayLabelText.isEmpty ? store.relationshipDayLabel : dayLabelText)
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.secondary)
            }
            Spacer(minLength: 0)
            Button {
                LPHaptics.tap()
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(LP.Content.secondary)
                    .frame(width: 28, height: 28)
                    .padding(LP.Spacing.xs)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.text("设置"))
        }
        .padding(.top, LP.Spacing.s)
    }

    // MARK: Bottom controls

    /// 露珠相机 floats in the lower third (Figma `74:6178`, 88pt @ ~80% height),
    /// with the grab-bar chevron pinned to the very bottom — they're not stacked.
    private var bottomControls: some View {
        VStack(spacing: 0) {
            if store.pluckAvailable {
                pluckButton
                Spacer().frame(height: LP.Spacing.m)
            }
            cameraButton
            Spacer().frame(height: 60)
            upArrowHandle
        }
        .padding(.bottom, LP.Spacing.s)
    }

    private var cameraButton: some View {
        Button {
            LPHaptics.tap()
            showCamera = true
        } label: {
            Image(systemName: "camera")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(LP.Content.secondary)
                .frame(width: 84, height: 84)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair))
                .lpShadow(LP.Shadow.elevation2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("拍照"))
    }

    private var pluckButton: some View {
        Button {
            LPHaptics.tap()
            doPluck()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill").font(.system(size: 12))
                Text(AppLocalization.text("收下今天的毛"))
                    .lpText(LP.Typography.b3Medium)
            }
            .foregroundStyle(LP.Fill.foundationOnAccent)
            .padding(.horizontal, LP.Spacing.l)
            .padding(.vertical, LP.Spacing.s)
            .background(Capsule().fill(LP.Fill.foundationAccent))
            .lpShadow(LP.Shadow.elevation2)
        }
        .buttonStyle(.plain)
    }

    private var upArrowHandle: some View {
        Button(action: openDashboard) {
            Image(systemName: "chevron.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LP.Content.tertiary)
                .frame(width: 44, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("上滑查看数据"))
    }

    /// ⌄ on the 二楼, mirroring the home's ʌ — sits between Pibo's hanging feet
    /// and the date strip. (拖拽尾巴/下划 also close: the page-wide drag arms
    /// from anywhere while the floor is open, including over the feet.)
    private var closeHandle: some View {
        Button(action: closeFloor) {
            Image(systemName: "chevron.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LP.Content.tertiary)
                .frame(width: 44, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 36)
        .accessibilityLabel(AppLocalization.text("回到Pibo"))
    }

    // MARK: 拍一拍

    private func handlePat() {
        LPHaptics.tap()
        let response = store.pat()
        if response.turnsAway { turnAwayToken = UUID() }
        if let line = response.line { show(line) }
    }

    // MARK: 能量收集 (发芽 flow — see EnergySproutFlow.swift)

    /// Workout detected (app open / push while foregrounded): play the 发芽
    /// close-up if the head can still sprout, otherwise the small in-place
    /// shake — both end on the 能量已收集 pop.
    private func maybeStartEnergyFlow() {
        guard store.pendingWorkout != nil, sproutPhase == .idle else { return }
        let canSprout = store.growthStage == .mystery
            && store.currentTheme.sproutedHeadSprite != nil
            && floor.progress < 0.5    // parked on the 二楼 → skip the theater
        if canSprout {
            switch SproutAnimationStyle.current {
            case .stagePlaceholder:
                setSproutPhase(.collecting)
                sproutToken = UUID()
            case .lottie:
                // TODO(design): full-screen Lottie player once the asset lands;
                // until then the stage placeholder carries the sequence.
                setSproutPhase(.collecting)
                sproutToken = UUID()
            }
        } else {
            energyToken = UUID()
            setSproutPhase(.pop)
        }
    }

    private func handleSproutPhase(_ phase: SproutCloseupPhase) {
        switch phase {
        case .shaking:
            break   // caption already up
        case .sprouted:
            store.markSprouted()   // pibo头顶发生变化 — persists the new head
            setSproutPhase(.sprouted)
        case .finished:
            setSproutPhase(.pop)
        }
    }

    private func dismissEnergyPop() {
        LPHaptics.tap()
        store.consumePendingWorkout()
        setSproutPhase(.idle)
    }

    /// Animates the flow-phase transitions locally — scoped here instead of a
    /// subtree-wide `.animation(value:)` so mid-drag frames are never captured.
    private func setSproutPhase(_ phase: SproutFlowPhase) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) { sproutPhase = phase }
    }

    // MARK: 拔毛 / 拍照

    private func doPluck() {
        let grade = store.pluck()
        pluckToken = PluckToken(id: UUID(), color: grade.seedColor)
        show(PiboSpeechLine(text: grade.piboLines.randomElement() ?? "...给...你..."))
    }

    private func handlePhotoSaved() {
        // 拍照 = 认知能量. Nudge the head 毛 + let Pibo react (spec §4.3).
        energyToken = UUID()
        if Bool.random() {
            show(PiboSpeechLine(text: PiboCameraView.genericComments.randomElement() ?? "...颜色...记..."))
        }
    }

    // MARK: Floor

    private func openDashboard() {
        LPHaptics.tap()
        // Pause only when the panel has actually covered the stage — pausing up
        // front froze Pibo mid-bob in plain sight for the whole rise. The
        // completion is skipped if a drag catches the panel mid-flight.
        floor.settle(to: 1) { stagePaused = true }
        withAnimation(FloorAnim.feetIn.delay(FloorAnim.feetDelay)) { floor.feetShown = true }
    }

    private func closeFloor() {
        LPHaptics.tap()
        stagePaused = false   // resume before anything is revealed
        withAnimation(FloorAnim.feetOut) { floor.feetShown = false }
        floor.settle(to: 0)
    }

    // MARK: Speech plumbing

    private func show(_ line: PiboSpeechLine) {
        speechClear?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { speech = line }
        let linger: Double = line.mood == .murmur || line.isStoryClue ? 3.4 : 2.6
        speechClear = Task {
            try? await Task.sleep(for: .seconds(linger))
            if !Task.isCancelled {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { speech = nil }
            }
        }
    }

    /// Idle self-mutter loop (spec §3.3) — every 15–30s, ~20% chance Pibo
    /// drifts a line on its own. Cancelled automatically when the view leaves.
    private func idleMutterLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 15...30)))
            if speech == nil, sproutPhase == .idle, let line = store.idleMutter() { show(line) }
        }
    }

    private func performReset() {
        store.reset()
        onboardingDone = false
    }
}

// MARK: - Floor container (pull-up coordinator)

/// Owns the 上滑 `progress` + the drag, applying offset/opacity to three subtrees
/// that `HomeView` builds once. Only this view reads `floor.progress`, so a drag
/// re-renders just this thin shell — the stage / chrome / 二楼 bodies are not
/// re-evaluated per frame (they update only when their own inputs change).
private struct FloorContainer<Stage: View, Chrome: View, Panel: View, Content: View>: View {
    let floor: FloorModel
    /// Fired when a settle-to-open lands (the panel fully covers the stage) —
    /// the moment it's safe to pause the SpriteKit loop. Never fires for a
    /// settle that was caught mid-flight.
    var onCovered: () -> Void = {}
    /// Fired the moment the stage may become visible again (a drag armed from
    /// the open floor, or a settle-to-closed started) — resume the loop
    /// *before* anything is revealed, so Pibo is never seen frozen.
    var onRevealing: () -> Void = {}
    @ViewBuilder let stage: Stage
    @ViewBuilder let chrome: Chrome
    @ViewBuilder let panel: Panel
    @ViewBuilder let content: Content

    @Environment(\.scenePhase) private var scenePhase

    /// `progress` captured at the start of a drag, so partial drags compose.
    @State private var dragBase: CGFloat? = nil
    /// Whether the in-flight drag is allowed to move the floor. Armed only when a
    /// pull starts on the bottom control band (or the floor is already open).
    @State private var dragActive = false

    /// A pull may *open* the 二楼 only when it starts below this fraction of the
    /// screen height — i.e. on the bottom control cluster (露珠相机 circle + grab
    /// chevron), not from Pibo or the header. (Computed, not stored: `FloorContainer`
    /// is generic, and Swift forbids static stored properties in generic types.)
    private static var openDragZoneTop: CGFloat { 0.72 }

    var body: some View {
        GeometryReader { geo in
            let h = max(geo.size.height, 1)
            let p = floor.progress
            let cT = Self.contentReveal(p)
            let cF = Self.chromeFade(p)
            ZStack {
                // Pibo (+ themed stage) holds place with a hair of parallax; the
                // rising panel *submerges* it from the feet up, so its 下半身 is the
                // first thing covered — never left dangling mid-screen. They always
                // overlap, so there's no uncovered (black) gap.
                stage
                    .offset(y: -p * h * 0.06)

                chrome
                    .opacity(cF)
                    .allowsHitTesting(p < 0.08)

                // 二楼 surface: domed panel, rises with the finger, fully opaque.
                panel
                    .offset(y: (1 - p) * h)
                    .opacity(p > 0.001 ? 1 : 0)

                // 二楼 data: rises with the panel but *materializes* via a
                // late-weighted fade (+ a tiny settle) — never a rigid fly-in.
                content
                    .offset(y: (1 - p) * h + CGFloat(1 - cT) * 14)
                    .opacity(cT)
                    .allowsHitTesting(p > 0.9)
            }
            .contentShape(Rectangle())
            .gesture(drag(height: h))
        }
        // Pibo 下半身 crown — a full-screen overlay that *actually* ignores the safe
        // area (the earlier per-layer `.ignoresSafeArea` inside the GeometryReader
        // didn't push the body up — it sat at the safe-area top). Now the body
        // bleeds up behind the status bar / dynamic island like the Figma. Hidden
        // through the pull; drops in from behind the status bar after the floor opens.
        .overlay {
            VStack(spacing: 0) {
                feet
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .offset(y: floor.feetShown ? -16 : -176)
            .opacity(floor.feetShown ? 1 : 0)
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        // A system interruption (call banner, app switcher) can cancel the drag
        // without `onEnded` ever firing — snap to the nearest floor so the pull
        // never strands half-open with the chrome faded and unreachable.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, dragActive else { return }
            dragBase = nil
            dragActive = false
            settleAfterInterruption()
        }
    }

    private func settleAfterInterruption() {
        let target: CGFloat = floor.progress > 0.5 ? 1 : 0
        if target == 0 {
            onRevealing()
            withAnimation(FloorAnim.feetOut) { floor.feetShown = false }
            floor.settle(to: 0)
        } else {
            withAnimation(FloorAnim.feetIn.delay(FloorAnim.feetDelay)) { floor.feetShown = true }
            floor.settle(to: 1) { onCovered() }
        }
    }

    /// The hanging lower-body + feet — `pibo_lower`, the exact Figma 二楼 Pibo
    /// (Group 70 render, 226×110): a wide body tapering to two feet. Rendered at
    /// the Figma width (226pt) so the silhouette matches; `pibo_body` is a
    /// different (rounder) shape and can't be scaled to fit.
    private var feet: some View {
        Image("pibo_lower")
            .resizable()
            .scaledToFit()
            .frame(width: 226)
            .compositingGroup()
            .shadow(color: .black.opacity(0.10), radius: 9, y: 6)
    }

    /// Late-weighted smoothstep — content stays hidden through the first ~45% of
    /// the pull, then develops to full by the top (so you don't see it mid-drag).
    private static func contentReveal(_ p: CGFloat) -> Double {
        let t = max(0, min(1, (Double(p) - 0.45) / 0.55))
        return t * t * (3 - 2 * t)
    }

    /// First-screen ease-out — the mirror of `contentReveal`. The chrome (greeting /
    /// 相机 / 抓手) holds for the first few % of the pull, then *eases* out on a
    /// smoothstep, fully gone by ~62%. Replaces a fast linear fade (`1 − p·1.7`) so
    /// the home doesn't snap off — it dissolves out as the 二楼 dissolves in.
    private static func chromeFade(_ p: CGFloat) -> Double {
        let t = max(0, min(1, (Double(p) - 0.06) / 0.56))
        return 1 - t * t * (3 - 2 * t)
    }

    /// Finger-tracking pull; snaps to the nearer floor (or follows a flick) on
    /// release. `minimumDistance` lets taps reach Pibo (拍一拍) and 二楼 controls.
    ///
    /// Gating: a pull is *armed* if it starts on the bottom control band
    /// (`openDragZoneTop`), the floor is already open, **or a settle spring is
    /// mid-flight** (so the panel can be caught anywhere, like a sheet) — an
    /// up-swipe on Pibo / the header does nothing, while a drag-down anywhere
    /// still closes the 二楼. An un-armed drag is ignored end-to-end.
    private func drag(height h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                if !dragActive {
                    let fromHandle = v.startLocation.y >= h * Self.openDragZoneTop
                    guard floor.progress > 0.5 || fromHandle || floor.isSettling else { return }
                    floor.beginInteraction()   // catch the spring where it visually is
                    onRevealing()              // the stage may show under finger control
                    dragBase = floor.progress  // == on-screen position (model-driven)
                    dragActive = true
                }
                let base = dragBase ?? floor.progress
                let np = min(1, max(0, base + (-v.translation.height) / h))
                floor.progress = np
                // Retract the feet as soon as a pull-down starts from the open floor.
                if floor.feetShown && np < 0.92 {
                    withAnimation(FloorAnim.feetOut) { floor.feetShown = false }
                }
            }
            .onEnded { v in
                defer { dragBase = nil; dragActive = false }
                guard dragActive else { return }
                let base = dragBase ?? floor.progress
                let p = min(1, max(0, base + (-v.translation.height) / h))
                let flickUp = -v.predictedEndTranslation.height > 150
                let flickDown = v.predictedEndTranslation.height > 150
                let target: CGFloat = flickUp ? 1 : (flickDown ? 0 : (p > 0.5 ? 1 : 0))
                // Hand the finger's speed to the spring (progress-units/s, up = +).
                let releaseVelocity = -v.velocity.height / h
                if target == 0 { onRevealing() }
                floor.settle(to: target, velocity: releaseVelocity) {
                    if target == 1 { onCovered() }
                }
                if target > 0.5 {
                    withAnimation(FloorAnim.feetIn.delay(FloorAnim.feetDelay)) { floor.feetShown = true }
                } else {
                    withAnimation(FloorAnim.feetOut) { floor.feetShown = false }
                }
            }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: HealthDayRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return HomeView()
        .environment(PetStateStore(demoMode: true))
        .environment(HealthHistoryStore(context: container.mainContext))
}

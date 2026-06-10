import SwiftUI
import SwiftData
import Observation

/// Drives the 上滑二楼 pull. Owned by `HomeView` for its lifetime but read **only**
/// by `FloorContainer`, so mutating `progress` during a drag re-renders just the
/// thin transform shell — never the stage / chrome / 二楼 subtrees.
@Observable final class FloorModel {
    var progress: CGFloat = 0
    /// Pibo's 下半身 handle — shown only once the 二楼 is fully open, dropping in
    /// from behind the status bar. Toggled on settle, never mid-drag.
    var feetShown: Bool = false
}

/// Shared spring timings for the 上滑二楼 choreography (used by both the drag
/// settle and the tap-to-open/close paths so they stay identical).
enum FloorAnim {
    static let panel   = Animation.spring(response: 0.46, dampingFraction: 0.86)
    static let feetIn  = Animation.spring(response: 0.52, dampingFraction: 0.6)   // emerge w/ slight overshoot
    static let feetOut = Animation.spring(response: 0.26, dampingFraction: 0.85)
    /// Delay before the feet drop, so they arrive *after* the panel has settled.
    static let feetDelay: TimeInterval = 0.24
}

/// Pibo home (魔丸态) — the SpriteKit stage fills the screen; SwiftUI overlays
/// the chrome: greeting + 与Pibo相识第 N 天, the 露珠相机 button, the 上滑
/// Dashboard handle, 拍一拍 speech, 拔毛, and the 能量收集 card.
///
/// Per the home spec, there are no stat bars / step cards / star-light — Pibo's
/// state and the head-flower come straight off raw HealthKit + time of day
/// (see `PetStateStore+Mowan`).
struct HomeView: View {
    @Environment(PetStateStore.self) private var store

    @State private var speech: String? = nil
    @State private var speechClear: Task<Void, Never>? = nil
    /// 上滑二楼 state — 0 = home floor, 1 = data 二楼. Lives in a model HomeView
    /// owns but does not read, so the drag only re-renders `FloorContainer`.
    @State private var floor = FloorModel()
    /// Pause the stage's 60fps loop while parked on the 二楼. Toggled on settle
    /// (not per frame), so the stage is never re-rendered mid-drag.
    @State private var stagePaused = false
    @State private var showCamera = false
    @State private var energyToken: UUID? = nil
    @State private var pluckToken: PluckToken? = nil
    @State private var showResetConfirm = false
    /// Greeting / day-label cached once (they're "drawn once per day"): keeps the
    /// header off the per-frame Calendar path while the 二楼 pull-up drags.
    @State private var greetingText: String = ""
    @State private var dayLabelText: String = ""

    @AppStorage(PiboPersistenceKeys.Defaults.onboardingDone) private var onboardingDone: Bool = false

    var body: some View {
        FloorContainer(
            floor: floor,
            onSettle: { target in stagePaused = target > 0.5 },
            stage: {
                PiboStageView(
                    theme: store.currentTheme,
                    state: store.activityState,
                    onPat: handlePat,
                    energyGainToken: energyToken,
                    pluckToken: pluckToken,
                    isPaused: stagePaused
                )
                .ignoresSafeArea()
            },
            chrome: { chromeContent },
            panel: { secondFloorPanel },
            content: {
                PiboDashboardView().environment(store)
            }
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: store.pendingWorkout)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: speech)
        .task { await idleMutterLoop() }
        .onAppear {
            greetingText = store.mowanGreeting
            dayLabelText = store.relationshipDayLabel
        }
        .onChange(of: store.pendingWorkout?.id) { _, id in
            if id != nil { energyToken = UUID() }
        }
        .fullScreenCover(isPresented: $showCamera) {
            PiboCameraView(onPhotoSaved: handlePhotoSaved).environment(store)
        }
        .confirmationDialog(
            AppLocalization.text("重置后会回到首启流程"),
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.text("重新开始"), role: .destructive, action: performReset)
            Button(AppLocalization.text("取消"), role: .cancel) {}
        }
    }

    // MARK: Chrome (home greeting / speech / controls / energy card)

    /// All the home-floor overlay built as one subtree. `FloorContainer` fades it
    /// out as the 二楼 rises, so it has no per-progress logic of its own.
    private var chromeContent: some View {
        GeometryReader { geo in
            ZStack {
                // Speech bubble floats just above Pibo's head (~30% down).
                if let speech {
                    PiboSpeechCloud(text: speech)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.30)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                VStack(spacing: 0) {
                    header
                    Spacer()
                    bottomControls
                }
                .padding(.horizontal, LP.Spacing.l)

                if store.pendingWorkout != nil {
                    EnergyCollectCard(
                        petName: store.petName,
                        gain: store.pendingWorkout?.gainVitality ?? 0,
                        onCollect: { store.consumePendingWorkout() },
                        onDismiss: { store.dismissPendingWorkout() }
                    )
                    .padding(.horizontal, LP.Spacing.l)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    /// The 二楼 surface — a domed crown over the cool grey-blue panel. Rendered
    /// behind (and risen with) the data content, so the content can fade in on
    /// top of an already-opaque surface.
    private var secondFloorPanel: some View {
        FloorDome(rise: 54)
            .fill(Color(hex: 0xEAEEEF))
            .ignoresSafeArea()
            // 球状 background (Figma Ellipse 24, x−180 / y−655 / 749²): a big light
            // circle whose bottom cap reads as a soft lighter dome behind Pibo's
            // lower body. Lighter than the panel (#F4F8F9 vs #EAEEEF).
            .overlay(alignment: .top) {
                Circle()
                    .fill(LP.Fill.bgSurface)   // #F4F8F9 = grey 100
                    .frame(width: 749, height: 749)
                    .offset(y: -655)
                    .ignoresSafeArea(edges: .top)
            }
    }

    // MARK: Header

    /// Header — faithful to Figma `HomeHeader` (76:6662): the `b4Medium` greeting
    /// (14pt) over the `uiH4` 与Pibo相识的第 N 天 line (28pt), both
    /// `LP.Content.secondary` (≈ rgba(0,0,0,0.72)), gear top-right. No theme-name
    /// title — the theme is expressed through the stage art.
    private var header: some View {
        HStack(alignment: .top, spacing: LP.Spacing.s) {
            VStack(alignment: .leading, spacing: LP.Spacing.s) {
                Text(greetingText.isEmpty ? store.mowanGreeting : greetingText)
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Content.secondary)
                Text(dayLabelText.isEmpty ? store.relationshipDayLabel : dayLabelText)
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.secondary)
            }
            Spacer(minLength: 0)
            Button {
                LPHaptics.tap()
                showResetConfirm = true
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

    // MARK: Actions

    private func handlePat() {
        LPHaptics.tap()
        if let line = store.pat() { show(line) }
    }

    private func doPluck() {
        let grade = store.pluck()
        pluckToken = PluckToken(id: UUID(), color: grade.seedColor)
        show(grade.piboLines.randomElement() ?? "...给...你...")
    }

    private func handlePhotoSaved() {
        // 拍照 = 认知能量. Nudge the head 毛 + let Pibo react (spec §4.3).
        energyToken = UUID()
        if Bool.random() {
            show(PiboCameraView.genericComments.randomElement() ?? "...颜色...记...")
        }
    }

    private func openDashboard() {
        LPHaptics.tap()
        stagePaused = true
        withAnimation(FloorAnim.panel) { floor.progress = 1 }
        withAnimation(FloorAnim.feetIn.delay(FloorAnim.feetDelay)) { floor.feetShown = true }
    }

    private func closeFloor() {
        LPHaptics.tap()
        withAnimation(FloorAnim.feetOut) { floor.feetShown = false }
        withAnimation(FloorAnim.panel) { floor.progress = 0 }
        stagePaused = false
    }

    private func show(_ line: String) {
        speechClear?.cancel()
        withAnimation { speech = line }
        speechClear = Task {
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { withAnimation { speech = nil } }
        }
    }

    /// Idle self-mutter loop (spec §3.3) — every 15–30s, ~20% chance Pibo
    /// drifts a line on its own. Cancelled automatically when the view leaves.
    private func idleMutterLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 15...30)))
            if speech == nil, let line = store.idleMutter() { show(line) }
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
    /// Called once when a drag settles, with the target floor (0 or 1).
    var onSettle: (CGFloat) -> Void = { _ in }
    @ViewBuilder let stage: Stage
    @ViewBuilder let chrome: Chrome
    @ViewBuilder let panel: Panel
    @ViewBuilder let content: Content

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
            ZStack {
                // Pibo (+ themed stage) holds place with a hair of parallax; the
                // rising panel *submerges* it from the feet up, so its 下半身 is the
                // first thing covered — never left dangling mid-screen. They always
                // overlap, so there's no uncovered (black) gap.
                stage
                    .offset(y: -p * h * 0.06)

                chrome
                    .opacity(1 - Double(min(1, p * 1.7)))
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

    /// Finger-tracking pull; snaps to the nearer floor (or follows a flick) on
    /// release. `minimumDistance` lets taps reach Pibo (拍一拍) and 二楼 controls.
    ///
    /// Gating: a pull is *armed* only if it starts on the bottom control band
    /// (`openDragZoneTop`) or the floor is already open — so an up-swipe on Pibo /
    /// the header does nothing, while a drag-down anywhere still closes the 二楼.
    /// An un-armed drag is ignored end-to-end (no snap on release).
    private func drag(height h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                if !dragActive {
                    let fromHandle = v.startLocation.y >= h * Self.openDragZoneTop
                    guard floor.progress > 0.5 || fromHandle else { return }
                    dragBase = floor.progress
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
                onSettle(target)
                withAnimation(FloorAnim.panel) { floor.progress = target }
                if target > 0.5 {
                    withAnimation(FloorAnim.feetIn.delay(FloorAnim.feetDelay)) { floor.feetShown = true }
                } else {
                    withAnimation(FloorAnim.feetOut) { floor.feetShown = false }
                }
            }
    }
}

// MARK: - Speech cloud

/// Pibo's garbled one-liner, as a soft rounded bubble.
private struct PiboSpeechCloud: View {
    let text: String

    var body: some View {
        Text(text)
            .lpText(LP.Typography.b2Medium)
            .foregroundStyle(LP.Content.primary)
            .padding(.horizontal, LP.Spacing.l)
            .padding(.vertical, LP.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .strokeBorder(LP.Separator.primary, lineWidth: LP.BorderWidth.hair)
            )
            .lpShadow(LP.Shadow.elevation2)
    }
}

// MARK: - 能量收集 card

private struct EnergyCollectCard: View {
    let petName: String
    let gain: Int
    let onCollect: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: LP.Spacing.m) {
            Image(systemName: "figure.run")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LP.Fill.foundationOnAccent)
                .frame(width: 38, height: 38)
                .background(Circle().fill(LP.Fill.foundationAccent))
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.text("收集到你的运动能量！"))
                    .lpText(LP.Typography.b2Medium)
                    .foregroundStyle(LP.Content.primary)
                Text(AppLocalization.format("%@ 感觉到了…+%d", petName, gain))
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
            }
            Spacer(minLength: LP.Spacing.s)
            Button(action: onCollect) {
                Text(AppLocalization.text("收下"))
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Fill.foundationOnAccent)
                    .padding(.horizontal, LP.Spacing.l)
                    .padding(.vertical, LP.Spacing.s)
                    .background(Capsule().fill(LP.Fill.foundationAccent))
            }
            .buttonStyle(.plain)
        }
        .padding(LP.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgPop)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .strokeBorder(LP.Separator.primary, lineWidth: LP.BorderWidth.hair)
        )
        .lpShadow(LP.Shadow.elevation3)
        .onTapGesture(perform: onDismiss)
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

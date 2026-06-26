import SwiftUI
import SwiftData
import UIKit
import os

// The 上滑二楼 pull-up subsystem now lives in `Features/Home/Floor/`:
//   • `FloorModel`  — the CADisplayLink-driven `progress` tween + `FloorAnim` + the
//                     `floorIsOpen` environment value (read by the history WaterSurface).
//   • `FloorContainer` — the pull-up coordinator view embedded by `HomeView` below.
//   • `FloorDome`   — the #E8EEF1 drawer surface shape.
// HomeView only owns a `FloorModel` and hands closures to `FloorContainer`.

/// Pibo home (魔丸态) — the SpriteKit stage fills the screen; SwiftUI overlays
/// the chrome: greeting + 与Pibo相识第 N 天, the 露珠相机 button, the 上滑
/// Dashboard handle, 拍一拍 speech, 拔毛, and the 能量收集 flow.
///
/// Per the home spec, there are no stat bars / step cards / star-light — Pibo's
/// state and the head-flower come straight off raw HealthKit + time of day
/// (see `PetStateStore+Mowan`).
struct HomeView: View {
    @Environment(PetStateStore.self) private var store
    @Environment(HealthHistoryStore.self) private var history

    @State private var speech: PiboSpeechLine? = nil
    @State private var speechClear: Task<Void, Never>? = nil
    /// 上滑二楼 state — 0 = home floor, 1 = data 二楼. Lives in a model HomeView
    /// owns but does not read, so the drag only re-renders `FloorContainer`.
    @State private var floor = FloorModel()
    /// Pause the stage's 60fps loop while parked on the 二楼. Toggled on settle
    /// (not per frame), so the stage is never re-rendered mid-drag.
    @State private var stagePaused = false
    @State private var showCamera = false
    @State private var showWalkDoodle = false
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
                        weather: store.weather,
                        onPat: handlePat,
                        onHairPulled: handleHairPull,
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
                // The 二楼 content (数据 / 自定义 Pibo tab container) rides inside
                // FloorContainer's single rising drawer, under the #E8EEF1 crown.
                content: { HistoryFloorView().environment(store) }
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
        .fullScreenCover(isPresented: $showWalkDoodle) {
            WalkDoodleView(onSaved: handleDoodleSaved)
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
    /// floating just above the 上滑区域 dome — the dome + its ʌ are drawn by
    /// `FloorContainer` (so they crossfade into the rising 二楼 panel), not here.
    private var bottomControls: some View {
        VStack(spacing: 0) {
            // Pibo 在主界面给用户布置的任务 — 出门走一幅地图涂鸦 (运动能量).
            WalkDoodleTaskCard { showWalkDoodle = true }
            Spacer().frame(height: LP.Spacing.m)
            if store.pluckAvailable {
                pluckButton
                Spacer().frame(height: LP.Spacing.m)
            }
            cameraButton
            // Reserve the 上滑区域 dome band below the 相机 (was a 60pt spacer +
            // 28pt chevron; the chevron now lives on the dome in `FloorContainer`).
            Spacer().frame(height: 88)
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
                // Figma 509:2659: a solid fill-bg-container (#FBFCFC) disc, *not*
                // a translucent material — over the themed stage the near-white
                // body + elevation2 shadow keep it cleanly distinct from the bg.
                .background(LP.Fill.bgContainer, in: Circle())
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

    // MARK: 拍一拍

    private func handlePat() {
        LPHaptics.tap()
        let response = store.pat()
        if response.turnsAway { turnAwayToken = UUID() }
        if let line = response.line { show(line) }
    }

    /// 拖毛 released past the pull threshold (scene's `onHairPulled`). Inside
    /// the 22:00–02:00 window this IS the 拔毛 collection; outside it Pibo just
    /// hates having its 毛 yanked and turns away — no speech, doesn't touch the
    /// pat caps.
    private func handleHairPull() {
        LPHaptics.tap()
        if store.pluckAvailable {
            doPluck()
        } else {
            turnAwayToken = UUID()
        }
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

    private func handlePhotoSaved(_ image: UIImage?, _ subjectLabel: String?) {
        // 拍照 = 认知能量. Nudge the head 毛 + let Pibo react (spec §4.3).
        LPLog.cutout.notice("photo saved → post-processing (hasImage=\(image != nil, privacy: .public) label=\(subjectLabel ?? "—", privacy: .public))")
        energyToken = UUID()
        if Bool.random() {
            show(PiboSpeechLine(text: PiboCameraView.genericComments.randomElement() ?? "...颜色...记..."))
        }
        // Persist a background-removed (抠图) + 镶边框 copy, tagged with the 识图
        // label, as a 今日记录 food photo so it lands on the 历史数据页 (home
        // spec §4). Heavy Vision work runs off-main.
        guard let image else {
            LPLog.cutout.info("no captured image (placeholder device) — skipping 抠图/persist")
            return
        }
        let capturedAt = Date()
        Task {
            let png = await Task.detached { SubjectCutout.stickerPNG(image) }.value
            guard let png else {
                LPLog.cutout.error("贴纸 PNG nil — FoodPhoto not persisted")
                return
            }
            history.addFoodPhoto(pngData: png, capturedAt: capturedAt, subjectLabel: subjectLabel)
            LPLog.cutout.notice("FoodPhoto persisted \(png.count / 1024, privacy: .public)KB label=\(subjectLabel ?? "—", privacy: .public) at \(LPLog.dateFormatter.string(from: capturedAt), privacy: .public)")
        }
    }

    // MARK: 地图涂鸦 (walk doodle — see Features/WalkDoodle)

    /// Walk doodle saved (运动能量) — persist it for the 足迹涂鸦 history card,
    /// nudge the head 毛, and let Pibo grumble a line (spec §3.4 energy lineage).
    private func handleDoodleSaved(_ result: WalkDoodleResult) {
        history.addWalkDoodle(result)
        energyToken = UUID()
        show(PiboSpeechLine(text: WalkDoodleCopy.savedLines.randomElement() ?? "...画...完了..."))
        LPLog.app.notice("walk doodle saved: \(Int(result.distanceMeters), privacy: .public)m \(Int(result.areaSquareMeters), privacy: .public)m²")
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

#Preview {
    // Reuse `HistoryPreviewData` (the long-lived, disk-backed, all-three-models store
    // shared with PiboHistoryView's preview). HomeView embeds PiboHistoryView (the 二
    // 楼), whose `makeDay` fetches WorkoutRecord + FoodPhoto — so the preview needs the
    // SAME guarantees: (1) all 3 @Model types in the schema (a partial schema traps on
    // the fetch), and (2) a container that OUTLIVES the #Preview closure (a local `let`
    // deallocates → the context's rows invalidate → SwiftData traps on the next
    // re-layout/animation frame). An inline in-memory container hit both traps.
    HomeView()
        .environment(PetStateStore(demoMode: true))
        .environment(HistoryPreviewData.store)
}

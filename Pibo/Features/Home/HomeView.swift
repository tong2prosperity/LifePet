import SwiftUI
import SwiftData
import UIKit
import os

/// Pibo home (魔丸态) — a horizontally-pannable SpriteKit world (旅行青蛙-style):
/// drag left/right to roam between zones (照相馆 · Pibo 的栖息地 · 游戏场), tap a
/// zone to enter its feature. The home zone keeps 拍一拍 / 拔毛 / 能量收集. SwiftUI
/// overlays only the chrome: greeting + 与Pibo相识第 N 天, the 足迹 (history) +
/// settings icons, the contextual 拔毛 button, zone dots, and the 拍一拍 speech /
/// 发芽 flow.
///
/// Feature entries are in-world now (home spec lineage, redesigned 2026-06-27):
/// 照相馆 → 露珠相机, 游戏场 → 健康小游戏列表 (`GameListView`, walk doodle 等),
/// 足迹 icon → 历史数据页. The old 上滑数据二楼 (FloorModel/FloorContainer) is retired.
///
/// Pibo's state and the head-flower come straight off raw HealthKit + time of day
/// (see `PetStateStore+Mowan`).
struct HomeView: View {
    @Environment(PetStateStore.self) private var store
    @Environment(HealthHistoryStore.self) private var history

    @State private var speech: PiboSpeechLine? = nil
    @State private var speechClear: Task<Void, Never>? = nil
    /// Which zone the camera is parked on (`StageZone.rawValue`) — gates the
    /// contextual 拔毛 button and lights the zone dots.
    @State private var currentZone: Int = StageZone.home.rawValue
    @State private var showCamera = false
    @State private var showGames = false
    @State private var showHistory = false
    @State private var showWalkDoodle = false
    @State private var showSettings = false
    @State private var energyToken: UUID? = nil
    @State private var pluckToken: PluckToken? = nil
    @State private var turnAwayToken: UUID? = nil
    /// 发芽 close-up trigger + phase (Figma 74:6102: workout detected → 特写
    /// pibo头顶动画 → 能量已收集 pop). See `EnergySproutFlow.swift`.
    @State private var sproutToken: UUID? = nil
    @State private var sproutPhase: SproutFlowPhase = .idle
    /// Greeting / day-label cached once (they're "drawn once per day").
    @State private var greetingText: String = ""
    @State private var dayLabelText: String = ""

    @AppStorage(PiboPersistenceKeys.Defaults.onboardingDone) private var onboardingDone: Bool = false

    /// Pause the 60fps stage loop while a full-screen feature covers it.
    private var stagePaused: Bool { showCamera || showGames || showHistory || showWalkDoodle }

    var body: some View {
        ZStack {
            PiboStageView(
                theme: store.currentTheme,
                state: store.activityState,
                growth: store.growthStage,
                weather: store.weather,
                onPat: handlePat,
                onHairPulled: handleHairPull,
                onEnterCamera: { showCamera = true },
                onEnterGames: { showGames = true },
                onZoneChanged: { currentZone = $0 },
                energyGainToken: energyToken,
                pluckToken: pluckToken,
                turnAwayToken: turnAwayToken,
                sproutToken: sproutToken,
                onSproutPhase: handleSproutPhase,
                isPaused: stagePaused
            )
            .ignoresSafeArea()

            chromeContent

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
        .task { await idleMutterLoop() }
        .onAppear {
            greetingText = store.mowanGreeting
            dayLabelText = store.relationshipDayLabel
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
        .fullScreenCover(isPresented: $showGames) {
            GameListView(onWalkDoodleSaved: handleDoodleSaved)
                .environment(store)
                .environment(history)
        }
        .fullScreenCover(isPresented: $showHistory) {
            HistoryScreen()
                .environment(store)
                .environment(history)
        }
        .fullScreenCover(isPresented: $showWalkDoodle) {
            WalkDoodleView(onSaved: handleDoodleSaved)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(onReset: performReset).environment(store)
        }
    }

    // MARK: Chrome

    /// Whether the 发芽 close-up owns the screen (chrome hides, captions show).
    private var closeupActive: Bool {
        sproutPhase == .collecting || sproutPhase == .sprouted
    }

    /// Whether Pibo's home zone is the one on screen — gates the 拔毛 button and
    /// the home greeting line (other zones speak for themselves via in-scene signage).
    private var onHomeZone: Bool { currentZone == StageZone.home.rawValue }

    private var chromeContent: some View {
        ZStack {
            // Speech bubble floats just above Pibo's head (~30% down) — only on home.
            if let speech, onHomeZone {
                GeometryReader { geo in
                    PiboSpeechBubbleView(line: speech)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.30)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                .allowsHitTesting(false)
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

    // MARK: Header

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
            .opacity(onHomeZone ? 1 : 0)   // greeting belongs to Pibo's zone

            Spacer(minLength: 0)

            // Fixed corner icons (旅行青蛙-style) — 足迹 history + settings.
            VStack(spacing: LP.Spacing.s) {
                historyButton
                settingsButton
            }
        }
        .padding(.top, LP.Spacing.s)
    }

    /// Hand-drawn 「足迹」 icon → the 历史数据页. A soft paper card, lightly tilted,
    /// so it reads as a hand-placed keepsake rather than a system chrome button.
    private var historyButton: some View {
        Button {
            LPHaptics.tap()
            showHistory = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "book.closed")
                    .font(.system(size: 18, weight: .regular))
                Text(AppLocalization.text("足迹"))
                    .lpText(LP.Typography.c2Medium)
            }
            .foregroundStyle(LP.Content.secondary)
            .frame(width: 48, height: 48)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                    .fill(LP.Fill.bgContainer))
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                    .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair))
            .lpShadow(LP.Shadow.elevation2)
            .rotationEffect(.degrees(-3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("足迹 · 历史数据"))
    }

    private var settingsButton: some View {
        Button {
            LPHaptics.tap()
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(LP.Content.secondary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(LP.Fill.bgContainer.opacity(0.9)))
                .lpShadow(LP.Shadow.elevation1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("设置"))
    }

    // MARK: Bottom controls

    private var bottomControls: some View {
        VStack(spacing: LP.Spacing.m) {
            if onHomeZone, store.pluckAvailable {
                pluckButton
            }
            zoneDots
        }
        .padding(.bottom, LP.Spacing.l)
    }

    /// Zone indicator dots (照相馆 · home · 游戏场) — lights the current one. Swipe
    /// the world to move between zones.
    private var zoneDots: some View {
        HStack(spacing: 8) {
            ForEach(StageZone.allCases, id: \.rawValue) { z in
                Circle()
                    .fill(z.rawValue == currentZone ? LP.Content.secondary : LP.Content.quarternary)
                    .frame(width: z.rawValue == currentZone ? 8 : 6,
                           height: z.rawValue == currentZone ? 8 : 6)
            }
        }
        .padding(.horizontal, LP.Spacing.m)
        .padding(.vertical, LP.Spacing.s)
        .background(Capsule().fill(LP.Fill.bgContainer.opacity(0.6)))
        .accessibilityHidden(true)
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

    /// 拖毛 released past the pull threshold. Inside 22:00–02:00 this IS 拔毛
    /// collection; outside it Pibo just hates it and turns away.
    private func handleHairPull() {
        LPHaptics.tap()
        if store.pluckAvailable {
            doPluck()
        } else {
            turnAwayToken = UUID()
        }
    }

    // MARK: 能量收集 (发芽 flow — see EnergySproutFlow.swift)

    private func maybeStartEnergyFlow() {
        guard store.pendingWorkout != nil, sproutPhase == .idle else { return }
        let canSprout = store.growthStage == .mystery
            && store.currentTheme.sproutedHeadSprite != nil
            && onHomeZone   // the theater only reads on Pibo's home zone
        if canSprout {
            switch SproutAnimationStyle.current {
            case .stagePlaceholder:
                setSproutPhase(.collecting)
                sproutToken = UUID()
            case .lottie:
                // TODO(design): full-screen Lottie player once the asset lands.
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
            break
        case .sprouted:
            store.markSprouted()
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

    /// Idle self-mutter loop (spec §3.3) — every 15–30s, ~20% chance Pibo drifts a
    /// line on its own. Only mutters on the home zone.
    private func idleMutterLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 15...30)))
            if speech == nil, sproutPhase == .idle, onHomeZone, let line = store.idleMutter() { show(line) }
        }
    }

    private func performReset() {
        store.reset()
        onboardingDone = false
    }
}

#Preview {
    HomeView()
        .environment(PetStateStore(demoMode: true))
        .environment(HistoryPreviewData.store)
}

import SwiftUI
import SwiftData
import UIKit
import os

/// Pibo home (魔丸态) — a single fixed SpriteKit home scene (no 横向逛场景 / camera
/// pan). Pibo stands center; two 场景内 icon flank it (摄影馆 → 露珠相机, 健身房 →
/// 健康小游戏列表), tapped in-scene to enter their feature. The scene keeps 拍一拍 /
/// 拔毛 / 能量收集. SwiftUI overlays only the chrome: greeting + 与Pibo相识第 N 天,
/// the 足迹 (history) + settings icons, the contextual 拔毛 button, and the 拍一拍
/// speech / 发芽 flow.
///
/// Feature entries are in-world (home spec lineage): 摄影馆 → 露珠相机, 健身房 →
/// 健康小游戏列表 (`GameListView`, walk doodle 等), 足迹 icon → 历史数据页. The old
/// 上滑数据二楼 (FloorModel/FloorContainer) is retired.
///
/// Pibo's state and the head-flower come straight off raw HealthKit + time of day
/// (see `PetStateStore+Mowan`).
struct HomeView: View {
    @Environment(PetStateStore.self) private var store
    @Environment(HealthHistoryStore.self) private var history

    @State private var speech: PiboSpeechLine? = nil
    @State private var speechClear: Task<Void, Never>? = nil
    @State private var showCamera = false
    @State private var showGames = false
    @State private var showHistory = false
    @State private var showWalkDoodle = false
    @State private var showSettings = false
    #if DEBUG
    @State private var debugOpenedGames = false
    #endif
    /// 拍照识别卡路里: which meal the pending camera capture belongs to (nil = a
    /// free 照相馆 shot with no recognition), and which meal's detail modal is up.
    @State private var pendingMeal: MealType? = nil
    @State private var detailMeal: MealType? = nil
    @State private var recognizer = FoodRecognitionService()
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
    /// Today's 三餐 photos, cached in state so the (warm) home body doesn't run a
    /// SwiftData fetch on every re-eval (e.g. each 拍一拍 flips `activityState`).
    /// Refreshed on appear + whenever `history.revision` bumps (a capture / 卡路里
    /// 分析 write).
    @State private var todayPhotos: [FoodPhoto] = []

    @AppStorage(PiboPersistenceKeys.Defaults.onboardingDone) private var onboardingDone: Bool = false

    /// Pause the 60fps stage loop while a feature covers it — the full-screen
    /// covers plus the two sheets (设置 / 餐食详情), which on iOS occlude the stage
    /// too (`MealDetailView` in particular can sit open a while during 卡路里 识别).
    private var stagePaused: Bool {
        showCamera || showGames || showHistory || showWalkDoodle
            || showSettings || detailMeal != nil
    }

    var body: some View {
        ZStack {
            PiboStageView(
                theme: store.currentTheme,
                state: store.activityState,
                growth: store.growthStage,
                weather: store.weather,
                onPat: handlePat,
                onHairPulled: handleHairPull,
                onEnterCamera: {
                    Analytics.track(.cameraOpen, screen: "home", ["meal": .string("none")])
                    pendingMeal = nil; showCamera = true
                },
                onEnterGames: {
                    Analytics.track(.gamesOpen, screen: "home")
                    showGames = true
                },
                energyGainToken: energyToken,
                pluckToken: pluckToken,
                turnAwayToken: turnAwayToken,
                sproutToken: sproutToken,
                onSproutPhase: handleSproutPhase,
                isPaused: stagePaused
            )
            .ignoresSafeArea()
            .accessibilityHidden(stagePaused)

            chromeContent
                .accessibilityHidden(stagePaused)

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
        .accessibilityHidden(stagePaused)
        .task { await idleMutterLoop() }
        .onAppear {
            greetingText = store.mowanGreeting
            dayLabelText = store.relationshipDayLabel
            todayPhotos = history.foodPhotos(on: Date())
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-PiboSimulateMeal") {
                Task { try? await Task.sleep(for: .seconds(1)); debugSimulateMeal(.lunch) }
            }
            if !debugOpenedGames, ProcessInfo.processInfo.arguments.contains("-PiboOpenGames") {
                debugOpenedGames = true
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    showGames = true
                }
            }
            #endif
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
        .onChange(of: history.revision) { _, _ in
            // A capture / 卡路里 分析 write landed — refresh the cached 三餐 photos
            // off the body path so the meal icons relight without re-fetching per
            // body eval.
            todayPhotos = history.foodPhotos(on: Date())
        }
        .fullScreenCover(isPresented: $showCamera) {
            PiboCameraView(onPhotoSaved: { image, label in
                handlePhotoSaved(image, label, meal: pendingMeal)
            }).environment(store)
        }
        .sheet(item: $detailMeal) { meal in
            MealDetailView(meal: meal, onRecapture: startMealCapture)
                .environment(history)
                .environment(recognizer)
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
            #if DEBUG
            SettingsSheet(onReset: performReset, onSimulateMeal: debugSimulateMeal)
                .environment(store)
            #else
            SettingsSheet(onReset: performReset)
                .environment(store)
            #endif
        }
    }

    // MARK: Chrome

    /// Whether the 发芽 close-up owns the screen (chrome hides, captions show).
    private var closeupActive: Bool {
        sproutPhase == .collecting || sproutPhase == .sprouted
    }

    private var chromeContent: some View {
        ZStack {
            // Speech bubble floats just above Pibo's head (~30% down).
            if let speech {
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
            Analytics.track(.historyOpen, screen: "home")
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
            Analytics.track(.settingsOpen, screen: "home")
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
            if store.pluckAvailable {
                pluckButton
            }
            mealIconsRow
        }
        .padding(.bottom, LP.Spacing.l)
    }

    /// 早 / 中 / 晚 — three meal icons. Tap an empty one to shoot that meal (→
    /// camera → Kimi 卡路里 识别); tap a filled one to reopen its detail modal.
    private var mealIconsRow: some View {
        // Reads the cached `todayPhotos` (refreshed on appear + history.revision) —
        // no SwiftData fetch on the home body path.
        HStack(spacing: LP.Spacing.s) {
            ForEach(MealType.allCases) { meal in
                mealIcon(meal, photos: todayPhotos)
            }
        }
        .padding(.horizontal, LP.Spacing.m)
        .padding(.vertical, LP.Spacing.s)
        .background(Capsule().fill(LP.Fill.bgContainer.opacity(0.85)))
        .lpShadow(LP.Shadow.elevation1)
    }

    private func mealIcon(_ meal: MealType, photos: [FoodPhoto]) -> some View {
        let photo = photos.last { $0.mealTypeRaw == meal.rawValue }
        let analyzing = photo.map { recognizer.isAnalyzing($0.id) } ?? false
        let kcal = photo?.totalCalories
        let filled = photo != nil
        return Button {
            LPHaptics.tap()
            if filled { detailMeal = meal } else { startMealCapture(meal) }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Image(systemName: meal.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(filled ? LP.Fill.foundationAccent : LP.Content.tertiary)
                    if analyzing {
                        ProgressView().controlSize(.mini)
                            .offset(x: 12, y: -12)
                    }
                }
                .frame(height: 20)
                if let kcal {
                    Text("\(kcal)")
                        .lpText(LP.Typography.c2Medium)
                        .foregroundStyle(LP.Content.secondary)
                } else {
                    Text(AppLocalization.text(meal.shortLabel))
                        .lpText(LP.Typography.c2Medium)
                        .foregroundStyle(filled ? LP.Content.secondary : LP.Content.tertiary)
                }
            }
            .frame(width: 44, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(meal.title) \(kcal.map { "\($0) kcal" } ?? "")")
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
        let reaction = response.line.map { $0.isStoryClue ? "story" : "spoke" } ?? "ignored"
        Analytics.track(.pat, screen: "home", ["reaction": .string(reaction)])
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
        Analytics.track(.energyCollected, screen: "home",
                        ["sprouted": .bool(store.growthStage == .sprouted)])
        store.consumePendingWorkout()
        setSproutPhase(.idle)
    }

    private func setSproutPhase(_ phase: SproutFlowPhase) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) { sproutPhase = phase }
    }

    // MARK: 拔毛 / 拍照

    private func doPluck() {
        let grade = store.pluck()
        Analytics.track(.pluck, screen: "home", ["grade": .string(grade.rawValue)])
        pluckToken = PluckToken(id: UUID(), color: grade.seedColor)
        show(PiboSpeechLine(text: grade.piboLines.randomElement() ?? "...给...你..."))
    }

    /// Open the camera for a specific meal slot (早/中/晚) — the saved photo goes
    /// to the backend for 卡路里 recognition and its detail modal pops up.
    private func startMealCapture(_ meal: MealType) {
        Analytics.track(.cameraOpen, screen: "home", ["meal": .string(meal.rawValue)])
        pendingMeal = meal
        showCamera = true
    }

    private func handlePhotoSaved(_ image: UIImage?, _ subjectLabel: String?, meal: MealType? = nil) {
        // 拍照 = 认知能量. Nudge the head 毛 + let Pibo react (spec §4.3).
        LPLog.cutout.notice("photo saved → post-processing (hasImage=\(image != nil, privacy: .public) label=\(subjectLabel ?? "—", privacy: .public) meal=\(meal?.rawValue ?? "—", privacy: .public))")
        pendingMeal = nil
        energyToken = UUID()
        Analytics.track(.photoSaved, screen: "camera",
                        ["meal": .string(meal?.rawValue ?? "none"),
                         "has_subject": .bool(subjectLabel != nil)])
        if meal == nil, Bool.random() {
            show(PiboSpeechLine(text: PiboCameraView.genericComments.randomElement() ?? "...颜色...记..."))
        }
        guard let image else {
            LPLog.cutout.info("no captured image (placeholder device) — skipping 抠图/persist")
            return
        }
        let capturedAt = Date()
        Task {
            // Show the user the Vision-processed cut-out; send the FULL frame to the VLM.
            let png = await Task.detached { SubjectCutout.stickerPNG(image) }.value
            guard let png else {
                LPLog.cutout.error("贴纸 PNG nil — FoodPhoto not persisted")
                return
            }
            let photo = history.addFoodPhoto(pngData: png, capturedAt: capturedAt,
                                             subjectLabel: subjectLabel, mealType: meal)
            LPLog.cutout.notice("FoodPhoto persisted \(png.count / 1024, privacy: .public)KB label=\(subjectLabel ?? "—", privacy: .public) at \(LPLog.dateFormatter.string(from: capturedAt), privacy: .public)")

            // Meal capture → 卡路里 识别. Pop the modal (spinner), analyze async.
            guard let meal else { return }
            // The camera fullScreenCover may still be animating out; presenting a
            // sheet mid-dismissal can get silently dropped. Wait out the flag plus
            // a short grace for the dismiss animation.
            while showCamera { try? await Task.sleep(for: .milliseconds(80)) }
            try? await Task.sleep(for: .milliseconds(420))
            detailMeal = meal
            await recognizer.analyze(photoID: photo.id, fullImage: image,
                                     hint: subjectLabel, meal: meal, history: history)
        }
    }

    // MARK: 地图涂鸦 (walk doodle — see Features/WalkDoodle)

    /// Walk doodle saved (运动能量) — persist it for the 足迹涂鸦 history card,
    /// nudge the head 毛, and let Pibo grumble a line (spec §3.4 energy lineage).
    private func handleDoodleSaved(_ result: WalkDoodleResult) {
        Analytics.track(.walkDoodleSaved, screen: "walk_doodle",
                        ["distance_m": .int(Int(result.distanceMeters)),
                         "area_m2": .int(Int(result.areaSquareMeters)),
                         "duration_s": .int(Int(result.duration))])
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
    /// line on its own.
    private func idleMutterLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 15...30)))
            if speech == nil, sproutPhase == .idle, let line = store.idleMutter() { show(line) }
        }
    }

    private func performReset() {
        Analytics.track(.reset, screen: "settings")
        store.reset()
        onboardingDone = false
    }

#if DEBUG
    /// DEV: exercise the full 拍餐识别 path without a camera — render a food emoji
    /// as the "captured" frame and run it through `handlePhotoSaved`.
    private func debugSimulateMeal(_ meal: MealType) {
        let img = Self.debugFoodImage("🍜")
        handlePhotoSaved(img, nil, meal: meal)
    }

    private static func debugFoodImage(_ emoji: String, size: CGFloat = 512) -> UIImage {
        let s = CGSize(width: size, height: size)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: s, format: fmt).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: s))
            let str = emoji as NSString
            let font = UIFont.systemFont(ofSize: size * 0.6)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let ts = str.size(withAttributes: attrs)
            str.draw(at: CGPoint(x: (size - ts.width) / 2, y: (size - ts.height) / 2),
                     withAttributes: attrs)
        }
    }
#endif
}

#Preview {
    HomeView()
        .environment(PetStateStore(demoMode: true))
        .environment(HistoryPreviewData.store)
}

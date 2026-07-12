import SwiftUI
import UIKit
import os

/// Pibo home — a fixed portrait SpriteKit forest. The scene never pans or
/// scrolls; SwiftUI owns the four corner entries and the surrounding chrome.
///
/// The top-right icon grid enters 露珠相机, 健康小游戏列表 (`GameListView`, walk
/// doodle 等), 足迹历史页, and 设置. The old in-world studio/gym entries and 上滑
/// 数据二楼 (`FloorModel` / `FloorContainer`) are retired.
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
    /// A meal passed by the detail sheet's “重拍” action. Normal home entry leaves
    /// this nil and lets the camera own purpose + meal selection.
    @State private var cameraInitialMeal: MealType? = nil
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
    @State private var atmosphereNow = Date()
    #if DEBUG
    @State private var forestTuning: ForestSceneTuning = .standard
    @State private var tuningPanelExpanded = true
    #else
    private let forestTuning: ForestSceneTuning = .standard
    #endif
    @AppStorage(PiboPersistenceKeys.Defaults.onboardingDone) private var onboardingDone: Bool = false

    /// Pause the 60fps stage loop while a feature covers it — the full-screen
    /// covers plus the two sheets (设置 / 餐食详情), which on iOS occlude the stage
    /// too (`MealDetailView` in particular can sit open a while during 卡路里 识别).
    private var stagePaused: Bool {
        showCamera || showGames || showHistory || showWalkDoodle
            || showSettings || detailMeal != nil
    }

    private var forestEnvironment: ForestEnvironmentSnapshot {
        #if DEBUG
        return ForestDayPhaseResolver.resolve(
            date: atmosphereNow,
            forcedHour: store.debugForestHour,
            rainIntensity: CGFloat(store.weather.precipitation)
        )
        #else
        return ForestDayPhaseResolver.resolve(date: atmosphereNow, rainIntensity: 0)
        #endif
    }

    var body: some View {
        ZStack {
            PiboStageView(
                theme: store.currentTheme,
                state: store.activityState,
                growth: store.growthStage,
                environment: forestEnvironment,
                tuning: forestTuning,
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
        .task { await atmosphereClockLoop() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            atmosphereNow = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            atmosphereNow = Date()
        }
        .onAppear {
            greetingText = store.mowanGreeting
            dayLabelText = store.relationshipDayLabel
            #if DEBUG
            if let hourArgument = ProcessInfo.processInfo.arguments.first(where: {
                $0.hasPrefix("-PiboForestHour=")
            }) {
                let rawValue = String(hourArgument.dropFirst("-PiboForestHour=".count))
                store.debugForestHour = rawValue == "auto" ? nil : Double(rawValue)
            }
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
        .fullScreenCover(isPresented: $showCamera) {
            PiboCameraView(initialMeal: cameraInitialMeal, onPhotoSaved: { image, label, meal in
                handlePhotoSaved(image, label, meal: meal)
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

            #if DEBUG
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    ForestTuningPanel(
                        tuning: $forestTuning,
                        isExpanded: $tuningPanelExpanded,
                        forcedHour: Binding(
                            get: { store.debugForestHour },
                            set: { store.debugForestHour = $0 }
                        )
                    )
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, LP.Spacing.l)
            .padding(.top, 118)
            #endif
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
                Text(dayLabelText.isEmpty ? store.relationshipDayLabel : dayLabelText)
                    .lpText(LP.Typography.uiH4)
                    .foregroundStyle(LP.Content.secondary)
            }

            Spacer(minLength: 0)

            cornerActions
        }
        .padding(.top, LP.Spacing.s)
    }

    private var cornerActions: some View {
        LazyVGrid(columns: [GridItem(.fixed(44), spacing: LP.Spacing.s),
                            GridItem(.fixed(44), spacing: LP.Spacing.s)],
                  spacing: LP.Spacing.s) {
            cornerButton(systemImage: "camera.fill", label: "露珠相机", rotation: -2) {
                Analytics.track(.cameraOpen, screen: "home", ["meal": .string("none")])
                cameraInitialMeal = nil
                showCamera = true
            }
            cornerButton(systemImage: "gamecontroller.fill", label: "小游戏", rotation: 2) {
                Analytics.track(.gamesOpen, screen: "home")
                showGames = true
            }
            cornerButton(systemImage: "book.closed", label: "足迹", rotation: 2) {
                Analytics.track(.historyOpen, screen: "home")
                showHistory = true
            }
            cornerButton(systemImage: "gearshape", label: "设置", rotation: -2) {
                Analytics.track(.settingsOpen, screen: "home")
                showSettings = true
            }
        }
        .frame(width: 96)
    }

    private func cornerButton(
        systemImage: String,
        label: String,
        rotation: Double,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            LPHaptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LP.Content.secondary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                        .fill(LP.Fill.bgContainer.opacity(0.90))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair)
                )
                .lpShadow(LP.Shadow.elevation1)
                .rotationEffect(.degrees(rotation))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text(label))
    }

    // MARK: Bottom controls

    private var bottomControls: some View {
        Group {
            if store.pluckAvailable {
                pluckButton
                    .padding(.bottom, LP.Spacing.l)
            }
        }
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
        cameraInitialMeal = meal
        showCamera = true
    }

    private func handlePhotoSaved(_ image: UIImage?, _ subjectLabel: String?, meal: MealType? = nil) {
        // 拍照 = 认知能量. Nudge the head 毛 + let Pibo react (spec §4.3).
        LPLog.cutout.notice("photo saved → post-processing (hasImage=\(image != nil, privacy: .public) label=\(subjectLabel ?? "—", privacy: .public) meal=\(meal?.rawValue ?? "—", privacy: .public))")
        cameraInitialMeal = nil
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

    /// Wall-clock lighting is intentionally cheap: one update per minute plus
    /// the explicit timezone/day notifications registered on the view.
    private func atmosphereClockLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if !Task.isCancelled { atmosphereNow = Date() }
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

#if DEBUG
private struct ForestTuningPanel: View {
    @Binding var tuning: ForestSceneTuning
    @Binding var isExpanded: Bool
    @Binding var forcedHour: Double?
    @State private var playbackTask: Task<Void, Never>?
    @State private var isPlayingDay = false

    var body: some View {
        Group {
            if isExpanded {
                expandedPanel
                    .transition(.scale(scale: 0.88, anchor: .topLeading).combined(with: .opacity))
            } else {
                collapsedButton
                    .transition(.scale(scale: 0.88, anchor: .topLeading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: isExpanded)
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { stopPlayback() }
        }
        .onDisappear { stopPlayback() }
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            HStack(spacing: LP.Spacing.s) {
                Label("森林细节", systemImage: "slider.horizontal.3")
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.primary)

                Spacer(minLength: 0)

                Button {
                    LPHaptics.tap()
                    stopPlayback()
                    tuning = .standard
                    forcedHour = nil
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("恢复森林默认参数")

                Button {
                    LPHaptics.tap()
                    isExpanded = false
                } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收起森林细节面板")
            }
            .foregroundStyle(LP.Content.secondary)

            Toggle("隐藏 Pibo", isOn: Binding(
                get: { !tuning.piboVisible },
                set: { tuning.piboVisible = !$0 }
            ))
            .lpText(LP.Typography.c1Regular)
            .tint(LP.Fill.foundationAccent)

            timeLightingControl

            tuningSlider(
                title: "树叶晃动",
                value: $tuning.foliageMotionScale,
                range: 0...2
            )
            tuningSlider(
                title: "水流速度",
                value: $tuning.waterFlowSpeed,
                range: 0...1.4
            )
        }
        .padding(LP.Spacing.m)
        .frame(width: 264)
        .background(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .fill(LP.Fill.bgContainer.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair)
        )
        .lpShadow(LP.Shadow.elevation2)
    }

    private var timeLightingControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: LP.Spacing.s) {
                Text("时间光影")
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.secondary)
                Spacer(minLength: 0)
                Text(forcedHour == nil ? "自动 · \(formattedHour(displayHour))" : formattedHour(displayHour))
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.tertiary)
                    .monospacedDigit()
            }

            Slider(value: hourBinding, in: 0...23.75, step: 0.25)
                .tint(LP.Fill.foundationAccent)
                .accessibilityLabel("森林时间")
                .accessibilityValue(formattedHour(displayHour))

            HStack(spacing: 4) {
                timeButton("自动", hour: nil)
                timeButton("06:30", hour: 6.5)
                timeButton("12:00", hour: 12)
                timeButton("18:30", hour: 18.5)
                timeButton("23:00", hour: 23)
            }

            Button {
                LPHaptics.tap()
                isPlayingDay ? stopPlayback() : startPlayback()
            } label: {
                Label(isPlayingDay ? "停止播放" : "24 秒播放一天",
                      systemImage: isPlayingDay ? "stop.fill" : "play.fill")
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Capsule().fill(LP.Fill.bgSurfaceSecondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlayingDay ? "停止时间光影播放" : "用二十四秒播放一天光影")
        }
    }

    private var hourBinding: Binding<Double> {
        Binding(
            get: { displayHour },
            set: { value in
                stopPlayback()
                forcedHour = (value * 4).rounded() / 4
            }
        )
    }

    private var displayHour: Double {
        forcedHour ?? localHour
    }

    private var localHour: Double {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: Date())
        return Double(components.hour ?? 12) + Double(components.minute ?? 0) / 60
    }

    private func timeButton(_ title: String, hour: Double?) -> some View {
        let isSelected: Bool
        if let hour, let forcedHour {
            isSelected = abs(hour - forcedHour) < 0.01
        } else {
            isSelected = hour == nil && forcedHour == nil
        }
        return Button {
            guard !isSelected else { return }
            LPHaptics.tap()
            stopPlayback()
            forcedHour = hour
        } label: {
            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(isSelected ? LP.Fill.foundationOnAccent : LP.Content.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(
                    Capsule().fill(isSelected ? LP.Fill.foundationAccent : LP.Fill.bgSurfaceSecondary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hour.map(formattedHour) ?? "自动跟随本地时间")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func formattedHour(_ hour: Double) -> String {
        let normalized = ForestDayPhaseResolver.normalizedHour(hour)
        let totalMinutes = Int((normalized * 60).rounded()) % (24 * 60)
        return String(format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60)
    }

    private func startPlayback() {
        stopPlayback()
        isPlayingDay = true
        playbackTask = Task { @MainActor in
            for step in 0..<96 {
                guard !Task.isCancelled else { return }
                forcedHour = Double(step) / 4
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            isPlayingDay = false
            playbackTask = nil
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlayingDay = false
    }

    private var collapsedButton: some View {
        Button {
            LPHaptics.tap()
            isExpanded = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LP.Content.secondary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                        .fill(LP.Fill.bgContainer.opacity(0.94))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair)
                )
                .lpShadow(LP.Shadow.elevation1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("展开森林细节面板")
    }

    private func tuningSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: LP.Spacing.s) {
                Text(title)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.secondary)
                Spacer(minLength: 0)
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.tertiary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 0.05)
                .tint(LP.Fill.foundationAccent)
                .accessibilityLabel(title)
                .accessibilityValue(
                    Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                )
        }
    }
}
#endif

#Preview {
    HomeView()
        .environment(PetStateStore(demoMode: true))
        .environment(HistoryPreviewData.store)
}

import AVFAudio
import SwiftUI
import UIKit
import os

/// Pibo home — a fixed portrait SpriteKit forest. The scene never pans or
/// scrolls; SwiftUI owns the four corner entries and the surrounding chrome.
///
/// The top-right icon grid enters 露珠相机, 足迹历史页, and 设置. The old in-world
/// studio/gym entries and 上滑数据二楼 (`FloorModel` / `FloorContainer`) are
/// retired. 小游戏 remains implemented but its release entry is temporarily hidden.
///
/// Pibo's state and the head-flower come straight off raw HealthKit + time of day
/// (see `PetStateStore+Mowan`).
struct HomeView: View {
    @Environment(PetStateStore.self) private var store
    @Environment(HealthHistoryStore.self) private var history
    @Environment(PiboSpeechService.self) private var piboSpeech
    @Environment(MorningSleepCoordinator.self) private var morningSleep
    /// Carries the "user tapped a stress push" request from the notification
    /// router into this view (see `presentStressCardIfPossible`).
    @Environment(StressNotifier.self) private var stressNotifier

    @Environment(\.scenePhase) private var scenePhase

    @State private var speech: PiboSpeechLine? = nil
    @State private var speechClear: Task<Void, Never>? = nil
    @State private var showCamera = false
    @State private var showGames = false
    @State private var showHistory = false
    /// Card the history cover should land on. Set only by the stress-notification
    /// deep link; the 足迹 icon opens with `nil` (top of the 足迹 tab).
    @State private var historyFocus: HistoryFocus?

    @State private var showWalkDoodle = false
    @State private var activeSheet: HomeSheetDestination?
    #if DEBUG
    @State private var debugOpenedGames = false
    @State private var debugOpenedHistory = false
    #endif
    /// A meal passed by the detail sheet's “重拍” action. Normal home entry leaves
    /// this nil and lets the camera own purpose + meal selection.
    @State private var cameraInitialMeal: MealType? = nil
    @State private var recognizer = FoodRecognitionService()
    @State private var stageCommands = PiboStageCommandController()
    /// 发芽 close-up trigger + phase (Figma 74:6102: workout detected → 特写
    /// pibo头顶动画 → 能量已收集 pop). See `EnergySproutFlow.swift`.
    @State private var sproutPhase: SproutFlowPhase = .idle
    /// Greeting / day-label cached once (they're "drawn once per day").
    @State private var greetingText: String = ""
    @State private var dayLabelText: String = ""
    @State private var atmosphereNow = Date()
    @State private var soundscape = AmbientSoundscapeService()
    #if DEBUG
    @State private var forestTuning: StageRenderTuning = .standard
    @State private var tuningPanelExpanded = !ProcessInfo.processInfo.arguments.contains("-PiboHideTuning")
    #else
    private let forestTuning: StageRenderTuning = .standard
    #endif
    @AppStorage(PiboPersistenceKeys.Defaults.onboardingDone) private var onboardingDone: Bool = false
    @AppStorage(PiboPersistenceKeys.Defaults.ambientSoundEnabled) private var ambientSoundEnabled = true

    /// Pause the 60fps stage loop while a feature covers it — the full-screen
    /// covers plus the two sheets (设置 / 餐食详情), which on iOS occlude the stage
    /// too (`MealDetailView` in particular can sit open a while during 卡路里 识别).
    private var stagePaused: Bool {
        showCamera || showGames || showHistory || showWalkDoodle
            || activeSheet != nil
    }

    private var fullScreenFeaturePresented: Bool {
        showCamera || showGames || showHistory || showWalkDoodle
    }

    private var stageEnvironment: PiboStageEnvironment {
        #if DEBUG
        return PiboStageEnvironmentResolver.resolve(
            date: atmosphereNow,
            forcedHour: store.debugForestHour,
            weather: store.weather
        )
        #else
        return PiboStageEnvironmentResolver.resolve(date: atmosphereNow)
        #endif
    }

    private var soundscapePresentation: SoundscapePresentation {
        guard scenePhase == .active else { return .suspended }
        if fullScreenFeaturePresented {
            return .suspended
        }
        switch activeSheet {
        case .settings: return .ducked
        case .meal, .morningSleep: return .suspended
        case nil: return .active
        }
    }

    var body: some View {
        ZStack {
            PiboStageView(
                theme: store.currentTheme,
                state: store.activityState,
                commandController: stageCommands,
                growth: store.growthStage,
                sproutGrowthProgress: store.headSproutGrowthProgress,
                environment: stageEnvironment,
                tuning: forestTuning,
                onPat: handlePat,
                onHairPulled: handleHairPull,
                isPaused: stagePaused
            )
            .equatable()
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
        .onReceive(NotificationCenter.default.publisher(
            for: AVAudioSession.interruptionNotification
        )) { notification in
            soundscape.handleInterruption(notification)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: AVAudioSession.silenceSecondaryAudioHintNotification
        )) { notification in
            soundscape.handleSecondaryAudioHint(notification)
        }
        .onAppear {
            greetingText = store.mowanGreeting
            dayLabelText = store.relationshipDayLabel
            speakForWeather(trigger: .entered)
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
            if !debugOpenedHistory, ProcessInfo.processInfo.arguments.contains("-PiboOpenHistory") {
                debugOpenedHistory = true
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    showHistory = true
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-PiboShowMorningSleep") {
                morningSleep.debugPresentFixture()
            }
            // Rehearse the stress-notification deep link without a real push:
            // raise the same flag the router raises, so the whole
            // present-history → 原版 tab → scroll-to-压力卡 path runs. Seed first —
            // the 压力卡 renders only when a derived score exists, and a bare
            // simulator has no heartbeat series to produce one.
            if ProcessInfo.processInfo.arguments.contains("-PiboOpenStressCard") {
                store.debugSeedStressIfNeeded()
                stressNotifier.pendingCardOpen = true
            }
            #endif
            if store.pendingWorkout != nil {
                Task {
                    try? await Task.sleep(for: .seconds(0.7))
                    maybeStartEnergyFlow()
                }
            }
            startSoundscape()
            presentMorningSleepIfPossible()
            presentStressCardIfPossible()
        }
        .onDisappear {
            soundscape.setPresentation(.suspended)
            soundscape.stop()
        }
        .onChange(of: stageEnvironment) { _, environment in
            soundscape.apply(
                environment: environment,
                date: atmosphereNow,
                petID: store.identity.currentPetId
            )
        }
        .onChange(of: store.weather) { _, _ in
            speakForWeather(trigger: .environmentChanged)
        }
        .onChange(of: store.identity.currentPetId) { _, petID in
            soundscape.apply(environment: stageEnvironment, date: atmosphereNow, petID: petID)
        }
        .onChange(of: ambientSoundEnabled) { _, enabled in
            soundscape.setEnabled(enabled)
        }
        .onChange(of: soundscapePresentation) { _, presentation in
            soundscape.setPresentation(presentation)
        }
        .onChange(of: store.pendingWorkout?.id) { _, id in
            if id != nil { maybeStartEnergyFlow() }
        }
        .onChange(of: morningSleep.pendingPresentation?.id) { _, _ in
            presentMorningSleepIfPossible()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { presentMorningSleepIfPossible() }
        }
        .onChange(of: stressNotifier.pendingCardOpen) { _, _ in
            presentStressCardIfPossible()
        }
        .onChange(of: sproutPhase) { _, phase in
            if phase == .idle { resumePendingHomeFlows() }
        }
        // Every cover/sheet resumes queued flows from `onDismiss`, i.e. once the
        // dismissal animation has finished. Reacting to the presentation binding
        // instead would try to present while the previous modal is still on its
        // way out, which SwiftUI silently drops — leaving `activeSheet` non-nil
        // with nothing on screen and no way back.
        .fullScreenCover(isPresented: $showCamera, onDismiss: resumePendingHomeFlows) {
            PiboCameraView(initialMeal: cameraInitialMeal, onPhotoSaved: { image, label, meal in
                handlePhotoSaved(image, label, meal: meal)
            }).environment(store)
        }
        .fullScreenCover(isPresented: $showGames, onDismiss: resumePendingHomeFlows) {
            GameListView(onWalkDoodleSaved: handleDoodleSaved)
                .environment(store)
                .environment(history)
        }
        .fullScreenCover(isPresented: $showHistory, onDismiss: {
            historyFocus = nil
            resumePendingHomeFlows()
        }) {
            HistoryScreen(focus: historyFocus)
                .environment(store)
                .environment(history)
        }
        .fullScreenCover(isPresented: $showWalkDoodle, onDismiss: resumePendingHomeFlows) {
            WalkDoodleView(onSaved: handleDoodleSaved)
        }
        .sheet(item: $activeSheet, onDismiss: resumePendingHomeFlows) { destination in
            switch destination {
            case .meal(let meal):
                MealDetailView(meal: meal, onRecapture: startMealCapture)
                    .environment(history)
                    .environment(recognizer)
            case .settings:
                #if DEBUG
                SettingsSheet(onReset: performReset, onSimulateMeal: debugSimulateMeal)
                    .environment(store)
                #else
                SettingsSheet(onReset: performReset)
                    .environment(store)
                #endif
            case .morningSleep(let presentation):
                MorningSleepCard(
                    presentation: presentation,
                    appearance: store.appearance,
                    weekly: SleepWeeklyReport.make(store: store, history: history)
                )
                    .onAppear { morningSleep.markPresented(presentation) }
            }
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
            cornerButton(systemImage: "book.closed", label: "足迹", rotation: 2) {
                Analytics.track(.historyOpen, screen: "home")
                showHistory = true
            }
            cornerButton(systemImage: "gearshape", label: "设置", rotation: -2) {
                Analytics.track(.settingsOpen, screen: "home")
                activeSheet = .settings
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
        if response.turnsAway { stageCommands.playTurnAway() }
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
            stageCommands.playTurnAway()
        }
    }

    // MARK: 能量收集 (发芽 flow — see EnergySproutFlow.swift)

    private func maybeStartEnergyFlow() {
        // The close-up runs on the SpriteKit stage, which `stagePaused` freezes
        // while any sheet or cover is up — starting it behind one would play the
        // whole beat where nobody can see it.
        guard let workout = store.pendingWorkout,
              sproutPhase == .idle,
              activeSheet == nil,
              !fullScreenFeaturePresented
        else { return }
        let growthStart = store.headSproutGrowthProgress
        let growthTarget = store.sproutGrowthTarget(for: workout)
        let canSprout = store.growthStage == .mystery
            && store.currentTheme.sproutedHeadSprite != nil
        if canSprout {
            switch SproutAnimationStyle.current {
            case .stagePlaceholder:
                setSproutPhase(.collecting)
                stageCommands.playSproutCloseup(
                    growthFrom: growthStart,
                    growthTo: growthTarget,
                    onPhase: handleSproutPhase
                )
            case .lottie:
                // TODO(design): full-screen Lottie player once the asset lands.
                setSproutPhase(.collecting)
                stageCommands.playSproutCloseup(
                    growthFrom: growthStart,
                    growthTo: growthTarget,
                    onPhase: handleSproutPhase
                )
            }
        } else {
            setSproutPhase(.collecting)
            stageCommands.playSproutGrowth(from: growthStart, to: growthTarget)
            let workoutID = workout.id
            Task { @MainActor in
                let delay = UIAccessibility.isReduceMotionEnabled ? 0.15 : 1.35
                try? await Task.sleep(for: .seconds(delay))
                guard store.pendingWorkout?.id == workoutID, sproutPhase == .collecting else { return }
                setSproutPhase(.pop)
            }
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
        // 发芽那一段讲的是「收集到能量」；剧本讲的是「你今天动过了」。两件事接着
        // 演，而不是抢同一个时刻。是否该演由 Core 判 —— 深眠里被叫醒秀肌肉，
        // 或者正处在长期能量不足的颓势上突然亮相，都会读成 bug。
        if PiboCoreAnimationAdapter.workoutCelebrationAllowed(for: store.activityState) {
            stageCommands.playWorkoutCelebration()
        }
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
        stageCommands.playPluck(color: grade.seedColor)
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
        stageCommands.playEnergyGain()
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
            activeSheet = .meal(meal)
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
        stageCommands.playEnergyGain()
        if let line = piboSpeech.resolve(
            cues: [
                .walkCompleted(
                    distanceMeters: result.distanceMeters,
                    duration: result.duration
                ),
            ],
            context: .home(trigger: .completed)
        ) {
            show(line)
        }
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

    private func show(_ resolved: PiboSpeech) {
        let mood: PiboSpeechMood = switch resolved.presentation {
        case .normal, .story: .normal
        case .angry: .angry
        case .murmur: .murmur
        }
        show(PiboSpeechLine(
            text: resolved.text,
            mood: mood,
            isStoryClue: resolved.presentation == .story
        ))
    }

    private func speakForWeather(trigger: PiboSpeechTrigger) {
        guard !stagePaused,
              let weather = PiboSpeechWeather(rawValue: store.weather.rawValue),
              let line = piboSpeech.resolve(
                cues: [.weather(weather)],
                context: .home(trigger: trigger)
              )
        else { return }
        show(line)
    }

    /// Offers an idle speech opportunity every 15–30s. The app-wide resolver
    /// usually returns silence because it owns the daily budget and cooldown.
    private func idleMutterLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 15...30)))
            if speech == nil,
               sproutPhase == .idle,
               !stagePaused,
               let line = piboSpeech.resolve(
                cues: [.idle(activity: store.activityState.rawValue)],
                context: .home(trigger: .idle)
               ) {
                show(line)
            }
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

    private func presentMorningSleepIfPossible() {
        guard scenePhase == .active,
              activeSheet == nil,
              !fullScreenFeaturePresented,
              sproutPhase == .idle,
              // Re-validated at the moment of presentation, not when it was
              // queued: a card queued late at night must not surface as "last
              // night" after midnight, nor consume the wrong wake-day.
              let presentation = morningSleep.consumablePresentation()
        else { return }
        activeSheet = .morningSleep(presentation)
    }

    /// Resume whatever the just-dismissed modal was covering. The sleep card
    /// owns the wake-up moment, so it goes first; the 发芽 close-up follows once
    /// the screen is genuinely free.
    private func resumePendingHomeFlows() {
        presentMorningSleepIfPossible()
        presentStressCardIfPossible()
        maybeStartEnergyFlow()
    }

    /// Open the history surface on the 压力卡 after a stress notification tap.
    ///
    /// The request is a flag on `StressNotifier` rather than a direct present,
    /// because the tap can land at any moment — including a cold launch before
    /// this view exists, and while another cover is already up. Presenting over a
    /// live modal is silently dropped by SwiftUI, so when the screen is busy the
    /// flag simply stays raised and `resumePendingHomeFlows` retries from the next
    /// `onDismiss`.
    private func presentStressCardIfPossible() {
        guard stressNotifier.pendingCardOpen else { return }
        guard !fullScreenFeaturePresented, activeSheet == nil else { return }
        stressNotifier.pendingCardOpen = false
        historyFocus = .stress
        showHistory = true
    }

    private func startSoundscape() {
        soundscape.setEnabled(ambientSoundEnabled)
        soundscape.setPresentation(soundscapePresentation)
        soundscape.refreshExternalAudioSuppression()
        soundscape.apply(
            environment: stageEnvironment,
            date: atmosphereNow,
            petID: store.identity.currentPetId
        )
    }

    private func performReset() {
        Analytics.track(.reset, screen: "settings")
        piboSpeech.resetHistory()
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

private enum HomeSheetDestination: Equatable, Identifiable {
    case meal(MealType)
    case settings
    case morningSleep(MorningSleepPresentation)

    var id: String {
        switch self {
        case .meal(let meal): "meal-\(meal.rawValue)"
        case .settings: "settings"
        case .morningSleep(let presentation): "morning-sleep-\(presentation.id)"
        }
    }
}

#if DEBUG
private struct ForestTuningPanel: View {
    @Binding var tuning: StageRenderTuning
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
                value: $tuning.ambientMotionScale,
                range: 0...2
            )

            tuningSlider(
                title: "Pibo 草叶柔韧度",
                value: $tuning.headSproutFlexibility,
                range: 0...1
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
        let normalized = PiboStageEnvironmentResolver.normalizedHour(hour)
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
        .environment(PiboSpeechService())
        .environment(MorningSleepCoordinator())
        .environment(HistoryPreviewData.store)
}

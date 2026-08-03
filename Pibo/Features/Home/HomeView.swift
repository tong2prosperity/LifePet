import AVFAudio
import SwiftUI
import UIKit
import os

/// Pibo home — a fixed portrait SpriteKit forest. The scene never pans or
/// scrolls; SwiftUI owns the corner entries and the surrounding chrome.
///
/// The top-right icon grid enters 足迹历史页 and 设置. The old in-world studio/gym
/// entries and 上滑数据二楼 (`FloorModel` / `FloorContainer`) are retired.
/// 露珠相机 and 小游戏 remain implemented but are outside the 首发 range — their
/// entries are gated by `PiboReleaseScope` (see that file to restore them).
///
/// Pibo's state and the head-flower come straight off raw HealthKit + time of day
/// (see `PetStateStore+Mowan`).
struct HomeView: View {
    @Environment(PetStateStore.self) private var store
    @Environment(BoProgressFeedbackStore.self) private var boProgressFeedback
    @Environment(BoLedgerStore.self) private var boLedger
    @Environment(OrnamentUnlockStore.self) private var ornamentUnlocks
    @Environment(OrnamentLightStore.self) private var ornamentLights
    @Environment(HealthHistoryStore.self) private var history
    @Environment(PiboSpeechService.self) private var piboSpeech
    @Environment(MorningSleepCoordinator.self) private var morningSleep
    /// Carries the "user tapped a stress push" request from the notification
    /// router into this view (see `presentStressCardIfPossible`).
    @Environment(StressNotifier.self) private var stressNotifier
    @Environment(WeatherDataService.self) private var weather

    @Environment(\.scenePhase) private var scenePhase

    @State private var speech: PiboSpeechLine? = nil
    @State private var speechClear: Task<Void, Never>? = nil
    @State private var showCamera = false
    @State private var showGames = false
    @State private var showHistory = false
    @State private var showBoUnlockPage = false
    @State private var showSettings = false
    /// Card the history cover should land on. Set only by the stress-notification
    /// deep link; the 足迹 icon opens with `nil` (top of the 足迹 tab).
    @State private var historyFocus: HistoryFocus?

    @State private var showWalkDoodle = false
    @State private var activeSheet: HomeSheetDestination?
    /// `activeSheet` becomes nil at the start of dismissal, while its pixels are
    /// still covering Home. Badge feedback waits for the sheet's `onDismiss` so
    /// the first particle frame is never spent behind the confirmation UI.
    @State private var homeSheetDismissalInProgress = false
    #if DEBUG
    @State private var debugOpenedGames = false
    @State private var debugOpenedHistory = false
    @State private var debugWorkoutID: UUID?
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
    @State private var semanticAnimationStateID = PiboAnimationStateMap.fallback
    @State private var soundscape = AmbientSoundscapeService()
    #if DEBUG
    @State private var forestTuning: StageRenderTuning = .standard
    @State private var tuningPanelExpanded = !ProcessInfo.processInfo.arguments.contains("-PiboHideTuning")
    /// 面板强制的动画态。nil = 跟随 Core。`-PiboAnimationState=` 只是把它种上，
    /// 所以启动参数与面板走的是同一条覆盖路径。
    @State private var debugForcedAnimationStateID: String? = {
        guard let argument = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("-PiboAnimationState=")
        }) else { return nil }
        let value = String(argument.dropFirst("-PiboAnimationState=".count))
        return PiboAnimationStateMap.available.contains(value) ? value : nil
    }()
    /// Core 自己的判定，被面板覆盖时仍然显示出来 —— 走查时要能看出「Core 说
    /// default，我在强制 dive」。
    @State private var coreAnimationStateID = PiboAnimationStateMap.fallback
    @State private var debugBounceCutIntent = false
    @State private var debugPlaysAchievementCombo = false
    #else
    private let forestTuning: StageRenderTuning = .standard
    #endif
    @AppStorage(PiboPersistenceKeys.Defaults.onboardingDone) private var onboardingDone: Bool = false
    @AppStorage(PiboPersistenceKeys.Defaults.ambientSoundEnabled) private var ambientSoundEnabled = true

    /// Pause the 60fps stage loop while a feature covers it — the full-screen
    /// covers plus the two sheets (设置 / 餐食详情), which on iOS occlude the stage
    /// too (`MealDetailView` in particular can sit open a while during 卡路里 识别).
    private var stagePaused: Bool {
        showCamera || showGames || showHistory || showWalkDoodle || showBoUnlockPage || showSettings
            || activeSheet != nil
    }

    private var fullScreenFeaturePresented: Bool {
        showCamera || showGames || showHistory || showWalkDoodle || showBoUnlockPage || showSettings
    }

    private var boCounterFeedbackRequest: BoCounterFeedbackRequest? {
        BoCounterFeedbackRequest(
            feedID: store.feedToken,
            milestoneID: boProgressFeedback.pending?.id
        )
    }

    private var boCounterFeedbackEnabled: Bool {
        scenePhase == .active
            && !stagePaused
            && !homeSheetDismissalInProgress
            && sproutPhase == .idle
    }

    // 首发范围外的三张全屏功能页，呈现绑定统一过一遍 `PiboReleaseScope`。收在绑定
    // 上而不是只收在按钮上，是因为按钮不是唯一入口（重拍、启动参数、以后新加的
    // 任何一处赋值都会走这里），这样"关着"就不依赖调用方记得判断。
    private var cameraPresented: Binding<Bool> {
        Binding(get: { showCamera && PiboReleaseScope.camera }, set: { showCamera = $0 })
    }

    private var gamesPresented: Binding<Bool> {
        Binding(get: { showGames && PiboReleaseScope.miniGames }, set: { showGames = $0 })
    }

    private var walkDoodlePresented: Binding<Bool> {
        Binding(get: { showWalkDoodle && PiboReleaseScope.miniGames }, set: { showWalkDoodle = $0 })
    }

    private var stageEnvironment: PiboStageEnvironment {
        #if DEBUG
        let forcedHour = store.debugForestHour
        #else
        let forcedHour: Double? = nil
        #endif
        return PiboStageEnvironmentResolver.resolve(
            date: atmosphereNow,
            forcedHour: forcedHour,
            weather: weather.condition
        )
    }

    private var soundscapePresentation: SoundscapePresentation {
        guard scenePhase == .active else { return .suspended }
        if fullScreenFeaturePresented {
            return .suspended
        }
        switch activeSheet {
        case .meal, .morningSleep, .achievement: return .suspended
        case nil: return .active
        }
    }

    var body: some View {
        ZStack {
            PiboStageView(
                theme: store.currentTheme,
                state: store.activityState,
                animationStateID: semanticAnimationStateID,
                commandController: stageCommands,
                growth: store.growthStage,
                sproutGrowthProgress: store.headSproutGrowthProgress,
                environment: stageEnvironment,
                unlockedOrnaments: ornamentUnlocks.unlocked,
                litOrnamentLights: ornamentLights.lit,
                tuning: forestTuning,
                onPat: handlePat,
                onHairPulled: handleHairPull,
                onOrnamentLightTapped: handleOrnamentLightTap,
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
        .task(id: store.animationExperience.angryUntil) {
            guard let expiry = store.animationExperience.angryUntil else { return }
            let delay = max(0, expiry.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            refreshAnimationState(now: expiry)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            atmosphereNow = Date()
            refreshAnimationState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            atmosphereNow = Date()
            refreshAnimationState()
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
            weather.activateForHome()
            greetingText = store.mowanGreeting
            dayLabelText = store.relationshipDayLabel
            speakForWeather(trigger: .entered)
            refreshAnimationState()
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
            if PiboReleaseScope.miniGames, !debugOpenedGames,
               ProcessInfo.processInfo.arguments.contains("-PiboOpenGames") {
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
            if let argument = ProcessInfo.processInfo.arguments.first(where: {
                $0.hasPrefix("-PiboShowAchievement=")
            }), let kind = PiboAnimationAchievementKind(
                rawValue: String(argument.dropFirst("-PiboShowAchievement=".count))
            ) {
                let payload = PiboAnimationAchievementPayload(
                    id: UUID(),
                    kind: kind,
                    occurredAt: .now,
                    workoutLabel: kind == .pigu ? "跑步" : nil,
                    workoutDurationMinutes: kind == .pigu ? 30 : nil
                )
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard activeSheet == nil else { return }
                    activeSheet = .achievement(payload)
                }
            }
            if let argument = ProcessInfo.processInfo.arguments.first(where: {
                $0.hasPrefix("-PiboBounceTo=")
            }) {
                let target = String(argument.dropFirst("-PiboBounceTo=".count))
                if PiboAnimationStateMap.available.contains(target) {
                    Task {
                        // Deterministic Simulator capture hook. The delay leaves
                        // one stable source frame before the exact 710 ms cut.
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        semanticAnimationStateID = target
                        stageCommands.transitionAnimation(to: target, intent: .bounceCut)
                    }
                }
            }
            if let argument = ProcessInfo.processInfo.arguments.first(where: {
                $0.hasPrefix("-PiboSelectStateAfter=")
            }) {
                let target = String(argument.dropFirst("-PiboSelectStateAfter=".count))
                if PiboAnimationStateMap.available.contains(target) {
                    Task {
                        // 走查面板本身的抓帧钩子：模拟器合成不了点击，所以让这个
                        // 参数走面板那条完整选择路径（而不是直接写状态变量），
                        // 前后各截一帧就能证明「面板选中 → 舞台换态」是通的。
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        applyDebugAnimationState(target)
                    }
                }
            }
            if let argument = ProcessInfo.processInfo.arguments.first(where: {
                $0.hasPrefix("-PiboBoProgress=")
            }), let value = Int(argument.dropFirst("-PiboBoProgress=".count)),
               let milestone = BoProgressMilestone(rawValue: value) {
                boProgressFeedback.enqueue(milestone)
            }
            if ProcessInfo.processInfo.arguments.contains("-PiboOpenBoPanel") {
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    showBoUnlockPage = true
                }
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
            presentAchievementIfPossible()
            startSoundscape()
            presentMorningSleepIfPossible()
            presentStressCardIfPossible()
            if boLedger.hasRipeBo { announceFirstRipeBoIfNeeded() }
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
        .onChange(of: weather.condition) { _, _ in
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
        .onChange(of: animationRefreshToken) { oldValue, newValue in
            refreshAnimationState()
            let pendingChanged = oldValue.pendingAchievementID != newValue.pendingAchievementID
            let notificationRequested = oldValue.notificationPresentationRequestID
                != newValue.notificationPresentationRequestID
            if pendingChanged {
                reconcilePresentedAchievement()
            }
            if pendingChanged || notificationRequested {
                presentAchievementIfPossible()
            }
        }
        .onChange(of: morningSleep.pendingPresentation?.id) { _, _ in
            presentMorningSleepIfPossible()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshAnimationState()
                // 后台待了一夜的常见情形：回前台先对一次点灯日，不然昨晚的灯会
                // 因为「没人在场看着它熄」而继续亮着。
                ornamentLights.refresh()
                presentAchievementIfPossible()
                presentMorningSleepIfPossible()
            }
        }
        .onChange(of: stressNotifier.pendingCardOpen) { _, _ in
            presentStressCardIfPossible()
        }
        .onChange(of: boLedger.hasRipeBo) { _, isRipe in
            if isRipe { announceFirstRipeBoIfNeeded() }
        }
        .onChange(of: sproutPhase) { _, phase in
            if phase == .idle { resumePendingHomeFlows() }
        }
        // Every cover/sheet resumes queued flows from `onDismiss`, i.e. once the
        // dismissal animation has finished. Reacting to the presentation binding
        // instead would try to present while the previous modal is still on its
        // way out, which SwiftUI silently drops — leaving `activeSheet` non-nil
        // with nothing on screen and no way back.
        .fullScreenCover(isPresented: cameraPresented, onDismiss: resumePendingHomeFlows) {
            PiboCameraView(initialMeal: cameraInitialMeal, onPhotoSaved: { image, label, meal in
                handlePhotoSaved(image, label, meal: meal)
            }).environment(store)
        }
        .fullScreenCover(isPresented: gamesPresented, onDismiss: resumePendingHomeFlows) {
            GameListView(onWalkDoodleSaved: handleDoodleSaved)
                .environment(store)
                .environment(history)
        }
        .fullScreenCover(isPresented: $showHistory, onDismiss: historyDismissed) {
            HistoryScreen(focus: historyFocus)
                .environment(store)
                .environment(history)
        }
        .fullScreenCover(isPresented: walkDoodlePresented, onDismiss: resumePendingHomeFlows) {
            WalkDoodleView(onSaved: handleDoodleSaved)
        }
        .navigationDestination(isPresented: $showBoUnlockPage) {
            BoUnlockPage()
        }
        .navigationDestination(isPresented: $showSettings) {
            settingsDestination
        }
        .sheet(item: $activeSheet, onDismiss: resumePendingHomeFlows) { destination in
            homeSheet(destination)
        }
    }

    @ViewBuilder
    private var settingsDestination: some View {
        #if DEBUG
        SettingsView(
            onReset: performReset,
            onSimulateMeal: debugSimulateMeal,
            onSimulateWorkout: debugSimulateWorkout
        )
        #else
        SettingsView()
        #endif
    }

    private func historyDismissed() {
        historyFocus = nil
        resumePendingHomeFlows()
    }

    @ViewBuilder
    private func homeSheet(_ destination: HomeSheetDestination) -> some View {
        switch destination {
        case .meal(let meal):
            MealDetailView(meal: meal, onRecapture: startMealCapture)
                .environment(history)
                .environment(recognizer)
        case .morningSleep(let presentation):
            MorningSleepCard(
                presentation: presentation,
                appearance: store.appearance,
                weekly: SleepWeeklyReport.make(store: store, history: history)
            )
            .onAppear { morningSleep.markPresented(presentation) }
        case .achievement(let payload):
            PiboAchievementModal(payload: payload) { confirmAchievement(payload) }
                .interactiveDismissDisabled()
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
                    let scale = max(geo.size.width / 393, geo.size.height / 852)
                    let originY = (geo.size.height - 852 * scale) / 2
                    let bubbleBottom = originY + 317 * scale

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        PiboSpeechBubbleView(line: speech, onDetail: speech.data == nil ? nil : {
                            dismissSpeech()
                            Analytics.track(.historyOpen, screen: "home_speech")
                            showHistory = true
                        })
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                    .frame(width: geo.size.width, height: max(0, bubbleBottom))
                }
                .allowsHitTesting(speech.data != nil)
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
                        ),
                        forcedAnimationStateID: $debugForcedAnimationStateID,
                        coreAnimationStateID: coreAnimationStateID,
                        presentedAnimationStateID: semanticAnimationStateID,
                        usesBounceCut: $debugBounceCutIntent,
                        playsAchievementCombo: Binding(
                            get: { debugPlaysAchievementCombo },
                            set: {
                                debugPlaysAchievementCombo = $0
                                stageCommands.setPlaysAchievementCombo($0)
                            }
                        ),
                        onSelectAnimationState: applyDebugAnimationState,
                        onReplayAnimation: { stageCommands.replayAnimationIntro() }
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
                BoCounterView(
                    balance: boLedger.balance,
                    growthProgress: boLedger.growthProgress,
                    hasRipeBo: boLedger.hasRipeBo,
                    highlightsExchange: ornamentUnlocks.shouldHighlightUnlockGuide(
                        balance: boLedger.balance
                    ),
                    feedbackRequest: boCounterFeedbackRequest,
                    feedbackEnabled: boCounterFeedbackEnabled,
                    feedbackCompleted: { request in
                        if store.feedToken == request.feedID {
                            store.feedToken = nil
                        }
                        if let milestoneID = request.milestoneID {
                            boProgressFeedback.consume(id: milestoneID)
                        }
                    },
                    collectAction: {
                        dismissSpeech()
                        return doPluck()
                    }
                ) {
                    dismissSpeech()
                    Analytics.track(.boPanelOpen, screen: "home",
                                    ["balance": .int(boLedger.balance)])
                    showBoUnlockPage = true
                }
            }

            Spacer(minLength: 0)

            cornerActions
        }
        .padding(.top, LP.Spacing.s)
    }

    private var cornerActions: some View {
        HStack(spacing: LP.Spacing.s) {
            if PiboReleaseScope.camera {
                cornerButton(systemImage: "camera.fill", label: "露珠相机", rotation: -2) {
                    Analytics.track(.cameraOpen, screen: "home", ["meal": .string("none")])
                    cameraInitialMeal = nil
                    showCamera = true
                }
            }
            cornerButton(systemImage: "gearshape", label: "设置", rotation: 0, size: 36) {
                Analytics.track(.settingsOpen, screen: "home")
                showSettings = true
            }
        }
    }

    private func cornerButton(
        systemImage: String,
        label: String,
        rotation: Double,
        size: CGFloat = 44,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            LPHaptics.tap()
            dismissSpeech()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LP.Content.secondary)
                .frame(width: size, height: size)
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
        ZStack(alignment: .bottom) {
            if boLedger.hasRipeBo {
                pluckButton
            }
            HStack {
                Spacer(minLength: 0)
                historyButton
            }
        }
        .padding(.bottom, LP.Spacing.l)
    }

    private var historyButton: some View {
        Button {
            LPHaptics.tap()
            dismissSpeech()
            Analytics.track(.historyOpen, screen: "home")
            showHistory = true
        } label: {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(hex: 0x006650))
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LP.Colorful.teal500)
                    .frame(height: 64)
                Image(systemName: "list.bullet")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Color.white)
                    .padding(.top, 16)
            }
            .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("足迹"))
    }

    private var pluckButton: some View {
        Button {
            LPHaptics.tap()
            dismissSpeech()
            doPluck()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill").font(.system(size: 12))
                Text(AppLocalization.text("收下长好的毛"))
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
        let now = Date()
        let hour = localHour(at: now)
        let sourceStateID = semanticAnimationStateID
        let enteredAngry = store.animationExperience.registerActualPat(localHour: hour, now: now)
        refreshAnimationState(now: now)
        let targetStateID = semanticAnimationStateID
        if targetStateID != sourceStateID {
            let intent = PiboCoreAnimationAdapter.transitionIntent(
                fromStateID: sourceStateID,
                toStateID: targetStateID,
                angryEntered: enteredAngry
            )
            stageCommands.transitionAnimation(to: targetStateID, intent: intent)
        }
        if let contentID = PiboCoreAnimationAdapter.patContentID(
            stateID: semanticAnimationStateID,
            angryEntered: enteredAngry
        ), let line = animationPatLine(contentID, angry: enteredAngry) {
            show(line)
            Analytics.track(.pat, screen: "home", ["reaction": .string(contentID)])
            return
        }
        let response = store.pat()
        if response.turnsAway { stageCommands.playTurnAway() }
        if let line = response.line { show(patLineWithData(line)) }
        let reaction = response.line.map { $0.isStoryClue ? "story" : "spoke" } ?? "ignored"
        Analytics.track(.pat, screen: "home", ["reaction": .string(reaction)])
    }

    /// 拖毛 released past the pull threshold. 毛熟了的时候这就是拔毛；没熟的时候
    /// Pibo 只是不喜欢被扯，扭头了事。
    private func handleHairPull() {
        LPHaptics.tap()
        if boLedger.hasRipeBo {
            doPluck()
        } else {
            stageCommands.playTurnAway()
        }
    }

    /// 点亮铃兰灯的一盏铃铛。
    ///
    /// **不给任何回报** —— 不加 bo、不加能量、不解锁、不推进故事。决定 013 写死了
    /// 这条边界，而「点一下灯」正是最容易被顺手挂上奖励的那种交互。这里只有一次
    /// 触觉反馈和一条打点。
    ///
    /// 也没有「点灭」的分支：灯只能点亮，天亮自己熄。
    private func handleOrnamentLightTap(_ id: PiboOrnament.ID, index: Int) {
        guard ornamentLights.light(id, index: index) else { return }
        LPHaptics.tap()
        Analytics.track(.ornamentLight, screen: "home",
                        ["ornament": .string(id.rawValue), "index": .int(index)])
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
        // 发芽只讲「收集到能量」。运动完成的成果表演归成果卡片，`pigu` 不在主场景
        // 出现 —— 这里曾经接着演一遍首页剧本，等于同一件事演两次。
        store.consumePendingWorkout()
        setSproutPhase(.idle)
    }

    private func setSproutPhase(_ phase: SproutFlowPhase) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) { sproutPhase = phase }
    }

    // MARK: 拔毛 / 拍照

    @discardableResult
    private func doPluck() -> Bool {
        // 账本先落，动画后播 —— 反过来的话，一次没成功的拔取会先演一遍收获。
        guard boLedger.pluck() else { return false }
        let grade = store.pluck()
        Analytics.track(.pluck, screen: "home",
                        ["grade": .string(grade.rawValue),
                         "balance": .int(boLedger.balance)])
        stageCommands.playPluck(color: grade.seedColor)
        show(PiboSpeechLine(text: grade.piboLines.randomElement() ?? "...给...你..."))
        return true
    }

    /// Open the camera for a specific meal slot (早/中/晚) — the saved photo goes
    /// to the backend for 卡路里 recognition and its detail modal pops up.
    /// Guarded because 重拍 is a second door into the camera; with the feature out
    /// of 首发 range there must be no way in at all.
    private func startMealCapture(_ meal: MealType) {
        guard PiboReleaseScope.camera else { return }
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

    /// Adds a directly observed HealthKit fact to ordinary pat speech. This is
    /// presentation-only: Core still decides whether Pibo speaks and which line
    /// it uses; no activity threshold or state rule is duplicated here.
    private func patLineWithData(_ line: PiboSpeechLine) -> PiboSpeechLine {
        guard line.source == .pibo, line.mood == .normal, !line.isStoryClue else {
            return line
        }
        var presented = line
        if store.hasStepsData, store.rawSteps > 0 {
            presented.data = PiboSpeechData(
                prefix: AppLocalization.text("你今天走了 "),
                value: AppLocalization.format("%d 步", store.rawSteps),
                suffix: AppLocalization.text("。")
            )
        } else if store.rawSleepHours > 0 {
            presented.data = PiboSpeechData(
                prefix: AppLocalization.text("你昨晚睡了 "),
                value: String(format: "%.1f %@", store.rawSleepHours, AppLocalization.text("小时")),
                suffix: AppLocalization.text("。")
            )
        }
        return presented
    }

    private func dismissSpeech() {
        speechClear?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { speech = nil }
    }

    private func show(_ line: PiboSpeechLine) {
        speechClear?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { speech = line }
        // A system notice is a full sentence rather than a garbled fragment, so
        // it holds a beat longer than ordinary speech.
        let linger: Double = if line.data != nil {
            5.0
        } else if line.source == .system {
            3.0
        } else if line.mood == .murmur || line.isStoryClue {
            3.4
        } else {
            2.0
        }
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
              let weather = PiboSpeechWeather(rawValue: weather.condition.rawValue),
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
            if !Task.isCancelled {
                atmosphereNow = Date()
                refreshAnimationState()
                // 每分钟一次正好是「有没有跨过天亮」需要的精度。灯是否该熄
                // 由存储自己判断，这里重复调用是廉价的。
                ornamentLights.refresh(now: atmosphereNow)
            }
        }
    }

    #if DEBUG
    /// 面板选中一个状态（nil = 交还给 Core）。
    ///
    /// 走的是业务同一条路径：先写状态变量让下一次 `apply(...)` 生效；要看 Q 弹
    /// 时紧接着发命令 —— 命令会先把渲染器的 `animationStateID` 写掉，随后那次
    /// `apply` 自然成为 no-op，不会双切。顺序与 `handlePat()` 一致。
    private func applyDebugAnimationState(_ stateID: String?) {
        let previous = semanticAnimationStateID
        debugForcedAnimationStateID = stateID
        refreshAnimationState()
        let target = semanticAnimationStateID
        guard debugBounceCutIntent, target != previous else { return }
        stageCommands.transitionAnimation(to: target, intent: .bounceCut)
    }
    #endif

    private func refreshAnimationState(now: Date = .now) {
        let experience = store.animationExperience
        experience.refreshExpiries(now: now)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let historyStart = calendar.date(byAdding: .day, value: -40, to: today) ?? today
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let sleepHistory = history.records(from: historyStart, to: yesterday)
            .map(\.sleepTotal)
            .filter { $0 > 0 }
            .suffix(28)
            .map { $0 / 3600 }
        let sleepReference = PiboCoreAnimationAdapter.sleepReference(history: Array(sleepHistory))
        let baseline = store.stressBaseline
        let z = store.rmssd.flatMap { value in baseline.map { $0.z(for: value) } } ?? 0
        let rmssdAge = store.rmssdMeasuredAt.map { max(0, now.timeIntervalSince($0)) }
            ?? .greatestFiniteMagnitude
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let dayKey = Int64((components.year ?? 0) * 10_000 + (components.month ?? 0) * 100 + (components.day ?? 0))

        var decided = PiboCoreAnimationAdapter.completeAmbientStateID(
            localHour: localHour(at: now),
            hasSleepData: store.rawSleepHours > 0,
            sleepHours: store.rawSleepHours,
            sleepReferenceHours: sleepReference.hours,
            hasActivityData: store.hasStepsData,
            steps: store.rawSteps,
            hasWorkoutToday: store.hasWorkoutToday,
            postPluckSleep: store.pluckSleepUntil.map { $0 > now } ?? false,
            sleepDayKey: dayKey,
            angryActive: experience.angryActive(at: now),
            hasEligibleRMSSD: store.rmssd != nil && baseline != nil,
            stressBaselineDays: baseline?.dayCount ?? 0,
            stressZ: z,
            rmssdAgeSeconds: rmssdAge,
            previousStressStateID: experience.previousStressStateID
        )
        experience.previousStressStateID = PiboCoreAnimationAdapter.nextStressMemoryStateID(
            decidedStateID: decided,
            previousStressStateID: experience.previousStressStateID
        )
        decided = PiboCoreAnimationAdapter.stateIDByApplyingAchievementHold(
            to: decided,
            held: experience.heldAchievement
        )
        #if DEBUG
        coreAnimationStateID = decided
        // 覆盖必须落在这里：前台对账 / HealthKit 更新 / 整点定时都会重跑本函数，
        // 写在别处会被下一次刷新冲掉。
        if let forced = debugForcedAnimationStateID,
           PiboAnimationStateMap.available.contains(forced) {
            decided = forced
        }
        #endif
        semanticAnimationStateID = decided
    }

    private var animationRefreshToken: AnimationRefreshToken {
        AnimationRefreshToken(
            steps: store.rawSteps,
            sleepHours: store.rawSleepHours,
            hasWorkout: store.hasWorkoutToday,
            rmssd: store.rmssd,
            historyRevision: history.revision,
            pendingAchievementID: store.animationExperience.pendingAchievement?.id,
            notificationPresentationRequestID: store.animationExperience
                .notificationPresentationRequestID
        )
    }

    private func localHour(at date: Date) -> Double {
        let values = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return Double(values.hour ?? 0)
            + Double(values.minute ?? 0) / 60
            + Double(values.second ?? 0) / 3_600
    }

    private func presentAchievementIfPossible() {
        guard scenePhase == .active,
              activeSheet == nil,
              !fullScreenFeaturePresented,
              PiboCoreAnimationAdapter.achievementPresentationAllowed(
                  in: semanticAnimationStateID
              ),
              let payload = store.animationExperience.pendingAchievement
        else { return }
        activeSheet = .achievement(payload)
    }

    /// HealthKit can deliver a newer workout while an achievement sheet is
    /// already visible. Keep the sheet bound to the replaceable pending slot;
    /// otherwise its Confirm button targets an obsolete UUID and becomes an
    /// undismissable no-op because interactive dismissal is disabled.
    private func reconcilePresentedAchievement() {
        guard case .achievement(let presented) = activeSheet else { return }
        guard let latest = store.animationExperience.pendingAchievement else {
            activeSheet = nil
            return
        }
        if latest.id != presented.id {
            activeSheet = .achievement(latest)
        }
    }

    private func confirmAchievement(_ payload: PiboAnimationAchievementPayload) {
        #if DEBUG
        if store.animationExperience.pendingAchievement?.id != payload.id,
           ProcessInfo.processInfo.arguments.contains(where: {
               $0.hasPrefix("-PiboShowAchievement=")
           }) {
            activeSheet = nil
            return
        }
        #endif
        guard store.animationExperience.pendingAchievement?.id == payload.id else { return }
        _ = store.animationExperience.confirmPending()
        if payload.kind == .pigu, store.pendingWorkout?.id == payload.id {
            store.consumePendingWorkout()
        }
        #if DEBUG
        if debugWorkoutID == payload.id {
            boLedger.debugApplyWorkout(durationMinutes: payload.workoutDurationMinutes ?? 24)
            debugWorkoutID = nil
        }
        #endif
        refreshAnimationState()
        homeSheetDismissalInProgress = true
        activeSheet = nil
    }

    /// The bubble a pat earns while Core has authored content for the current
    /// pose. `sleep` is deliberately **not** a line of Pibo's: asleep it cannot
    /// answer, so the app posts a system notice instead of putting words in a
    /// sleeping character's mouth.
    private func animationPatLine(_ contentID: String, angry: Bool) -> PiboSpeechLine? {
        switch contentID {
        case "animation.sleep.pat":
            .system(AppLocalization.text("Pibo 设置了请勿打扰"))
        case "animation.awake.pat":
            PiboSpeechLine(text: AppLocalization.text("我刚醒。让我再待一会儿。"),
                           mood: angry ? .angry : .normal)
        case "animation.angry.enter":
            PiboSpeechLine(text: AppLocalization.text("三次了。我需要安静一会儿。"),
                           mood: angry ? .angry : .normal)
        default:
            nil
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
        homeSheetDismissalInProgress = false
        presentAchievementIfPossible()
        guard activeSheet == nil else { return }
        presentMorningSleepIfPossible()
        presentStressCardIfPossible()
    }

    /// 首枚 `bo` 长熟时讲一次规则，之后再不打扰。
    ///
    /// 「熟了就能拔，拔不拔随你，但不拔就不会长新的」这条规则用户不可能自己猜到，
    /// 所以必须讲一次；讲完就闭嘴 —— 每天催一遍就变成了决定 027 明确不要的那种
    /// 施压。同一个一次性标志位同时把守气泡和通知。
    private func announceFirstRipeBoIfNeeded() {
        let key = PiboPersistenceKeys.Defaults.boFirstRipeNotified
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        show(PiboSpeechLine(text: AppLocalization.text("...长好了...要收就收...不收...就不长新的...")))
        Task { await WorkoutCompletionNotifier.shared.notifyFirstBoRipened() }
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
        // 重置也要清账本和已解锁物件，否则「重置」之后左上角还挂着上一轮的余额，
        // 森林里还挂着上一轮换来的灯。起始日重新以今天起算。
        boLedger.reset()
        ornamentUnlocks.reset()
        ornamentLights.reset()
        UserDefaults.standard.removeObject(
            forKey: PiboPersistenceKeys.Defaults.boFirstRipeNotified
        )
        onboardingDone = false
    }

#if DEBUG
    /// Close Settings first so Home is visible when the real workout event is
    /// injected. Waiting for the navigation pop avoids queuing the modal behind
    /// an off-screen destination and makes the one-tap rehearsal deterministic.
    private func debugSimulateWorkout() {
        showSettings = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            debugWorkoutID = store.debugInjectWorkout()
        }
    }

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
    case morningSleep(MorningSleepPresentation)
    case achievement(PiboAnimationAchievementPayload)

    var id: String {
        switch self {
        case .meal(let meal): "meal-\(meal.rawValue)"
        case .morningSleep(let presentation): "morning-sleep-\(presentation.id)"
        case .achievement(let payload): "animation-achievement-\(payload.id)"
        }
    }
}

private struct AnimationRefreshToken: Equatable {
    let steps: Int
    let sleepHours: Double
    let hasWorkout: Bool
    let rmssd: Double?
    let historyRevision: Int
    let pendingAchievementID: UUID?
    let notificationPresentationRequestID: UUID?
}

#if DEBUG
private struct ForestTuningPanel: View {
    @Binding var tuning: StageRenderTuning
    @Binding var isExpanded: Bool
    @Binding var forcedHour: Double?
    @Binding var forcedAnimationStateID: String?
    let coreAnimationStateID: String
    let presentedAnimationStateID: String
    @Binding var usesBounceCut: Bool
    @Binding var playsAchievementCombo: Bool
    let onSelectAnimationState: (String?) -> Void
    let onReplayAnimation: () -> Void
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
                    usesBounceCut = false
                    playsAchievementCombo = false
                    onSelectAnimationState(nil)
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

            ScrollView {
                VStack(alignment: .leading, spacing: LP.Spacing.s) {
                    Toggle("隐藏 Pibo", isOn: Binding(
                        get: { !tuning.piboVisible },
                        set: { tuning.piboVisible = !$0 }
                    ))
                    .lpText(LP.Typography.c1Regular)
                    .tint(LP.Fill.foundationAccent)

                    animationStateControl

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
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 470)
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

    /// 动画态走查：切状态、看 Core 判定、看这一态的连招由什么组成、重播登场。
    private var animationStateControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: LP.Spacing.s) {
                Text("Pibo 动画态")
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.secondary)
                Spacer(minLength: 0)
                Text(forcedAnimationStateID == nil ? "跟随 Core" : "已强制")
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.tertiary)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
                spacing: 4
            ) {
                animationStateChip("Core", stateID: nil)
                // 白名单是唯一来源，多一态少一态面板自动跟。
                ForEach(PiboAnimationStateMap.available.sorted(), id: \.self) { stateID in
                    animationStateChip(shortStateLabel(stateID), stateID: stateID)
                }
            }

            Text("Core：\(coreAnimationStateID) · 在演：\(presentedAnimationStateID)")
                .lpText(LP.Typography.c2Regular)
                .foregroundStyle(LP.Content.tertiary)
                .monospacedDigit()

            Text(idleComposition(of: presentedAnimationStateID))
                .lpText(LP.Typography.c2Regular)
                .foregroundStyle(LP.Content.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                intentButton("硬切", bounce: false)
                intentButton("Q 弹", bounce: true)
            }

            Button {
                LPHaptics.tap()
                onReplayAnimation()
            } label: {
                Label("重播登场 / 连招", systemImage: "arrow.clockwise")
                    .lpText(LP.Typography.c2Medium)
                    .foregroundStyle(LP.Content.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Capsule().fill(LP.Fill.bgSurfaceSecondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("从头重播当前状态的登场与连招")

            Toggle("成果态演完整连招", isOn: $playsAchievementCombo)
                .lpText(LP.Typography.c1Regular)
                .tint(LP.Fill.foundationAccent)
                .disabled(!isAchievementState(presentedAnimationStateID))
                .accessibilityHint("关闭时首页只跑设计的保持呼吸")
        }
    }

    private func animationStateChip(_ title: String, stateID: String?) -> some View {
        let isSelected = forcedAnimationStateID == stateID
        return Button {
            guard !isSelected else { return }
            LPHaptics.tap()
            onSelectAnimationState(stateID)
        } label: {
            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? LP.Fill.foundationOnAccent : LP.Content.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(
                    Capsule().fill(isSelected ? LP.Fill.foundationAccent : LP.Fill.bgSurfaceSecondary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stateID ?? "跟随 Core 判定")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func intentButton(_ title: String, bounce: Bool) -> some View {
        let isSelected = usesBounceCut == bounce
        return Button {
            guard !isSelected else { return }
            LPHaptics.tap()
            usesBounceCut = bounce
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
        .accessibilityLabel(bounce ? "下一次切换走 Q 弹" : "下一次切换走硬切")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 睡眠三态的 ID 太长，四列放不下。
    private func shortStateLabel(_ stateID: String) -> String {
        stateID.replacingOccurrences(of: "sleep-", with: "睡")
    }

    private func isAchievementState(_ stateID: String) -> Bool {
        PiboAnimationStateMap.holdIdle(for: stateID) != nil
    }

    /// 这一态的连招由哪些原语、多长的门控周期组成 —— 直接读运行时数据，
    /// 面板不复述一份。
    private func idleComposition(of stateID: String) -> String {
        guard let idle = PiboCharacterData.shared?.states[stateID]?.idle else {
            return "无待机数据"
        }
        let parts = idle.resolvedParts
        let cycle = parts.compactMap(\.gateCycle).max()
        var summary = "\(parts.count) 段"
        if let cycle { summary += " · 时间轴 \(String(format: "%.1f", cycle))s" }
        if let intro = idle.intro {
            summary += " · 登场 \(String(format: "%.2f", intro.duration))s"
        }
        let kinds = parts.map(\.kind).reduce(into: [String]()) { unique, kind in
            if !unique.contains(kind) { unique.append(kind) }
        }
        return summary + "\n" + kinds.joined(separator: " · ")
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
        .environment(WeatherDataService())
}

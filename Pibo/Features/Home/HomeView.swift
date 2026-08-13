import AVFAudio
import PiboCore
import SwiftUI
import UIKit
import os

/// Pibo home — a fixed portrait SpriteKit forest. The scene never pans or
/// scrolls; SwiftUI owns the corner entries and the surrounding chrome.
///
/// The top-right icon grid enters 足迹历史页 and 设置. The old in-world studio/gym
/// entries and 上滑数据二楼 (`FloorModel` / `FloorContainer`) are retired.
/// 餐食相机与 Walk Doodle 属于首发；其他小游戏仍由 `PiboReleaseScope` 收起。
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
    @Environment(OnboardingStateStore.self) private var onboarding
    @Environment(MorningSleepCoordinator.self) private var morningSleep
    /// Carries the "user tapped a stress push" request from the notification
    /// router into this view (see `presentStressCardIfPossible`).
    @Environment(StressNotifier.self) private var stressNotifier
    @Environment(WeatherDataService.self) private var weather

    @Environment(\.scenePhase) private var scenePhase

    @State private var speechPresentation = HomeSpeechPresentationController()
    @State private var featurePresentation = HomeFeaturePresentationState()
    @State private var showBoUnlockPage = false
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
    @State private var recognizer = FoodRecognitionService()
    @State private var stageCommands = PiboStageCommandController()
    /// 发芽 close-up trigger + phase (Figma 74:6102: workout detected → 特写
    /// pibo头顶动画 → 运动记录同步 pop). See `EnergySproutFlow.swift`.
    @State private var sproutFlow = HomeSproutFlowController()
    /// Greeting / day-label cached once (they're "drawn once per day").
    @State private var greetingText: String = ""
    @State private var dayLabelText: String = ""
    @State private var atmosphereClock = HomeAtmosphereClock()
    @State private var animationPresentation = HomeAnimationPresentationController()
    @State private var soundscape = AmbientSoundscapeService()
    #if DEBUG
    @State private var forestTuning: StageRenderTuning = .standard
    @State private var tuningPanelExpanded = !HomeDebugLaunchOptions.current.hidesTuningPanel
    /// 面板强制的动画态。nil = 跟随 Core。`-PiboAnimationState=` 只是把它种上，
    /// 所以启动参数与面板走的是同一条覆盖路径。
    @State private var debugBounceCutIntent = false
    @State private var debugPlaysAchievementCombo = false
    #else
    private let forestTuning: StageRenderTuning = .standard
    #endif
    @AppStorage(PiboPersistenceKeys.Defaults.ambientSoundEnabled) private var ambientSoundEnabled = true

    private var semanticAnimationStateID: String {
        animationPresentation.stateID
    }

    private var sproutPhase: SproutFlowPhase {
        sproutFlow.phase
    }

    private var presentationPolicy: HomePresentationPolicy {
        HomePresentationPolicy(
            sceneIsActive: scenePhase == .active,
            cameraPresented: featurePresentation.showCamera,
            gamesPresented: featurePresentation.showGames,
            historyPresented: featurePresentation.showHistory,
            walkDoodlePresented: featurePresentation.showWalkDoodle,
            settingsPresented: featurePresentation.showSettings,
            storyRecoveryPresented: featurePresentation.showStoryRecovery,
            sheetPresented: activeSheet != nil,
            sheetDismissalInProgress: homeSheetDismissalInProgress,
            sproutFlowIsIdle: sproutPhase == .idle
        )
    }

    private var stagePaused: Bool {
        presentationPolicy.stagePaused
    }

    private var fullScreenFeaturePresented: Bool {
        presentationPolicy.fullScreenFeaturePresented
    }

    private var boCounterFeedbackEnabled: Bool {
        presentationPolicy.boCounterFeedbackEnabled
    }

    private var storySpeechStage: PiboCoreStorySpeechStage {
        guard PiboReleaseScope.temporaryCooperationOnboarding else {
            return .unresponded
        }
        return onboarding.eventProjection().speechStage
    }

    private var homeSpeechFacts: PiboHomeSpeechFacts {
        HomeSpeechInputResolver.facts(
            hasStepsData: store.hasStepsData,
            rawSteps: store.rawSteps,
            rawSleepHours: store.rawSleepHours,
            hasWorkoutToday: store.hasWorkoutToday,
            pendingBoCount: boLedger.state.ripeCount,
            cooperationEnabled: PiboReleaseScope.temporaryCooperationOnboarding,
            connectionAccepted: onboarding.snapshot.connection == .accepted
        )
    }

    private var homeSpeechValues: [String: String] {
        HomeSpeechInputResolver.values(
            hasStepsData: store.hasStepsData,
            rawSteps: store.rawSteps,
            rawSleepHours: store.rawSleepHours,
            sleepDurationUnit: AppLocalization.text("小时")
        )
    }

    private var idleSpeechContext: PiboCoreHomeSpeechContext? {
        HomeIdleSpeechContextResolver.resolve(
            animationStateID: semanticAnimationStateID,
            wakingSleptEnough: store.wakingSleptEnough,
            hasRealHealthData: store.hasRealHealthData
        )
    }

    // 可选全屏功能页的呈现绑定统一过一遍 `PiboReleaseScope`。收在绑定
    // 上而不是只收在按钮上，是因为按钮不是唯一入口（重拍、启动参数、以后新加的
    // 任何一处赋值都会走这里），这样"关着"就不依赖调用方记得判断。
    private var cameraPresented: Binding<Bool> {
        featurePresentation.cameraBinding(isEnabled: canUseDewCamera)
    }

    private var gamesPresented: Binding<Bool> {
        featurePresentation.gamesBinding(isEnabled: PiboReleaseScope.miniGames)
    }

    private var walkDoodlePresented: Binding<Bool> {
        featurePresentation.walkDoodleBinding(isEnabled: canUseWalkDoodle)
    }

    private var canUseDewCamera: Bool {
        PiboReleaseScope.camera && ornamentUnlocks.grants(.dewCamera)
    }

    private var canUseWalkDoodle: Bool {
        PiboReleaseScope.walkDoodle && ornamentUnlocks.grants(.walkDoodle)
    }

    private var stageEnvironment: PiboStageEnvironment {
        #if DEBUG
        let forcedHour = store.debugForestHour
        #else
        let forcedHour: Double? = nil
        #endif
        return PiboStageEnvironmentResolver.resolve(
            date: atmosphereClock.now,
            forcedHour: forcedHour,
            weather: weather.condition
        )
    }

    private var soundscapePresentation: SoundscapePresentation {
        presentationPolicy.soundscapePresentation
    }

    private var homeScene: some View {
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
                onOrnamentTapped: handleOrnamentTap,
                isPaused: stagePaused,
                isObscured: showBoUnlockPage
            )
            .equatable()
            .ignoresSafeArea()
            .allowsHitTesting(!showBoUnlockPage)
            .accessibilityHidden(stagePaused || showBoUnlockPage)

            chromeContent
                .allowsHitTesting(!showBoUnlockPage)
                .accessibilityHidden(stagePaused || showBoUnlockPage)

            if shouldShowStoryRecoveryBanner {
                VStack {
                    storyRecoveryBanner
                    Spacer()
                }
                .padding(.horizontal, LP.Spacing.l)
                .padding(.top, 108)
            }

            // 发芽 close-up captions, synced to the stage phases.
            if sproutPhase == .collecting || sproutPhase == .sprouted {
                VStack(spacing: 0) {
                    SproutCaptionView(text: sproutPhase == .collecting
                                      ? "收到一条新的运动记录"
                                      : "Pibo 记下了这次变化")
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            // 运动记录同步 pop — back on the home floor (Figma 70:4549).
            if sproutPhase == .pop {
                EnergyCollectedPop(onDismiss: dismissEnergyPop)
            }

            if showBoUnlockPage {
                BoUnlockOverlay(stageCommands: stageCommands) {
                    showBoUnlockPage = false
                    resumePendingHomeFlows()
                }
                .transition(.opacity)
                .zIndex(100)
            }

        }
    }

    private var homeTaskContent: some View {
        homeScene
        .accessibilityHidden(stagePaused)
        .task { await idleMutterLoop() }
        .task {
            await atmosphereClock.run { now in
                refreshAnimationState()
                // 每分钟一次正好是「有没有跨过天亮」需要的精度。灯是否该熄
                // 由存储自己判断，这里重复调用是廉价的。
                ornamentLights.refresh(now: now)
            }
        }
        .task(id: store.animationExperience.angryUntil) {
            guard let expiry = store.animationExperience.angryUntil else { return }
            let delay = max(0, expiry.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            refreshAnimationState(now: expiry)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            atmosphereClock.refresh()
            refreshAnimationState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            atmosphereClock.refresh()
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
    }

    private var homeLifecycleContent: some View {
        homeTaskContent
        .onAppear {
            weather.activateForHome()
            greetingText = store.mowanGreeting
            dayLabelText = store.relationshipDayLabel
            speakForWeather(trigger: .entered)
            refreshAnimationState()
            #if DEBUG
            runDebugLaunchAutomation()
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
                date: atmosphereClock.now,
                petID: store.identity.currentPetId
            )
        }
        .onChange(of: weather.condition) { _, _ in
            speakForWeather(trigger: .environmentChanged)
        }
        .onChange(of: store.identity.currentPetId) { _, petID in
            soundscape.apply(
                environment: stageEnvironment,
                date: atmosphereClock.now,
                petID: petID
            )
        }
        .onChange(of: ambientSoundEnabled) { _, enabled in
            soundscape.setEnabled(enabled)
        }
        .onChange(of: soundscapePresentation) { _, presentation in
            soundscape.setPresentation(presentation)
        }
    }

    private var homeStateObservationContent: some View {
        homeLifecycleContent
        .onChange(of: animationRefreshToken) { oldValue, newValue in
            refreshAnimationState()
            let changes = newValue.achievementChanges(from: oldValue)
            if changes.pendingAchievementChanged {
                reconcilePresentedAchievement()
            }
            if changes.shouldAttemptPresentation {
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
        .onChange(of: semanticAnimationStateID) { _, _ in
            if boLedger.hasRipeBo { announceFirstRipeBoIfNeeded() }
        }
        .onChange(of: sproutPhase) { _, phase in
            if phase == .idle { resumePendingHomeFlows() }
        }
    }

    private var homeWithoutSheet: some View {
        homeStateObservationContent
        // Every cover/sheet resumes queued flows from `onDismiss`, i.e. once the
        // dismissal animation has finished. Reacting to the presentation binding
        // instead would try to present while the previous modal is still on its
        // way out, which SwiftUI silently drops — leaving `activeSheet` non-nil
        // with nothing on screen and no way back.
        .fullScreenCover(isPresented: cameraPresented, onDismiss: resumePendingHomeFlows) {
            PiboCameraView(
                initialMeal: featurePresentation.cameraInitialMeal,
                onPhotoSaved: { image, label, meal in
                    handlePhotoSaved(image, label, meal: meal)
                }
            )
            .environment(store)
        }
        .fullScreenCover(isPresented: gamesPresented, onDismiss: resumePendingHomeFlows) {
            GameListView(
                walkDoodleEnabled: canUseWalkDoodle,
                onWalkDoodleSaved: handleDoodleSaved
            )
                .environment(store)
                .environment(history)
        }
        .fullScreenCover(
            isPresented: featurePresentation.historyBinding,
            onDismiss: historyDismissed
        ) {
            HistoryScreen(focus: featurePresentation.historyFocus)
                .environment(store)
                .environment(history)
        }
        .fullScreenCover(isPresented: featurePresentation.storyRecoveryBinding) {
            HealthAuthView(mode: .storyRecovery) {
                featurePresentation.showStoryRecovery = false
                featurePresentation.storyRecoveryDismissed = true
            }
        }
        .fullScreenCover(isPresented: walkDoodlePresented, onDismiss: resumePendingHomeFlows) {
            WalkDoodleView(onSaved: handleDoodleSaved)
        }
        .navigationDestination(isPresented: featurePresentation.settingsBinding) {
            settingsDestination
        }
    }

    var body: some View {
        homeWithoutSheet
        .sheet(item: $activeSheet, onDismiss: resumePendingHomeFlows) { destination in
            homeSheet(destination)
        }
    }

    private var shouldShowStoryRecoveryBanner: Bool {
        HomeStoryRecoveryPolicy.shouldShow(
            featureEnabled: PiboReleaseScope.temporaryCooperationOnboarding,
            needsRecovery: onboarding.needsStoryRecovery,
            dismissed: featurePresentation.storyRecoveryDismissed
        ) {
            #if DEBUG
            return true
            #else
            let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
            return day.isMultiple(of: 3)
            #endif
        }
    }

    private var storyRecoveryBanner: some View {
        HomeStoryRecoveryBanner(
            messageKey: onboarding.recoveryMessageKey,
            actionKey: onboarding.recoveryActionKey,
            onOpen: {
                Analytics.track(.storyRecoveryOpened, screen: "home")
                featurePresentation.showStoryRecovery = true
            },
            onDismiss: {
                featurePresentation.storyRecoveryDismissed = true
            }
        )
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
        featurePresentation.historyFocus = nil
        resumePendingHomeFlows()
    }

    @ViewBuilder
    private func homeSheet(_ destination: HomeSheetDestination) -> some View {
        switch destination {
        case .meal(let meal):
            MealDetailView(meal: meal, onRecapture: startMealCapture)
                .environment(history)
                .environment(recognizer)
        case .morningSleep(let presentation, let consumesPending):
            MorningSleepCard(
                presentation: presentation,
                appearance: store.appearance,
                weekly: SleepWeeklyReport.make(store: store, history: history)
            )
            .onAppear {
                if consumesPending { morningSleep.markPresented(presentation) }
            }
        case .commonItemStatus(let model):
            CommonItemStatusModal(
                ornamentID: model.ornamentID,
                title: model.title,
                status: model.status,
                message: model.message
            )
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
            if let speech = speechPresentation.line {
                HomeSpeechOverlay.make(line: speech) {
                    dismissSpeech()
                    Analytics.track(.historyOpen, screen: "home_speech")
                    featurePresentation.showHistory = true
                }
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
                        forcedAnimationStateID: Binding(
                            get: { animationPresentation.forcedStateID },
                            set: { animationPresentation.forcedStateID = $0 }
                        ),
                        coreAnimationStateID: animationPresentation.coreStateID,
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
        HomeHeader(
            featurePresentation: featurePresentation,
            showBoUnlockPage: $showBoUnlockPage,
            cameraEnabled: canUseDewCamera,
            walkDoodleEnabled: canUseWalkDoodle,
            feedbackEnabled: boCounterFeedbackEnabled,
            dismissSpeech: dismissSpeech,
            collectAction: doPluck
        )
    }

    // MARK: Bottom controls

    private var bottomControls: some View {
        HomeBottomControls(
            hasRipeBo: boLedger.hasRipeBo,
            dismissSpeech: dismissSpeech,
            onOpenHistory: {
                Analytics.track(.historyOpen, screen: "home")
                featurePresentation.showHistory = true
            },
            onPluck: {
                _ = doPluck()
            }
        )
    }

    // MARK: 拍一拍

    private func handlePat() {
        LPHaptics.tap()
        let now = Date()
        let hour = HomeAtmosphereClock.localHour(at: now)
        let sourceStateID = semanticAnimationStateID
        HomePatInteractionCoordinator.run(
            localHour: hour,
            sourceStateID: sourceStateID,
            handlers: .init(
                registerActualPat: { localHour, countsTowardAngry in
                    store.animationExperience.registerActualPat(
                        localHour: localHour,
                        countsTowardAngry: countsTowardAngry,
                        now: now
                    )
                },
                refreshAnimationState: { refreshAnimationState(now: now) },
                currentAnimationStateID: { semanticAnimationStateID },
                transitionAnimation: { targetStateID, intent in
                    stageCommands.transitionAnimation(to: targetStateID, intent: intent)
                },
                resolvePatSpeech: { context in
                    piboSpeech.resolvePat(
                        storyStage: storySpeechStage,
                        restingState: context.resting,
                        sleepingState: context.sleeping,
                        facts: homeSpeechFacts,
                        neutralLegacyMode: !PiboReleaseScope.temporaryCooperationOnboarding
                    )
                },
                showAnimationLine: show,
                showResolvedSpeech: show,
                trackReaction: { reaction in
                    Analytics.track(
                        .pat,
                        screen: "home",
                        ["reaction": .string(reaction.rawValue)]
                    )
                }
            )
        )
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
        HomeOrnamentInteractionCoordinator.handleLightTap(
            ornamentID: id,
            index: index,
            unlocks: ornamentUnlocks,
            lights: ornamentLights
        )
    }

    private func handleOrnamentTap(_ id: PiboOrnament.ID) {
        HomeOrnamentInteractionCoordinator.handleTap(
            ornamentID: id,
            canPresent: {
                activeSheet == nil
                    && !fullScreenFeaturePresented
                    && sproutPhase == .idle
            },
            unlocks: ornamentUnlocks,
            morningSleep: morningSleep,
            history: history,
            dismissSpeech: dismissSpeech,
            present: { activeSheet = $0 }
        )
    }

    // MARK: 能量收集 (发芽 flow — see EnergySproutFlow.swift)
    private func maybeStartEnergyFlow() {
        // The close-up runs on the SpriteKit stage, which `stagePaused` freezes
        // while any sheet or cover is up — starting it behind one would play the
        // whole beat where nobody can see it.
        let request = HomeSproutFlowStartResolver.resolve(
            pendingWorkout: store.pendingWorkout,
            phase: sproutPhase,
            sheetPresented: activeSheet != nil,
            fullScreenFeaturePresented: fullScreenFeaturePresented,
            growthStart: store.headSproutGrowthProgress,
            growthTarget: { store.sproutGrowthTarget(for: $0) },
            canSprout: store.growthStage == .mystery
                && store.currentTheme.sproutedHeadSprite != nil,
            animationStyle: SproutAnimationStyle.current
        )
        sproutFlow.start(
            request: request,
            reduceMotion: UIAccessibility.isReduceMotionEnabled,
            handlers: .init(
                playCloseup: { start, target, onPhase in
                    stageCommands.playSproutCloseup(
                        growthFrom: start,
                        growthTo: target,
                        onPhase: onPhase
                    )
                },
                playGrowth: { start, target in
                    stageCommands.playSproutGrowth(from: start, to: target)
                },
                markSprouted: { store.markSprouted() },
                currentPendingWorkoutID: { store.pendingWorkout?.id }
            )
        )
    }

    private func dismissEnergyPop() {
        LPHaptics.tap()
        Analytics.track(.energyCollected, screen: "home",
                        ["sprouted": .bool(store.growthStage == .sprouted)])
        // 发芽只讲「收集到能量」。运动完成的成果表演归成果卡片，`pigu` 不在主场景
        // 出现 —— 这里曾经接着演一遍首页剧本，等于同一件事演两次。
        store.consumePendingWorkout()
        sproutFlow.finishPop()
    }

    // MARK: 拔毛 / 拍照

    @discardableResult
    private func doPluck() -> Bool {
        HomePluckCoordinator.run(
            ledger: boLedger,
            stageCommands: stageCommands,
            onboarding: onboarding,
            show: show
        )
    }

    /// Open the camera for a specific meal slot (早/中/晚) — the saved photo goes
    /// to the backend for 卡路里 recognition and its detail modal pops up.
    /// Guarded because 重拍 is a second door into the camera; with the feature out
    /// of 首发 range there must be no way in at all.
    private func startMealCapture(_ meal: MealType) {
        guard canUseDewCamera else { return }
        Analytics.track(.cameraOpen, screen: "home", ["meal": .string(meal.rawValue)])
        featurePresentation.cameraInitialMeal = meal
        featurePresentation.showCamera = true
    }

    private func handlePhotoSaved(_ image: UIImage?, _ subjectLabel: String?, meal: MealType? = nil) {
        LPLog.cutout.notice("photo saved → post-processing (hasImage=\(image != nil, privacy: .public) label=\(subjectLabel ?? "—", privacy: .public) meal=\(meal?.rawValue ?? "—", privacy: .public))")
        featurePresentation.cameraInitialMeal = nil
        Analytics.track(.photoSaved, screen: "camera",
                        ["meal": .string(meal?.rawValue ?? "none"),
                         "has_subject": .bool(subjectLabel != nil)])
        guard let image else {
            LPLog.cutout.info("no captured image (placeholder device) — skipping 抠图/persist")
            return
        }
        HomePhotoSaveCoordinator.process(
            image: image,
            subjectLabel: subjectLabel,
            meal: meal,
            history: history,
            recognizer: recognizer,
            isCameraPresented: { featurePresentation.showCamera },
            presentMeal: { activeSheet = .meal($0) }
        )
    }

    // MARK: 地图涂鸦 (walk doodle — see Features/WalkDoodle)

    /// Walk Doodle is a saved route and authored reaction, never a `bo` source.
    private func handleDoodleSaved(_ result: WalkDoodleResult) {
        HomeWalkDoodleSaveCoordinator.run(
            result: result,
            history: history,
            speech: piboSpeech,
            show: show
        )
    }

    // MARK: Speech plumbing

    private func dismissSpeech() {
        speechPresentation.dismiss()
    }

    private func show(_ line: PiboSpeechLine) {
        speechPresentation.show(line)
    }

    private func show(_ resolved: PiboSpeech) {
        speechPresentation.show(resolved)
    }

    private func speakForWeather(trigger: PiboSpeechTrigger) {
        guard !stagePaused,
              idleSpeechContext != nil,
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
            if speechPresentation.line == nil,
               sproutPhase == .idle,
               !stagePaused,
               let context = idleSpeechContext,
               let line = piboSpeech.resolveIdle(
                context: context,
                storyStage: storySpeechStage,
                facts: homeSpeechFacts,
                values: homeSpeechValues
               ) {
                show(line)
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
        guard let target = animationPresentation.selectDebugState(
            stateID,
            usesBounceCut: debugBounceCutIntent,
            store: store,
            history: history
        ) else { return }
        stageCommands.transitionAnimation(to: target, intent: .bounceCut)
    }
    #endif

    private func refreshAnimationState(now: Date = .now) {
        animationPresentation.refresh(store: store, history: history, now: now)
    }

    private var animationRefreshToken: HomeAnimationRefreshToken {
        HomeAnimationRefreshToken(
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

    private func presentAchievementIfPossible() {
        guard let payload = presentationPolicy.pendingAchievement(
            animationStateID: semanticAnimationStateID,
            pendingAchievement: store.animationExperience.pendingAchievement
        ) else { return }
        activeSheet = .achievement(payload)
    }

    /// HealthKit can deliver a newer workout while an achievement sheet is
    /// already visible. Keep the sheet bound to the replaceable pending slot;
    /// otherwise its Confirm button targets an obsolete UUID and becomes an
    /// undismissable no-op because interactive dismissal is disabled.
    private func reconcilePresentedAchievement() {
        guard case .achievement(let presented) = activeSheet else { return }
        let reconciliation = HomeAchievementPresentationPolicy.reconciliation(
            presentedAchievement: presented,
            pendingAchievement: store.animationExperience.pendingAchievement
        )
        reconciliation.apply(to: &activeSheet)
    }

    private func confirmAchievement(_ payload: PiboAnimationAchievementPayload) {
        #if DEBUG
        if HomeAchievementPresentationPolicy.shouldDismissStaleFixture(
            presentedAchievementID: payload.id,
            pendingAchievementID: store.animationExperience.pendingAchievement?.id,
            fixtureEnabled: HomeDebugLaunchOptions.current.hasAchievementArgument
        ) {
            activeSheet = nil
            return
        }
        #endif
        guard HomeAchievementPresentationPolicy.shouldConfirm(
            presentedAchievementID: payload.id,
            pendingAchievementID: store.animationExperience.pendingAchievement?.id
        ) else { return }
        _ = store.animationExperience.confirmPending()
        if HomeAchievementPresentationPolicy.consumesPendingWorkout(
            presentedAchievement: payload,
            pendingWorkoutID: store.pendingWorkout?.id
        ) {
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

    private func presentMorningSleepIfPossible() {
        let presentation = presentationPolicy.morningSleepPresentation(
            sleepReviewGranted: ornamentUnlocks.grants(.sleepReview),
            // Re-validated at the moment of presentation, not when it was
            // queued: a card queued late at night must not surface as "last
            // night" after midnight, nor consume the wrong wake-day.
            consumablePresentation: morningSleep.consumablePresentation()
        )
        guard let presentation else { return }
        activeSheet = .morningSleep(presentation, consumesPending: true)
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
        if activeSheet == nil { announceFirstRipeBoIfNeeded() }
    }

    /// 首枚 `bo` 长熟时讲一次规则，之后再不打扰。
    ///
    /// 只说明首次形成事实；成熟物不会过期，也不会冻结后续积累。
    private func announceFirstRipeBoIfNeeded() {
        let key = PiboPersistenceKeys.Defaults.boFirstRipeNotified
        guard presentationPolicy.shouldAnnounceFirstRipeBo(
            hasRipeBo: boLedger.hasRipeBo,
            wasAnnounced: UserDefaults.standard.bool(forKey: key),
            speechIsAbsent: speechPresentation.line == nil,
            idleSpeechContextAvailable: idleSpeechContext != nil
        ) else { return }
        UserDefaults.standard.set(true, forKey: key)

        show(PiboSpeechLine(text: AppLocalization.narrative("home.bo.firstRipe")))
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
        guard presentationPolicy.shouldPresentStressCard(
            pendingCardOpen: stressNotifier.pendingCardOpen
        ) else { return }
        stressNotifier.pendingCardOpen = false
        featurePresentation.historyFocus = .stress
        featurePresentation.showHistory = true
    }

    private func startSoundscape() {
        soundscape.setEnabled(ambientSoundEnabled)
        soundscape.setPresentation(soundscapePresentation)
        soundscape.refreshExternalAudioSuppression()
        soundscape.apply(
            environment: stageEnvironment,
            date: atmosphereClock.now,
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
        onboarding.reset()
        ornamentUnlocks.reset()
        ornamentLights.reset()
        UserDefaults.standard.removeObject(
            forKey: PiboPersistenceKeys.Defaults.boFirstRipeNotified
        )
    }

#if DEBUG
    private func runDebugLaunchAutomation() {
        HomeDebugLaunchAutomation.run(
            options: .current,
            miniGamesEnabled: PiboReleaseScope.miniGames,
            gamesAlreadyOpened: &debugOpenedGames,
            historyAlreadyOpened: &debugOpenedHistory,
            handlers: .init(
                setForestHour: { store.debugForestHour = $0 },
                simulateLunch: { debugSimulateMeal(.lunch) },
                openGames: { featurePresentation.showGames = true },
                openHistory: { featurePresentation.showHistory = true },
                showMorningSleep: { morningSleep.debugPresentFixture() },
                presentAchievementIfAvailable: { payload in
                    guard activeSheet == nil else { return }
                    activeSheet = .achievement(payload)
                },
                bounceToAnimationState: { target in
                    // Deterministic Simulator capture hook. The delay leaves
                    // one stable source frame before the exact 710 ms cut.
                    animationPresentation.prepareDebugBounce(to: target)
                    stageCommands.transitionAnimation(to: target, intent: .bounceCut)
                },
                selectAnimationState: applyDebugAnimationState,
                enqueueBoProgress: { boProgressFeedback.enqueue($0) },
                openBoPanel: { showBoUnlockPage = true },
                openStressCard: {
                    // Seed first: the stress card needs a derived score, which
                    // a bare simulator has no heartbeat series to produce.
                    store.debugSeedStressIfNeeded()
                    stressNotifier.pendingCardOpen = true
                }
            )
        )
    }

    /// Close Settings first so Home is visible when the real workout event is
    /// injected. Waiting for the navigation pop avoids queuing the modal behind
    /// an off-screen destination and makes the one-tap rehearsal deterministic.
    private func debugSimulateWorkout() {
        featurePresentation.showSettings = false
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
#Preview {
    HomeView()
        .environment(PetStateStore(demoMode: true))
        .environment(PiboSpeechService())
        .environment(MorningSleepCoordinator())
        .environment(HistoryPreviewData.store)
        .environment(WeatherDataService())
}

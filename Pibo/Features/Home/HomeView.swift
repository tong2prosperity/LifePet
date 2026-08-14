import PiboCore
import SwiftUI
import UIKit

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
    @State private var debugAutomation = HomeDebugAutomationController()
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
    @State private var debugControls = HomeDebugControlsState()
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
            presentation: featurePresentation,
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

    private var speechInput: HomeSpeechInputProvider {
        HomeSpeechInputProvider(
            store: store,
            boLedger: boLedger,
            onboarding: onboarding,
            animationPresentation: animationPresentation
        )
    }

    private var featureAccess: HomeFeatureAccess {
        HomeFeatureAccess(
            presentation: featurePresentation,
            ornamentUnlocks: ornamentUnlocks
        )
    }

    private var stageInteractions: HomeStageInteractionAdapter {
        HomeStageInteractionAdapter(
            store: store,
            history: history,
            animationPresentation: animationPresentation,
            stageCommands: stageCommands,
            speech: piboSpeech,
            ledger: boLedger,
            onboarding: onboarding,
            ornamentUnlocks: ornamentUnlocks,
            ornamentLights: ornamentLights,
            morningSleep: morningSleep,
            storyStage: { speechInput.storyStage },
            speechFacts: { speechInput.facts },
            canPresentOrnament: {
                activeSheet == nil
                    && !fullScreenFeaturePresented
                    && sproutPhase == .idle
            },
            dismissSpeech: dismissSpeech,
            showAnimationLine: { show($0) },
            showResolvedSpeech: { show($0) },
            presentSheet: { activeSheet = $0 }
        )
    }

    private var achievementLifecycle: HomeAchievementLifecycleAdapter {
        HomeAchievementLifecycleAdapter(
            store: store,
            currentPolicy: { presentationPolicy },
            currentAnimationStateID: { semanticAnimationStateID },
            withSheet: { update in update(&activeSheet) },
            dismissSheet: { activeSheet = nil },
            applyDebugReward: { payload in
                #if DEBUG
                debugAutomation.applyWorkoutRewardIfMatching(
                    payload,
                    ledger: boLedger
                )
                #endif
            },
            refreshAnimationState: { refreshAnimationState() },
            beginSheetDismissal: {
                homeSheetDismissalInProgress = true
                activeSheet = nil
            }
        )
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

    private var forestTuning: StageRenderTuning {
        #if DEBUG
        debugControls.tuning
        #else
        .standard
        #endif
    }

    private var homeScene: some View {
        ZStack {
            HomeStageSurface(
                input: .init(
                    store: store,
                    animationPresentation: animationPresentation,
                    environment: stageEnvironment,
                    ornamentUnlocks: ornamentUnlocks,
                    ornamentLights: ornamentLights,
                    tuning: forestTuning,
                    isPaused: stagePaused,
                    isObscured: showBoUnlockPage
                ),
                commandController: stageCommands,
                handlers: stageInteractions.stageHandlers
            )

            chromeContent
                .allowsHitTesting(!showBoUnlockPage)
                .accessibilityHidden(stagePaused || showBoUnlockPage)

            HomeStoryRecoveryOverlay(
                onboarding: onboarding,
                presentation: featurePresentation
            )

            HomeSproutOverlay(
                phase: sproutPhase,
                onDismissPop: dismissEnergyPop
            )

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
            .modifier(homeTaskModifier)
    }

    private var homeTaskModifier: HomeTaskModifier {
        HomeTaskModifier(
            angryUntil: store.animationExperience.angryUntil,
            atmosphereClock: atmosphereClock,
            ornamentLights: ornamentLights,
            soundscape: soundscape,
            speechInput: .init(
                speechIsAbsent: { speechPresentation.line == nil },
                sproutIsIdle: { sproutPhase == .idle },
                stageIsPaused: { stagePaused },
                context: { speechInput.idleContext },
                storyStage: { speechInput.storyStage },
                facts: { speechInput.facts },
                values: { speechInput.values },
                speech: piboSpeech,
                show: show
            ),
            handlers: .init(
                refreshAnimation: { refreshAnimationState() },
                refreshAnimationAt: refreshAnimationState
            )
        )
    }

    private var homeLifecycleContent: some View {
        homeTaskContent
            .modifier(homeLifecycleModifier)
    }

    private var homeLifecycleModifier: HomeLifecycleModifier {
        HomeLifecycleModifier(
            greetingText: $greetingText,
            dayLabelText: $dayLabelText,
            currentGreeting: { store.mowanGreeting },
            currentDayLabel: { store.relationshipDayLabel },
            stageEnvironment: stageEnvironment,
            weather: weather.condition,
            petID: store.identity.currentPetId,
            ambientSoundEnabled: ambientSoundEnabled,
            soundscapePresentation: soundscapePresentation,
            currentHasRipeBo: { boLedger.hasRipeBo },
            weatherService: weather,
            soundscape: soundscape,
            currentDate: { atmosphereClock.now },
            handlers: .init(
                speakForWeather: speakForWeather,
                refreshAnimation: { refreshAnimationState() },
                runDebugAutomation: {
                    #if DEBUG
                    runDebugLaunchAutomation()
                    #endif
                },
                presentAchievement: achievementLifecycle.presentIfPossible,
                presentMorningSleep: presentMorningSleepIfPossible,
                presentStressCard: presentStressCardIfPossible,
                announceFirstRipeBo: announceFirstRipeBoIfNeeded
            )
        )
    }

    private var homeStateObservationContent: some View {
        homeLifecycleContent
            .modifier(stateObservationModifier)
    }

    private var stateObservationModifier: HomeStateObservationModifier {
        HomeStateObservationModifier(
            animationRefreshToken: animationRefreshToken,
            morningSleepPresentationID: morningSleep.pendingPresentation?.id,
            scenePhase: scenePhase,
            pendingStressCardOpen: stressNotifier.pendingCardOpen,
            hasRipeBo: boLedger.hasRipeBo,
            animationStateID: semanticAnimationStateID,
            sproutPhase: sproutPhase,
            handlers: stateObservationHandlers
        )
    }

    private var stateObservationHandlers: HomeStateObservationCoordinator.Handlers {
        HomeStateObservationCoordinator.Handlers(
            refreshAnimation: { refreshAnimationState() },
            reconcileAchievement: achievementLifecycle.reconcilePresentedAchievement,
            presentAchievement: achievementLifecycle.presentIfPossible,
            refreshOrnamentLights: {
                // A foreground return can cross dawn while nobody was present
                // to watch yesterday's lights turn off.
                ornamentLights.refresh()
            },
            presentMorningSleep: presentMorningSleepIfPossible,
            presentStressCard: presentStressCardIfPossible,
            currentHasRipeBo: { boLedger.hasRipeBo },
            announceFirstRipeBo: announceFirstRipeBoIfNeeded,
            resumePendingFlows: resumePendingHomeFlows
        )
    }

    private var homeWithoutSheet: some View {
        homeStateObservationContent
        .modifier(
            HomeFeatureCoversModifier(
                presentation: featurePresentation,
                cameraPresented: featureAccess.cameraPresented,
                gamesPresented: featureAccess.gamesPresented,
                walkDoodlePresented: featureAccess.walkDoodlePresented,
                walkDoodleEnabled: featureAccess.walkDoodleEnabled,
                store: store,
                history: history,
                resumePendingFlows: resumePendingHomeFlows,
                historyDismissed: historyDismissed,
                photoSaved: handlePhotoSaved,
                doodleSaved: handleDoodleSaved
            )
        )
        .navigationDestination(isPresented: featurePresentation.settingsBinding) {
            settingsDestination
        }
    }

    var body: some View {
        homeWithoutSheet
            .modifier(
                HomeSheetModifier(
                    destination: $activeSheet,
                    store: store,
                    history: history,
                    recognizer: recognizer,
                    morningSleep: morningSleep,
                    onDismiss: resumePendingHomeFlows,
                    startMealCapture: startMealCapture,
                    confirmAchievement: achievementLifecycle.confirm
                )
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

    // MARK: Chrome

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

            HomePrimaryChrome(
                featurePresentation: featurePresentation,
                showBoUnlockPage: $showBoUnlockPage,
                cameraEnabled: featureAccess.cameraEnabled,
                walkDoodleEnabled: featureAccess.walkDoodleEnabled,
                feedbackEnabled: boCounterFeedbackEnabled,
                hasRipeBo: boLedger.hasRipeBo,
                dismissSpeech: dismissSpeech,
                collectAction: stageInteractions.collectBo,
                onOpenHistory: {
                    Analytics.track(.historyOpen, screen: "home")
                    featurePresentation.showHistory = true
                }
            )

            #if DEBUG
            HomeDebugControlsOverlay(
                controls: debugControls,
                store: store,
                animationPresentation: animationPresentation,
                stageCommands: stageCommands,
                onSelectAnimationState: applyDebugAnimationState
            )
            #endif
        }
        .opacity(sproutPhase.obscuresHomeChrome ? 0 : 1)
        .allowsHitTesting(!sproutPhase.obscuresHomeChrome)
    }

    // MARK: 能量收集 (发芽 flow — see EnergySproutFlow.swift)
    private func maybeStartEnergyFlow() {
        sproutFlow.startIfPossible(
            store: store,
            sheetPresented: activeSheet != nil,
            fullScreenFeaturePresented: fullScreenFeaturePresented,
            stageCommands: stageCommands
        )
    }

    private func dismissEnergyPop() {
        HomeEnergyCollectionCoordinator.dismissPop(
            store: store,
            flow: sproutFlow
        )
    }

    // MARK: 拍照

    /// Open the camera for a specific meal slot (早/中/晚) — the saved photo goes
    /// to the backend for 卡路里 recognition and its detail modal pops up.
    /// Guarded because 重拍 is a second door into the camera; with the feature out
    /// of 首发 range there must be no way in at all.
    private func startMealCapture(_ meal: MealType) {
        HomeCameraPresentationCoordinator.openIfEnabled(
            meal: meal,
            isEnabled: featureAccess.cameraEnabled,
            presentation: featurePresentation
        )
    }

    private func handlePhotoSaved(_ image: UIImage?, _ subjectLabel: String?, meal: MealType? = nil) {
        HomePhotoSaveCoordinator.handleSavedPhoto(
            image: image,
            subjectLabel: subjectLabel,
            meal: meal,
            clearInitialMeal: { featurePresentation.cameraInitialMeal = nil },
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
        HomeSpeechOpportunityCoordinator.presentWeatherIfPossible(
            trigger: trigger,
            stageIsPaused: stagePaused,
            idleSpeechContext: speechInput.idleContext,
            weather: weather.condition,
            speech: piboSpeech,
            show: show
        )
    }

    #if DEBUG
    /// 面板选中一个状态（nil = 交还给 Core）。
    ///
    /// 走的是业务同一条路径：先写状态变量让下一次 `apply(...)` 生效；要看 Q 弹
    /// 时紧接着发命令 —— 命令会先把渲染器的 `animationStateID` 写掉，随后那次
    /// `apply` 自然成为 no-op，不会双切。顺序与拍一拍交互一致。
    private func applyDebugAnimationState(_ stateID: String?) {
        debugControls.selectAnimationState(
            stateID,
            animationPresentation: animationPresentation,
            store: store,
            history: history,
            stageCommands: stageCommands
        )
    }
    #endif

    private func refreshAnimationState(now: Date = .now) {
        animationPresentation.refresh(store: store, history: history, now: now)
    }

    private var animationRefreshToken: HomeAnimationRefreshToken {
        HomeAnimationRefreshToken(store: store, history: history)
    }

    private func presentMorningSleepIfPossible() {
        HomeMorningSleepPresentationCoordinator.presentIfPossible(
            policy: presentationPolicy,
            sleepReviewGranted: ornamentUnlocks.grants(.sleepReview),
            consumablePresentation: morningSleep.consumablePresentation(),
            destination: &activeSheet
        )
    }

    private func resumePendingHomeFlows() {
        HomePendingFlowCoordinator.resume(handlers: .init(
            clearSheetDismissal: { homeSheetDismissalInProgress = false },
            presentAchievement: achievementLifecycle.presentIfPossible,
            sheetIsAbsent: { activeSheet == nil },
            presentMorningSleep: presentMorningSleepIfPossible,
            presentStressCard: presentStressCardIfPossible,
            announceFirstRipeBo: announceFirstRipeBoIfNeeded
        ))
    }

    /// 首枚 `bo` 长熟时讲一次规则，之后再不打扰。
    ///
    /// 只说明首次形成事实；成熟物不会过期，也不会冻结后续积累。
    private func announceFirstRipeBoIfNeeded() {
        HomeFirstRipeBoAnnouncementCoordinator.announceIfNeeded(
            policy: presentationPolicy,
            hasRipeBo: boLedger.hasRipeBo,
            speechIsAbsent: speechPresentation.line == nil,
            idleSpeechContextAvailable: speechInput.idleContext != nil,
            show: show
        )
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
        HomeStressCardPresentationCoordinator.presentIfPossible(
            policy: presentationPolicy,
            notifier: stressNotifier,
            presentation: featurePresentation
        )
    }

    private func performReset() {
        HomeResetCoordinator.run(
            speech: piboSpeech,
            store: store,
            boLedger: boLedger,
            onboarding: onboarding,
            ornamentUnlocks: ornamentUnlocks,
            ornamentLights: ornamentLights
        )
    }

#if DEBUG
    private func runDebugLaunchAutomation() {
        debugAutomation.runLaunchAutomation(
            options: .current,
            miniGamesEnabled: featureAccess.miniGamesEnabled,
            store: store,
            presentation: featurePresentation,
            morningSleep: morningSleep,
            animationPresentation: animationPresentation,
            stageCommands: stageCommands,
            boProgressFeedback: boProgressFeedback,
            stressNotifier: stressNotifier,
            sheetIsAbsent: { activeSheet == nil },
            presentSheet: { activeSheet = $0 },
            selectAnimationState: applyDebugAnimationState,
            photoSaved: handlePhotoSaved,
            openBoPanel: { showBoUnlockPage = true }
        )
    }

    /// Close Settings first so Home is visible when the real workout event is
    /// injected. Waiting for the navigation pop avoids queuing the modal behind
    /// an off-screen destination and makes the one-tap rehearsal deterministic.
    private func debugSimulateWorkout() {
        debugAutomation.simulateWorkout(
            store: store,
            presentation: featurePresentation
        )
    }

    /// DEV: exercise the full 拍餐识别 path without a camera — render a food emoji
    /// as the "captured" frame and run it through `handlePhotoSaved`.
    private func debugSimulateMeal(_ meal: MealType) {
        HomeDebugAutomationController.simulateMeal(
            meal,
            photoSaved: handlePhotoSaved
        )
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

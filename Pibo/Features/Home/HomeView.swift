import PiboCore
import SwiftUI

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
    /// router into Home's pending-presentation adapter.
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

    private var speechInteractions: HomeSpeechInteractionAdapter {
        HomeSpeechInteractionAdapter(
            presentation: speechPresentation,
            input: speechInput,
            speech: piboSpeech,
            currentPolicy: { presentationPolicy },
            currentStageIsPaused: { stagePaused },
            currentWeather: { weather.condition },
            currentHasRipeBo: { boLedger.hasRipeBo }
        )
    }

    private var featureAccess: HomeFeatureAccess {
        HomeFeatureAccess(
            presentation: featurePresentation,
            ornamentUnlocks: ornamentUnlocks
        )
    }

    private var contentCapture: HomeContentCaptureAdapter {
        HomeContentCaptureAdapter(
            currentCameraEnabled: { featureAccess.cameraEnabled },
            presentation: featurePresentation,
            history: history,
            recognizer: recognizer,
            speech: piboSpeech,
            presentMeal: { activeSheet = .meal($0) },
            showSpeech: speechInteractions.show
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
            dismissSpeech: speechInteractions.dismiss,
            showAnimationLine: speechInteractions.show,
            showResolvedSpeech: speechInteractions.show,
            presentSheet: { activeSheet = $0 }
        )
    }

    #if DEBUG
    private var debugInteractions: HomeDebugInteractionAdapter {
        HomeDebugInteractionAdapter(
            automation: debugAutomation,
            controls: debugControls,
            store: store,
            history: history,
            presentation: featurePresentation,
            morningSleep: morningSleep,
            animationPresentation: animationPresentation,
            stageCommands: stageCommands,
            boProgressFeedback: boProgressFeedback,
            stressNotifier: stressNotifier,
            ledger: boLedger,
            currentMiniGamesEnabled: { featureAccess.miniGamesEnabled },
            sheetIsAbsent: { activeSheet == nil },
            presentSheet: { activeSheet = $0 },
            photoSaved: contentCapture.handleSavedPhoto,
            openBoPanel: { showBoUnlockPage = true }
        )
    }
    #endif

    private var achievementLifecycle: HomeAchievementLifecycleAdapter {
        HomeAchievementLifecycleAdapter(
            store: store,
            currentPolicy: { presentationPolicy },
            currentAnimationStateID: { semanticAnimationStateID },
            withSheet: { update in update(&activeSheet) },
            dismissSheet: { activeSheet = nil },
            applyDebugReward: { payload in
                #if DEBUG
                debugInteractions.applyWorkoutRewardIfMatching(payload)
                #endif
            },
            refreshAnimationState: { refreshAnimationState() },
            beginSheetDismissal: {
                homeSheetDismissalInProgress = true
                activeSheet = nil
            }
        )
    }

    private var pendingPresentations: HomePendingPresentationAdapter {
        HomePendingPresentationAdapter(
            currentPolicy: { presentationPolicy },
            currentSleepReviewGranted: {
                ornamentUnlocks.grants(.sleepReview)
            },
            currentMorningSleepPresentation: {
                morningSleep.consumablePresentation()
            },
            withSheet: { update in update(&activeSheet) },
            currentPendingStressCardOpen: { stressNotifier.pendingCardOpen },
            stressHandlers: .init(
                clearPendingRequest: { stressNotifier.pendingCardOpen = false },
                focusStressCard: { featurePresentation.historyFocus = .stress },
                presentHistory: { featurePresentation.showHistory = true }
            ),
            clearSheetDismissal: {
                homeSheetDismissalInProgress = false
            },
            presentAchievement: achievementLifecycle.presentIfPossible,
            sheetIsAbsent: { activeSheet == nil },
            announceFirstRipeBo: speechInteractions.announceFirstRipeBoIfNeeded
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
                    pendingPresentations.resumePendingFlows()
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
                show: speechInteractions.show
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
                speakForWeather: speechInteractions.presentWeatherIfPossible,
                refreshAnimation: { refreshAnimationState() },
                runDebugAutomation: {
                    #if DEBUG
                    debugInteractions.runLaunchAutomation()
                    #endif
                },
                presentAchievement: achievementLifecycle.presentIfPossible,
                presentMorningSleep: pendingPresentations.presentMorningSleepIfPossible,
                presentStressCard: pendingPresentations.presentStressCardIfPossible,
                announceFirstRipeBo: speechInteractions.announceFirstRipeBoIfNeeded
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
            presentMorningSleep: pendingPresentations.presentMorningSleepIfPossible,
            presentStressCard: pendingPresentations.presentStressCardIfPossible,
            currentHasRipeBo: { boLedger.hasRipeBo },
            announceFirstRipeBo: speechInteractions.announceFirstRipeBoIfNeeded,
            resumePendingFlows: pendingPresentations.resumePendingFlows
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
                resumePendingFlows: pendingPresentations.resumePendingFlows,
                historyDismissed: historyDismissed,
                photoSaved: contentCapture.handleSavedPhoto,
                doodleSaved: contentCapture.handleSavedDoodle
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
                    onDismiss: pendingPresentations.resumePendingFlows,
                    startMealCapture: contentCapture.startMealCapture,
                    confirmAchievement: achievementLifecycle.confirm
                )
            )
    }

    @ViewBuilder
    private var settingsDestination: some View {
        #if DEBUG
        SettingsView(
            onReset: performReset,
            onSimulateMeal: debugInteractions.simulateMeal,
            onSimulateWorkout: debugInteractions.simulateWorkout
        )
        #else
        SettingsView()
        #endif
    }

    private func historyDismissed() {
        featurePresentation.historyFocus = nil
        pendingPresentations.resumePendingFlows()
    }

    // MARK: Chrome

    private var chromeContent: some View {
        ZStack {
            // Speech bubble floats just above Pibo's head (~30% down).
            if let speech = speechPresentation.line {
                HomeSpeechOverlay.make(line: speech) {
                    speechInteractions.dismiss()
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
                dismissSpeech: speechInteractions.dismiss,
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
                onSelectAnimationState: debugInteractions.selectAnimationState
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

    private func refreshAnimationState(now: Date = .now) {
        animationPresentation.refresh(store: store, history: history, now: now)
    }

    private var animationRefreshToken: HomeAnimationRefreshToken {
        HomeAnimationRefreshToken(store: store, history: history)
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

}
#Preview {
    HomeView()
        .environment(PetStateStore(demoMode: true))
        .environment(PiboSpeechService())
        .environment(MorningSleepCoordinator())
        .environment(HistoryPreviewData.store)
        .environment(WeatherDataService())
}

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
    @Environment(WalkDoodleProgressStore.self) private var walkDoodleProgress
    @Environment(OrnamentUnlockStore.self) private var ornamentUnlocks
    @Environment(OrnamentLightStore.self) private var ornamentLights
    @Environment(HealthHistoryStore.self) private var history
    @Environment(HealthDataService.self) private var health
    @Environment(PiboSpeechService.self) private var piboSpeech
    @Environment(OnboardingStateStore.self) private var onboarding
    @Environment(MorningSleepCoordinator.self) private var morningSleep
    /// Carries the "user tapped a stress push" request from the notification
    /// router into Home's pending-presentation adapter.
    @Environment(StressNotifier.self) private var stressNotifier
    @Environment(WeatherDataService.self) private var weather
    @Environment(AuthService.self) private var auth
    @Environment(ShadowService.self) private var shadowService
    @Environment(ShadowFriendStore.self) private var shadowFriendStore
    @Environment(ShadowFriendLightStore.self) private var shadowLightStore
    @Environment(ShadowSyncCoordinator.self) private var shadowSync

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var speechPresentation = HomeSpeechPresentationController()
    @State private var presentation = HomePresentationState()
    @State private var statusObserverPresentation = StatusObserverPresentationStore()
    #if DEBUG
    @State private var debugAutomation = HomeDebugAutomationController()
    #endif
    @State private var recognizer = FoodRecognitionService()
    @State private var stageCommands = PiboStageCommandController()
    @State private var contextualActions = HomeContextualActionCoordinator()
    @State private var ornamentDiscovery = OrnamentDiscoveryStore()
    @State private var discoveryTask: Task<Void, Never>?
    @State private var walkEchoCoordinates: [DoodleCoordinate] = []
    @State private var walkEchoProgress: CGFloat = 0
    @State private var walkEchoOpacity = 0.0
    @State private var walkEchoTask: Task<Void, Never>?
    /// 发芽 close-up trigger + phase (Figma 74:6102: workout detected → 特写
    /// pibo头顶动画 → 运动记录同步 pop). See `EnergySproutFlow.swift`.
    @State private var sproutFlow = HomeSproutFlowController()
    /// Greeting / day-label cached once (they're "drawn once per day").
    @State private var greetingText: String = ""
    @State private var dayLabelText: String = ""
    @State private var atmosphereClock = HomeAtmosphereClock()
    @State private var animationPresentation = HomeAnimationPresentationController()
    @State private var soundscape = AmbientSoundscapeService()
    @State private var shadowManifestSequence = 0
    @State private var shadowLightReceiptSequence = 0
    @State private var shadowManifestPendingRelationshipID = ""
    @State private var shadowPreviewCredential = ""
    @State private var shadowLightBanner: String?
    @State private var shadowManifestTask: Task<Void, Never>?
    @State private var shadowLightBannerTask: Task<Void, Never>?
    /// Decision 048: collection presentation in flight (keeps the collection pose).
    @State private var boHarvestActive = false
    @State private var boBalanceHint: String?
    @State private var boBalanceHintTask: Task<Void, Never>?
    @State private var boBalanceTarget: CGPoint?
    /// Current pose's bo container top (global), for the speech bubble.
    @State private var speechAnchor: CGPoint?
    /// Decision 054 companion prompts, echoes and moods (local-only memory).
    @State private var companion = HomeCompanionController.shared
    @AccessibilityFocusState private var statusObserverHeadingFocused: Bool
    #if DEBUG
    @State private var debugBoSession: HomeDebugBoSession?
    @State private var debugPatSession: HomePatDebugSession?
    @State private var debugDayTask: Task<Void, Never>?
    @State private var debugOnboardingPreview: DailySetupStep?
    #endif
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
            presentation: presentation,
            sproutFlowIsIdle: sproutPhase == .idle
        )
    }

    private var stagePaused: Bool {
        presentationPolicy.stagePaused
    }

    /// Full-screen features can detach the SpriteKit view. Native Moss sheets
    /// deliberately keep one low-cadence forest frame mounted so the spatial
    /// context remains visible through their translucent background.
    private var stageRenderingPaused: Bool {
        presentationPolicy.fullScreenFeaturePresented
    }

    private var stageObscured: Bool {
        presentation.activeSheet != nil
    }

    private var fullScreenFeaturePresented: Bool {
        presentationPolicy.fullScreenFeaturePresented
    }

    private var statusObserverOpen: Bool {
        statusObserverPresentation.isOpen
    }

    private var statusObserverUsesSample: Bool {
        statusObserverPresentation.usesSample
    }

    private var statusObserverOwnsHealthStatus: Bool {
        statusObserverCardVisible
    }

    private var statusObserverCardVisible: Bool {
        presentationPolicy.statusObserverCardVisible(
            isOpen: statusObserverOpen,
            recoveryStatusGranted: statusObserverUsesSample || ornamentUnlocks.grants(.recoveryStatus),
            foodProjectionPresented: presentation.foodProjection != nil,
            transientNoticePresented: presentation.transientNotice != nil,
            shadowLightBannerPresented: shadowLightBanner != nil
        )
    }

    private var statusObserverCardData: WellnessObserverPresentation {
        #if DEBUG
        if statusObserverUsesSample {
            // Sample fixture only: detached from health history, Core scoring,
            // rewards and ownership. The panel labels it as sample data.
            return .init(content: .available(.init(
                score: 82,
                band: .personalNormal,
                sleepSufficiency: 94,
                load: .usual,
                primaryReason: .sleepSufficient,
                secondaryReason: .hrvUsual,
                calibrationDays: 21,
                generatedAt: atmosphereClock.now
            )))
        }
        #endif
        _ = history.revision
        return WellnessObserverPresentation.make(
            record: history.record(on: atmosphereClock.now),
            availability: health.dataAvailability
        )
    }

    private var speechInput: HomeSpeechInputProvider {
        HomeSpeechInputProvider(
            store: store,
            boLedger: boLedger,
            onboarding: onboarding,
            animationPresentation: animationPresentation
        )
    }

    private var boProgressReconcileToken: String {
        [
            boProgressFeedback.pending?.id.uuidString ?? "-",
            presentationPolicy.boProgressFeedbackEnabled ? "ready" : "blocked",
            morningSleep.latestSummary?.wakeDayKey ?? "-",
            store.animationExperience.pendingAchievement?.id.uuidString ?? "-",
            store.pendingWorkout?.id.uuidString ?? "-",
            presentation.foodProjection?.id.uuidString ?? "-",
        ].joined(separator: "|")
    }

    private var speechOpportunities: HomeSpeechOpportunities {
        HomeSpeechOpportunities(
            presentation: speechPresentation,
            input: speechInput,
            speech: piboSpeech,
            currentPolicy: { presentationPolicy },
            currentStageIsPaused: { stagePaused || companion.holdsSpeech || companion.active != nil },
            currentWeather: { weather.condition },
            currentHasRipeBo: { boLedger.hasRipeBo }
        )
    }

    private var featureAccess: HomeFeatureAccess {
        HomeFeatureAccess(
            presentation: presentation,
            ornamentUnlocks: ornamentUnlocks
        )
    }

    private var contentCapture: HomeContentCapture {
        HomeContentCapture(
            currentCameraEnabled: { featureAccess.cameraEnabled },
            presentation: presentation,
            history: history,
            ledger: boLedger,
            walkDoodleProgress: walkDoodleProgress,
            recognizer: recognizer,
            speech: piboSpeech,
            showSpeech: speechPresentation.show
        )
    }

    private var stageInteractions: HomeStageInteractions {
        HomeStageInteractions(
            store: store,
            history: history,
            animationPresentation: animationPresentation,
            stageCommands: stageCommands,
            contextualActions: contextualActions,
            speech: piboSpeech,
            ledger: boLedger,
            onboarding: onboarding,
            ornamentUnlocks: ornamentUnlocks,
            ornamentLights: ornamentLights,
            morningSleep: morningSleep,
            storyStage: { speechInput.storyStage },
            speechFacts: { speechInput.facts },
            healthAvailability: { health.dataAvailability },
            canPresentOrnament: {
                presentation.activeSheet == nil
                    && !fullScreenFeaturePresented
                    && sproutPhase == .idle
                    && presentation.foodProjection == nil
            },
            toggleStatusObserver: toggleStatusObserver,
            dismissSpeech: speechPresentation.dismiss,
            showAnimationLine: speechPresentation.show,
            showResolvedSpeech: speechPresentation.show,
            presentSheet: { presentation.activeSheet = $0 },
            companion: companion,
            debugPat: debugPatHooks
        )
    }

    #if DEBUG
    private var debugInteractions: HomeDebugInteractions {
        HomeDebugInteractions(
            automation: debugAutomation,
            controls: debugControls,
            store: store,
            history: history,
            presentation: presentation,
            morningSleep: morningSleep,
            animationPresentation: animationPresentation,
            stageCommands: stageCommands,
            boProgressFeedback: boProgressFeedback,
            stressNotifier: stressNotifier,
            ledger: boLedger,
            currentMiniGamesEnabled: { featureAccess.miniGamesEnabled },
            sheetIsAbsent: { presentation.activeSheet == nil },
            presentSheet: { presentation.activeSheet = $0 },
            photoSaved: contentCapture.handleSavedPhoto,
            openBoPanel: {
                if let id = ornamentUnlocks.nextLocked?.id {
                    presentation.activeSheet = .ornamentUnlock(id)
                }
            }
        )
    }
    #endif

    private var presentationFlow: HomePresentationFlow {
        HomePresentationFlow(
            presentation: presentation,
            store: store,
            ornamentUnlocks: ornamentUnlocks,
            morningSleep: morningSleep,
            stressNotifier: stressNotifier,
            currentPolicy: { presentationPolicy },
            currentAnimationStateID: { semanticAnimationStateID },
            applyDebugReward: { payload in
                #if DEBUG
                debugInteractions.applyWorkoutRewardIfMatching(payload)
                #endif
            },
            refreshAnimationState: { refreshAnimationState() },
            announceFirstRipeBo: speechOpportunities.announceFirstRipeBoIfNeeded
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

    private var shadowSnapshotDraft: ShadowSnapshotDraft? {
        ShadowSnapshotValues.makeDraft(
            ownerName: store.ownerName,
            state: animationPresentation.state,
            decision: animationPresentation.decision,
            animationStateID: animationPresentation.stateID,
            occurredAt: animationPresentation.stateOccurredAt,
            hasHammock: ornamentUnlocks.isUnlocked(.hammock)
        )
    }

    private var shadowStagePresentation: ShadowPiboStagePresentation {
        guard PiboReleaseScope.shadow else { return .hidden }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PiboShadowPreview") {
            return ShadowPiboStagePresentation(
                isVisible: true,
                stateID: animationPresentation.stateID,
                friendName: "小岚",
                statusText: "当前状态：状态平稳；刚刚更新",
                manifestSequence: max(1, shadowManifestSequence),
                lightReceiptSequence: shadowLightReceiptSequence
            )
        }
        #endif
        guard auth.phase == .loggedIn,
              shadowFriendStore.hideOnHome == false,
              let view = shadowService.view,
              view.state.isActive,
              let friend = view.friend,
              let snapshot = friend.snapshot else { return .hidden }
        let sentence = ShadowFriendPresentationValues.stateSentence(snapshot.publicStateId)
        return ShadowPiboStagePresentation(
            isVisible: true,
            stateID: ShadowSnapshotValues.renderableStateID(
                snapshot.visualVariantKey,
                publicStateID: snapshot.publicStateId
            ),
            friendName: friend.displayName,
            statusText: "当前状态：\(sentence)；\(ShadowFriendPresentationValues.relativeUpdate(snapshot))",
            manifestSequence: shadowManifestSequence,
            lightReceiptSequence: shadowLightReceiptSequence
        )
    }

    /// 铃兰灯本版收起（决定 051），它的共光声景增益一并关闭。
    private func coLightCount(_ lights: [PiboOrnament.ID: Set<Int>]) -> Int {
        guard PiboReleaseScope.allowsOrnament(.lantern) else { return 0 }
        return lights[.lantern]?.count ?? 0
    }

    private var shadowEntryState: ShadowFriendHomeEntryState {
        if !shadowService.incomingCredential.isEmpty || shadowService.incoming != nil
            || shadowService.view?.endedEvent != nil { return .attention }
        guard let view = shadowService.view else { return .empty }
        if view.state == .inviteOutgoing { return .attention }
        return view.state.isActive ? .connected : .empty
    }

    private var shadowAutomationToken: String {
        let snapshot = shadowService.view?.friend?.snapshot
        return [
            String(describing: auth.phase),
            shadowService.incomingCredential,
            shadowService.incoming?.invitationId ?? "-",
            shadowService.view?.relationshipId ?? "-",
            shadowService.view?.state.rawValue ?? "-",
            String(shadowService.view?.cursor ?? -1),
            String(snapshot?.snapshotRevision ?? -1),
            shadowService.view?.endedEvent?.id ?? "-",
            String(shadowFriendStore.revision),
            String(shadowLightStore.revision),
            presentation.activeSheet?.id ?? "-",
            fullScreenFeaturePresented ? "covered" : "clear",
            sproutPhase == .idle ? "idle" : "sprout",
            presentation.foodProjection == nil ? "no-food" : "food",
            speechPresentation.line == nil ? "no-speech" : "speech",
        ].joined(separator: "|")
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
                    boLedger: boLedger,
                    animationPresentation: animationPresentation,
                    environment: stageEnvironment,
                    ornamentUnlocks: ornamentUnlocks,
                    ornamentLights: ornamentLights,
                    tuning: forestTuning,
                    isPaused: stageRenderingPaused,
                    isObscured: stageObscured,
                    shadowPresentation: shadowStagePresentation,
                    harvestActive: boHarvestActive,
                    balanceTarget: boBalanceTarget,
                    moodStateID: companion.moodAnimationID,
                    companionHotspots: companionHotspots,
                    boOverride: debugBoOverride
                ),
                commandController: stageCommands,
                handlers: stageHandlers
            )

            walkEchoOverlay
                .zIndex(5)

            chromeContent
                .accessibilityHidden(stagePaused || statusObserverCardVisible)
                .opacity(statusObserverCardVisible ? 0 : 1)
                .allowsHitTesting(!statusObserverCardVisible)

            if companion.replySheetOpen {
                CompanionReplyPanel(
                    question: companion.promptQuestion,
                    maxScalars: companion.maxReplyScalars,
                    countScalars: { companion.replyScalarCount($0) },
                    onCancel: { companion.cancelReply() },
                    onSubmit: { companion.submitReply($0) }
                )
                .zIndex(90)
                .transition(.opacity)
            }

            if statusObserverCardVisible {
                statusObserverPanel
                    .zIndex(20)
                    .transition(reduceMotion
                        ? .identity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                                .animation(.easeOut(duration: 0.24)),
                            removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                                .animation(.easeOut(duration: 0.16))
                        ))
            }

            HomeStoryRecoveryOverlay(
                onboarding: onboarding,
                presentation: presentation
            )

            // Decision 049 one-time Home guide (pat → tools + optional notifications).
            DailyHomeGuideOverlay(
                isBlocked: speechPresentation.line != nil
                    || presentation.activeSheet != nil
                    || fullScreenFeaturePresented
                    || sproutPhase != .idle
                    || presentation.foodProjection != nil
            )
            .zIndex(35)

            HomeSproutOverlay(
                phase: sproutPhase,
                onDismissPop: dismissEnergyPop
            )

            if presentation.activeSheet != nil {
                PiboMoss.Color.forestVeil
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(80)
            }

            if let projection = presentation.foodProjection {
                HomeFoodProjectionOverlay(
                    projection: projection,
                    state: animationPresentation.state,
                    onObserve: { onRight in
                        speechPresentation.dismiss()
                        stageCommands.cancelContextualAction()
                        stageCommands.playFoodObservation(onRight: onRight)
                    },
                    onComplete: {
                        guard presentation.foodProjection?.id == projection.id else { return }
                        stageCommands.cancelFoodObservation()
                        presentation.foodProjection = nil
                        presentBoProgressFeedbackIfPossible()
                        companion.onMealObserved()
                    }
                )
                .zIndex(30)
                .transition(.opacity)
            }

            if let notice = presentation.transientNotice {
                VStack {
                    HomeTransientNotice(text: notice)
                        .padding(.horizontal, LP.Spacing.l)
                        .padding(.top, 136)
                    Spacer()
                }
                .allowsHitTesting(false)
                .zIndex(40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if health.dataAvailability.requiresAttention,
               health.dataAvailability.hasReliableData,
               !statusObserverOwnsHealthStatus {
                VStack {
                    PiboMossInlineNotice(
                        title: AppLocalization.text("健康数据暂时中断"),
                        detail: AppLocalization.text("正在显示上次可信状态"),
                        actionTitle: AppLocalization.text("查看"),
                        action: { presentation.activeSheet = .healthDataStatus }
                    )
                    .padding(.horizontal, LP.Spacing.l)
                    .padding(.top, 76)
                    Spacer()
                }
                .zIndex(25)
            }

            if let shadowLightBanner {
                VStack {
                    ShadowFriendLightBanner(text: shadowLightBanner)
                        .padding(.top, 118)
                    Spacer()
                }
                .padding(.horizontal, LP.Spacing.l)
                .allowsHitTesting(false)
                .zIndex(45)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

        }
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
                show: speechPresentation.show
            ),
            handlers: .init(
                refreshAnimation: { refreshAnimationState() },
                refreshAnimationAt: refreshAnimationState
            )
        )
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
                speakForWeather: speechOpportunities.presentWeatherIfPossible,
                refreshAnimation: { refreshAnimationState() },
                runDebugAutomation: {
                    #if DEBUG
                    debugInteractions.runLaunchAutomation()
                    #endif
                },
                presentAchievement: presentationFlow.presentAchievementIfPossible,
                presentMorningSleep: presentationFlow.presentMorningSleepIfPossible,
                presentStressCard: presentationFlow.presentStressCardIfPossible,
                announceFirstRipeBo: speechOpportunities.announceFirstRipeBoIfNeeded
            )
        )
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
            reconcileAchievement: presentationFlow.reconcilePresentedAchievement,
            presentAchievement: presentationFlow.presentAchievementIfPossible,
            refreshOrnamentLights: {
                // A foreground return can cross dawn while nobody was present
                // to watch yesterday's lights turn off.
                ornamentLights.refresh()
            },
            presentMorningSleep: presentationFlow.presentMorningSleepIfPossible,
            presentStressCard: presentationFlow.presentStressCardIfPossible,
            currentHasRipeBo: { boLedger.hasRipeBo },
            announceFirstRipeBo: speechOpportunities.announceFirstRipeBoIfNeeded,
            resumePendingFlows: presentationFlow.resumePendingFlows
        )
    }

    var body: some View {
        homeScene
            .accessibilityHidden(stagePaused)
            .task(id: thinkingClockToken) {
                animationPresentation.stableThinking = false
                refreshExpressionBehavior()
                guard thinkingEligible else { return }
                try? await Task.sleep(for: .seconds(PiboCoreExpression.stableThinkingDelaySeconds))
                guard !Task.isCancelled, thinkingEligible else { return }
                animationPresentation.stableThinking = true
                refreshExpressionBehavior()
            }
            .onChange(of: animationPresentation.patState) { _, state in
                contextualActions.cancelIfStateChanged(
                    to: state,
                    stageCommands: stageCommands
                )
                piboSpeech.patStateChanged(
                    state,
                    episodeKey: animationPresentation.patEpisodeKey
                )
                speechPresentation.dismiss()
            }
            .onChange(of: shadowSnapshotDraft?.signature) { _, _ in
                shadowSync.setSnapshotDraft(shadowSnapshotDraft)
            }
            .onChange(of: shadowAutomationToken) { _, _ in
                reconcileShadowFriendFlow()
            }
            .onChange(of: scenePhase) { _, phase in
                // Decision 047: backgrounding ends the transient observer view,
                // and so does any sheet or full-screen feature taking over Home.
                if phase != .active { statusObserverPresentation.close() }
                bindCompanion()
                if phase == .active { companion.enterHome() } else { companion.leaveHome() }
            }
            .onChange(of: presentation.activeSheet == nil && !fullScreenFeaturePresented) { _, homeClear in
                if !homeClear { statusObserverPresentation.close() }
            }
            #if DEBUG
            .fullScreenCover(item: $debugOnboardingPreview) { step in
                DailyOnboardingPreviewHost(startingAt: step)
            }
            .onReceive(NotificationCenter.default.publisher(for: HomeDebugRequest.notification)) { note in
                guard let raw = note.object as? String,
                      let request = HomeDebugRequest(rawValue: raw) else { return }
                presentation.showSettings = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    handleDebugRequest(request)
                }
            }
            #endif
            .onDisappear {
                statusObserverPresentation.close()
                boBalanceHintTask?.cancel()
                boBalanceHint = nil
                companion.leaveHome()
                piboSpeech.leaveHome()
                speechPresentation.dismiss()
                stageCommands.cancelFoodObservation()
                presentation.foodProjection = nil
                presentation.pendingFoodProjection = nil
                shadowManifestTask?.cancel()
                shadowManifestTask = nil
                shadowLightBannerTask?.cancel()
                shadowLightBannerTask = nil
                shadowLightBanner = nil
                discoveryTask?.cancel()
                walkEchoTask?.cancel()
            }
            .onChange(of: health.dataAvailability) { _, _ in
                refreshAnimationState()
            }
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    bindCompanion()
                    companion.tick()
                }
            }
            .onChange(of: boProgressReconcileToken) { _, _ in
                presentBoProgressFeedbackIfPossible()
            }
            .onAppear {
                #if DEBUG
                if HomeDebugLaunchOptions.current.showsStatusObserver {
                    statusObserverPresentation.open(sample: true)
                }
                #endif
                presentBoProgressFeedbackIfPossible()
                bindCompanion()
                if scenePhase == .active { companion.enterHome() }
                #if DEBUG
                if let command = ProcessInfo.processInfo.arguments
                    .first(where: { $0.hasPrefix("-PiboCompanion=") })?
                    .dropFirst("-PiboCompanion=".count) {
                    _ = companion.debugRun(String(command))
                }
                #endif
                shadowSync.setSnapshotDraft(shadowSnapshotDraft)
                reconcileShadowFriendFlow()
                soundscape.setCoLightCount(coLightCount(ornamentLights.lit))
                resumeOrnamentDiscoveryIfNeeded()
            }
            .onChange(of: ornamentUnlocks.owned) { oldValue, newValue in
                guard newValue.count > oldValue.count,
                      let next = ornamentUnlocks.nextLocked else { return }
                ornamentDiscovery.markPending(next.id, petID: store.identity.currentPetId)
                stageCommands.prepareOrnamentDiscovery(next.id)
            }
            .onChange(of: ornamentLights.lit) { _, lights in
                soundscape.setCoLightCount(coLightCount(lights))
            }
            .modifier(homeTaskModifier)
            .modifier(homeLifecycleModifier)
            .modifier(stateObservationModifier)
            .modifier(
                HomeFeatureCoversModifier(
                    presentation: presentation,
                    cameraPresented: featureAccess.cameraPresented,
                    gamesPresented: featureAccess.gamesPresented,
                    walkDoodlePresented: featureAccess.walkDoodlePresented,
                    walkDoodleEnabled: featureAccess.walkDoodleEnabled,
                    walkDoodleRouteEchoEnabled: featureAccess.walkDoodleRouteEchoEnabled,
                    store: store,
                    history: history,
                    cameraDismissed: contentCapture.cameraDismissed,
                    resumePendingFlows: presentationFlow.resumePendingFlows,
                    historyDismissed: historyDismissed,
                    photoSaved: contentCapture.savePhoto,
                    doodleSaved: contentCapture.handleSavedDoodle
                )
            )
            .navigationDestination(isPresented: presentation.settingsBinding) {
                settingsDestination
            }
            .modifier(
                HomeSheetModifier(
                    destination: presentation.sheetBinding,
                    store: store,
                    history: history,
                    recognizer: recognizer,
                    morningSleep: morningSleep,
                    boLedger: boLedger,
                    onDismiss: {
                        if !presentation.presentQueuedCameraIfNeeded() {
                            presentationFlow.resumePendingFlows()
                            resumeOrnamentDiscoveryIfNeeded()
                        }
                    },
                    replayWalkEcho: playWalkEcho,
                    startMealCapture: { meal in
                        Analytics.track(
                            .cameraOpen,
                            screen: "meal_sheet",
                            ["meal": .string(meal.rawValue)]
                        )
                        presentation.queueCameraAfterSheet(meal)
                    },
                    confirmAchievement: presentationFlow.confirm
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
        presentation.historyFocus = nil
        presentationFlow.resumePendingFlows()
    }

    private func presentBoProgressFeedbackIfPossible() {
        guard presentationPolicy.boProgressFeedbackEnabled,
              store.animationExperience.pendingAchievement == nil,
              store.pendingWorkout == nil,
              presentation.foodProjection == nil,
              let pending = boProgressFeedback.pending
        else { return }

        let energyPerBo = PiboCoreBoEconomy.energyPerBo
        guard energyPerBo > 0 else { return }
        let sleep = morningSleep.energyFeedbackCandidate()
        let previousMature = boLedger.state.ripeCount > pending.mintedCount
        let message: String
        if previousMature {
            message = pending.mintedCount > 0
                ? AppLocalization.text("又一枚 bo 成熟了")
                : AppLocalization.text("下一枚 bo 又长了一点")
        } else {
            message = pending.milestone.message
        }
        let presentation = BoProgressPresentation(
            milestone: pending.milestone,
            message: message,
            fact: sleep.map { "昨晚睡了 \(sleepDurationText($0.total))" } ?? "",
            previousProgress: previousMature
                ? 1
                : min(1, max(0, pending.previousEnergyPool / energyPerBo)),
            currentProgress: boLedger.hasRipeBo
                ? 1
                : min(1, max(0, pending.newEnergyPool / energyPerBo)),
            previousMature: previousMature,
            mature: boLedger.hasRipeBo
        )
        guard stageCommands.playBoProgressFeedback(presentation) else { return }
        boProgressFeedback.consume(id: pending.id)
        // The bo feedback only quotes the duration; the sleep card is marked
        // seen solely when its sheet actually appears.
        if let sleep {
            morningSleep.markEnergyPresented(sleep)
        }
    }

    private func sleepDurationText(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int((duration / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return AppLocalization.format("%d 分钟", minutes) }
        if minutes == 0 { return AppLocalization.format("%d 小时", hours) }
        return AppLocalization.format("%d 小时 %d 分", hours, minutes)
    }

    // MARK: Chrome

    private var chromeContent: some View {
        ZStack {
            // Speech bubble floats just above Pibo's head (~30% down).
            if let speech = speechPresentation.line {
                HomeSpeechOverlay.make(
                    line: speech,
                    anchorY: speechAnchor?.y,
                    onDetail: {
                        speechPresentation.dismiss()
                        Analytics.track(.historyOpen, screen: "home_speech")
                        PiboSoundEffectService.shared.play(.footprintsOpen)
                        presentation.showHistory = true
                    },
                    onChoice: speech.interaction == nil ? nil : { companion.choose($0) },
                    onCustomReply: speech.interaction == nil ? nil : { companion.openReply() }
                )
            }

            HomePrimaryChrome(
                presentation: presentation,
                balanceChip: AnyView(boBalanceChip),
                cameraEnabled: featureAccess.cameraEnabled,
                walkDoodleEnabled: featureAccess.walkDoodleEnabled,
                dismissSpeech: speechPresentation.dismiss,
                onOpenHistory: {
                    Analytics.track(.historyOpen, screen: "home")
                    PiboSoundEffectService.shared.play(.footprintsOpen)
                    presentation.showHistory = true
                }
            )

            if PiboReleaseScope.shadow {
                ShadowFriendHomeEntry(state: shadowEntryState) {
                    speechPresentation.dismiss()
                    presentation.activeSheet = .shadow(manifest: false)
                }
            }

            #if DEBUG
            if debugControls.showsForestPanel {
                HomeDebugControlsOverlay(
                    controls: debugControls,
                    store: store,
                    animationPresentation: animationPresentation,
                    stageCommands: stageCommands,
                    onSelectAnimationState: debugInteractions.selectAnimationState
                )
            }
            HomeDebugDock(
                status: debugDockStatus,
                onRun: runDebugTool,
                onExitAll: exitAllDebug
            )
            .zIndex(95)
            #endif
        }
        .opacity(sproutPhase.obscuresHomeChrome ? 0 : 1)
        .allowsHitTesting(!sproutPhase.obscuresHomeChrome)
    }

    private var stageHandlers: HomeStageSurface.Handlers {
        var handlers = stageInteractions.stageHandlers
        let interactions = stageInteractions
        handlers.collectBo = {
            speechPresentation.dismiss()
            #if DEBUG
            if let session = debugBoSession { return session.collect() }
            #endif
            return interactions.collectBo()
        }
        handlers.harvestActiveChanged = { active in boHarvestActive = active }
        handlers.harvestHint = showBoBalanceHint
        handlers.companionHotspot = { hotspot in
            switch hotspot {
            case .grass: companion.onGrassTapped()
            case .river: companion.onRiverTapped()
            }
        }
        handlers.speechAnchorChanged = { point in
            if speechAnchor != point { speechAnchor = point }
        }
        return handlers
    }

    /// "已收取 1 bo" / "可用余额 N bo" beside the balance chip; 2.2 s, replaces
    /// the previous hint and clears when Home leaves the foreground.
    private func showBoBalanceHint(_ text: String) {
        boBalanceHintTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { boBalanceHint = text }
        boBalanceHintTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2_200))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.18)) { boBalanceHint = nil }
        }
    }

    private var boBalanceChip: some View {
        HomeBoBalanceChip(
            balance: displayedBoBalance,
            hint: boBalanceHint,
            onTap: {
                LPHaptics.tap()
                showBoBalanceHint(AppLocalization.format("可用余额 %d bo", boLedger.availableBo))
            },
            onCenterChange: { boBalanceTarget = $0 }
        )
    }

    /// Decision 047 floating view. The forest keeps running behind a
    /// transparent dismissal surface; hammock poses move the panel below Pibo.
    private var statusObserverPanel: some View {
        GeometryReader { proxy in
            let width = min(340, max(240, proxy.size.width - 32))
            let raisedPose = [
                PiboAnimationResourceID.sleepingHammockA,
                PiboAnimationResourceID.sleepingHammockB,
                PiboAnimationResourceID.wakingHammock,
            ].contains(animationPresentation.stateID)
            let maxCardHeight = max(180, proxy.size.height * 0.40)
            let top: CGFloat = raisedPose
                ? max(72, proxy.size.height - maxCardHeight - 76 - 60)
                : 72
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: closeStatusObserver)
                    .accessibilityHidden(true)
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(uiImage: UIImage(named: "forest_status_observer_floating") ?? UIImage())
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88, height: 52)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLocalization.text("状态观测仪"))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(PiboMoss.Color.forestInk)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityFocused($statusObserverHeadingFocused)
                            Text(AppLocalization.text(statusObserverUsesSample
                                ? "示例数据 · 不代表你的健康状态"
                                : "查看已有健康记录"))
                                .font(.system(size: 12))
                                .foregroundStyle(PiboMoss.Color.secondaryInk)
                        }
                        Spacer(minLength: 0)
                        Button(action: closeStatusObserver) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(PiboMoss.Color.forestInk)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalization.text("关闭状态观测仪"))
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(PiboMoss.Color.raisedNeutral.opacity(0.96)))
                    ScrollView {
                        WellnessObserverCard(
                            presentation: statusObserverCardData,
                            trend: statusObserverTrend,
                            expanded: statusObserverPresentation.expanded,
                            onToggleExpanded: {
                                statusObserverPresentation.setExpanded(
                                    !statusObserverPresentation.expanded
                                )
                            },
                            onOpenHealthStatus: {
                                closeStatusObserver()
                                speechPresentation.dismiss()
                                presentation.activeSheet = .healthDataStatus
                            }
                        )
                    }
                    .frame(maxHeight: maxCardHeight)
                    .fixedSize(horizontal: false, vertical: true)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .frame(width: width)
                .padding(.top, top)
                .padding(.trailing, 16)
            }
            .accessibilityAction(.escape) { closeStatusObserver() }
        }
        .onAppear { statusObserverHeadingFocused = true }
    }

    private var displayedBoBalance: Int {
        #if DEBUG
        if let session = debugBoSession { return Int(session.balance) }
        #endif
        return boLedger.availableBo
    }

    private var debugBoOverride: BoOverride? {
        #if DEBUG
        guard let session = debugBoSession else { return nil }
        return BoOverride(stage: session.growthStage, progress: session.progress, hasRipe: session.hasRipe)
        #else
        return nil
        #endif
    }

    private var debugPatHooks: (input: () -> PiboPatConversationInput, resolve: () -> PiboPatResolution)? {
        #if DEBUG
        guard let session = debugPatSession else { return nil }
        return (input: { session.input() }, resolve: { session.resolve() })
        #else
        return nil
        #endif
    }

    #if DEBUG
    private var debugDockStatus: String {
        var parts: [String] = []
        if debugBoSession != nil { parts.append("临时 bo") }
        if let session = debugPatSession { parts.append("拍一拍 · \(session.scenario.title)") }
        if animationPresentation.forcedStateID != nil { parts.append("动画覆盖") }
        if weather.debugCondition != nil { parts.append("天气覆盖") }
        if store.debugForestHour != nil { parts.append("时间覆盖") }
        if presentation.activeSheet != nil || fullScreenFeaturePresented { parts.append("有浮层打开，场景命令可能被阻挡") }
        return parts.joined(separator: " · ")
    }

    /// Routes one DEV dock command. Returns a short status line.
    private func runDebugTool(_ id: String) -> String {
        if id.hasPrefix("state:"), let state = PiboActivityState(rawValue: String(id.dropFirst(6))) {
            HomeStageSurface.debugBypassesCollectionPose = true
            debugInteractions.selectAnimationState(PiboAnimationStateMap.ambientStateID(for: state))
            return "角色表现：\(state.displayName)"
        }
        if id.hasPrefix("animation:") {
            let stateID = String(id.dropFirst("animation:".count))
            if stateID == "auto" {
                HomeStageSurface.debugBypassesCollectionPose = false
                debugInteractions.selectAnimationState(nil)
                return "已恢复当前真实表现"
            }
            HomeStageSurface.debugBypassesCollectionPose = true
            debugInteractions.selectAnimationState(nil)
            debugInteractions.selectAnimationState(stateID)
            return HomeDebugToolCatalog.animationTitles[stateID]?.title ?? stateID
        }
        if id.hasPrefix("companion:") {
            bindCompanion()
            return companion.debugRun(String(id.dropFirst("companion:".count)))
        }
        if id.hasPrefix("bo:") {
            let preset = String(id.dropFirst(3))
            switch preset {
            case "effect":
                stageCommands.debugPlayBoRipePreview()
                return "播放成熟效果（不写账本）"
            case "growth-hint":
                stageCommands.debugPlayBoGrowthHint()
                return "播放成长提示（不写账本）"
            default:
                debugBoSession = HomeDebugBoSession(preset: preset)
                return "临时 bo 场景 · 余额不写盘，不能投入真实物件"
            }
        }
        if id.hasPrefix("item:"), let ornament = PiboOrnament.ID(rawValue: String(id.dropFirst(5))) {
            stageCommands.prepareOrnamentDiscovery(ornament)
            stageCommands.playOrnamentDiscovery(ornament) {}
            return "显影预览（未解锁真实物件）"
        }
        if id.hasPrefix("weather:") {
            switch id.dropFirst(8) {
            case "rain": weather.setDebugCondition(.rain)
            case "storm": weather.setDebugCondition(.thunderstorm)
            default: weather.setDebugCondition(nil)
            }
            return HomeDebugToolCatalog.tool(id)?.title ?? id
        }
        if id.hasPrefix("hour:"), let hour = Double(id.dropFirst(5)) {
            debugDayTask?.cancel()
            store.debugForestHour = hour
            return "光影 \(HomeDebugToolCatalog.tool(id)?.title ?? id)"
        }
        switch id {
        case "onboarding":
            debugOnboardingPreview = .welcome
            return "首启预览 · 不申请权限、不写入数据"
        case "pat":
            if let session = debugPatSession {
                session.advanceScenario()
            } else {
                debugPatSession = HomePatDebugSession()
            }
            return "拍一拍场景：\(debugPatSession?.scenario.title ?? "")（双击 Pibo，或再点切到下一个）"
        case "pat-again":
            guard let session = debugPatSession else { return "先选择拍一拍场景" }
            stageInteractions.stageHandlers.pat()
            return "拍一次 · \(session.scenario.title)"
        case "pat-reset":
            guard let session = debugPatSession else { return "先选择拍一拍场景" }
            session.reset()
            speechPresentation.dismiss()
            return "已重开 \(session.scenario.title)"
        case "food-left", "food-right":
            stageCommands.playFoodObservation(onRight: id == "food-right")
            return "观察动作"
        case "day":
            debugDayTask?.cancel()
            debugDayTask = Task { @MainActor in
                let start = Date()
                while !Task.isCancelled {
                    let elapsed = Date().timeIntervalSince(start)
                    guard elapsed < 24 else { break }
                    store.debugForestHour = elapsed.truncatingRemainder(dividingBy: 24)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            return "24 秒播放一天"
        case "forest":
            debugControls.showsForestPanel.toggle()
            debugControls.isPanelExpanded = true
            return debugControls.showsForestPanel ? "森林细节参数已打开" : "森林细节参数已收起"
        case "observer":
            handleDebugRequest(.statusObserverSample)
            return "状态观测仪示例数据"
        case "sleep":
            morningSleep.debugPresentFixture()
            return "晨间睡眠卡片示例"
        case "notification":
            Task { _ = await morningSleep.debugScheduleFixtureNotification() }
            return "3 秒后发送睡眠通知（系统副作用）"
        case "workout":
            debugInteractions.simulateWorkout()
            return "已写入测试运动"
        case "history-data":
            Task {
                await history.seedSampleAllIfEmpty(forceMaintenance: true)
                presentation.showHistory = true
            }
            return "写入足迹示例数据"
        case "backend-meal":
            debugInteractions.simulateMeal(.lunch)
            return "后台餐食识别（真实网络请求）"
        case "legacy":
            presentation.showSettings = true
            return "打开维护设置"
        default:
            return ""
        }
    }

    private func exitAllDebug() {
        HomeStageSurface.debugBypassesCollectionPose = false
        debugInteractions.selectAnimationState(nil)
        weather.setDebugCondition(nil)
        debugDayTask?.cancel()
        store.debugForestHour = nil
        debugBoSession = nil
        debugPatSession = nil
        debugControls.showsForestPanel = false
        statusObserverPresentation.close()
        speechPresentation.dismiss()
    }

    private func handleDebugRequest(_ request: HomeDebugRequest) {
        switch request {
        case .statusObserverSample:
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
                statusObserverPresentation.open(sample: true)
            }
        case .boRipePreview:
            stageCommands.debugPlayBoRipePreview()
        case .boGrowthHint:
            stageCommands.debugPlayBoGrowthHint()
        case .companionPatReady, .companionAbsenceShort, .companionAbsenceLong, .companionReset:
            bindCompanion()
            let message = companion.debugRun(request.companionCommand)
            if !message.isEmpty { showBoBalanceHint(message) }
        }
    }
    #endif

    private func closeStatusObserver() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            statusObserverPresentation.close()
        }
    }

    private var statusObserverTrend: [WellnessObserverCard.TrendDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        #if DEBUG
        if statusObserverUsesSample {
            let scores: [Double?] = [68, 72, nil, 75, 71, 79, 82]
            return (-6...0).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: today).map {
                    WellnessObserverCard.TrendDay(date: $0, score: scores[offset + 6])
                }
            }
        }
        #endif
        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return WellnessObserverCard.TrendDay(
                date: date,
                score: history.record(on: date)?.wellnessSnapshot?.readinessScore?.value
            )
        }
    }

    /// Tapping the instrument toggles the transient view (the entry region
    /// counts as a close path too). The view never changes Pibo or its episode.
    private func toggleStatusObserver() {
        if statusObserverPresentation.isOpen {
            closeStatusObserver()
            return
        }
        speechPresentation.dismiss()
        PiboSoundEffectService.shared.play(.observerOpen)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
            statusObserverPresentation.open()
        }
    }

    @ViewBuilder
    private var walkEchoOverlay: some View {
        if walkEchoCoordinates.count >= 2 {
            GeometryReader { proxy in
                let scale = min(proxy.size.width / 390, proxy.size.height / 852)
                WalkDoodleShape(coordinates: walkEchoCoordinates, inset: 8)
                    .trim(from: 0, to: walkEchoProgress)
                    .stroke(
                        PiboMoss.Color.foundationTeal.opacity(0.92),
                        style: StrokeStyle(lineWidth: 5 * scale, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: .white.opacity(0.58), radius: 3 * scale)
                    .frame(width: 188 * scale, height: 118 * scale)
                    .position(x: 196 * scale, y: 647 * scale)
                    .opacity(walkEchoOpacity)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func playWalkEcho(_ record: WalkDoodleRecord) {
        guard record.coordinates.count >= 2 else { return }
        walkEchoTask?.cancel()
        walkEchoCoordinates = record.coordinates
        walkEchoProgress = reduceMotion ? 1 : 0
        walkEchoOpacity = 0
        walkEchoTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            AccessibilityNotification.Announcement("正在重播风铃中的散步回声").post()
            if reduceMotion {
                walkEchoOpacity = 0.92
                try? await Task.sleep(for: .milliseconds(1_400))
            } else {
                withAnimation(.easeOut(duration: 0.22)) { walkEchoOpacity = 0.92 }
                withAnimation(.linear(duration: 1.6)) { walkEchoProgress = 1 }
                try? await Task.sleep(for: .milliseconds(1_900))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.28)) { walkEchoOpacity = 0 }
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            walkEchoCoordinates = []
            walkEchoProgress = 0
            walkEchoOpacity = 0
        }
    }

    private func resumeOrnamentDiscoveryIfNeeded() {
        guard scenePhase == .active,
              presentation.activeSheet == nil,
              !fullScreenFeaturePresented,
              let id = ornamentDiscovery.pending(petID: store.identity.currentPetId),
              ornamentUnlocks.nextLocked?.id == id else { return }
        discoveryTask?.cancel()
        stageCommands.prepareOrnamentDiscovery(id)
        discoveryTask = Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled,
                  presentation.activeSheet == nil,
                  !fullScreenFeaturePresented else { return }
            stageCommands.playOrnamentDiscovery(id) {
                let petID = store.identity.currentPetId
                ornamentDiscovery.complete(id, petID: petID)
                let name = PiboOrnament.ornament(id)?.localizedName ?? "共同物件"
                AccessibilityNotification.Announcement("发现新的共同物件：\(name)").post()
                // Decision 048: the revealed target explains itself once.
                if ornamentDiscovery.needsIntroduction(id, petID: petID),
                   presentation.activeSheet == nil,
                   !fullScreenFeaturePresented {
                    ornamentDiscovery.completeIntroduction(id, petID: petID)
                    speechPresentation.dismiss()
                    presentation.activeSheet = .ornamentUnlock(id)
                }
            }
        }
    }

    // MARK: 能量收集 (发芽 flow — see EnergySproutFlow.swift)
    private func maybeStartEnergyFlow() {
        sproutFlow.startIfPossible(
            store: store,
            sheetPresented: presentation.activeSheet != nil,
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
        animationPresentation.refresh(
            store: store,
            history: history,
            hasHammock: ornamentUnlocks.isUnlocked(.hammock),
            hasReliableHealthData: health.dataAvailability.hasReliableData,
            now: now
        )
        refreshExpressionBehavior()
    }

    private var thinkingEligible: Bool {
        animationPresentation.state == .stable && scenePhase == .active && !stagePaused
            && speechPresentation.line == nil && presentation.foodProjection == nil
    }

    private var thinkingClockToken: String {
        "\(animationPresentation.patEpisodeKey):\(animationPresentation.attentionRevision):\(thinkingEligible)"
    }

    private func refreshExpressionBehavior() {
        let input = HomePatInputProvider(store: store, history: history,
            animationPresentation: animationPresentation,
            healthAvailability: health.dataAvailability, storyStage: speechInput.storyStage).input()
        animationPresentation.refreshExpression(behavior: piboSpeech.patBehavior(for: input))
    }

    private func reconcileShadowFriendFlow() {
        guard PiboReleaseScope.shadow, scenePhase == .active else { return }
        shadowSync.setSnapshotDraft(shadowSnapshotDraft)

        if auth.phase == .loggedIn,
           !shadowService.incomingCredential.isEmpty,
           shadowService.incoming == nil,
           shadowPreviewCredential != shadowService.incomingCredential {
            shadowPreviewCredential = shadowService.incomingCredential
            Task {
                _ = await shadowService.previewInvitation()
                reconcileShadowFriendFlow()
            }
            return
        }

        guard presentation.activeSheet == nil,
              !fullScreenFeaturePresented,
              sproutPhase == .idle,
              presentation.foodProjection == nil,
              speechPresentation.line == nil else { return }

        if shadowService.incoming != nil {
            presentation.activeSheet = .shadow(manifest: false)
            return
        }
        if shadowService.view?.endedEvent != nil {
            presentation.activeSheet = .shadow(manifest: false)
            return
        }
        if let view = shadowService.view,
           let relationshipID = view.relationshipId,
           view.friend?.snapshot != nil,
           shadowFriendStore.needsManifestTeaching(view),
           shadowManifestPendingRelationshipID != relationshipID {
            shadowManifestPendingRelationshipID = relationshipID
            shadowManifestSequence += 1
            shadowManifestTask?.cancel()
            shadowManifestTask = Task {
                if !reduceMotion { try? await Task.sleep(for: .milliseconds(950)) }
                guard !Task.isCancelled,
                      presentation.activeSheet == nil,
                      !fullScreenFeaturePresented,
                      sproutPhase == .idle,
                      presentation.foodProjection == nil,
                      speechPresentation.line == nil,
                      shadowService.view?.relationshipId == relationshipID else { return }
                presentation.activeSheet = .shadow(manifest: true)
            }
            return
        }
        guard let light = shadowLightStore.presentable() else { return }
        shadowLightStore.consume(id: light.id)
        shadowLightReceiptSequence += 1
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            shadowLightBanner = light.message
        }
        shadowLightBannerTask?.cancel()
        shadowLightBannerTask = Task {
            try? await Task.sleep(for: .milliseconds(2300))
            guard !Task.isCancelled, shadowLightBanner == light.message else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.25)) {
                shadowLightBanner = nil
            }
        }
    }

    private var animationRefreshToken: HomeAnimationRefreshToken {
        HomeAnimationRefreshToken(store: store, history: history)
    }

    /// Re-binds the companion to Home's current stores; facts are read lazily.
    private func bindCompanion() {
        companion.environment = HomeCompanionController.Environment(
            appActive: { scenePhase == .active },
            state: { animationPresentation.state },
            patBehavior: {
                let input = HomePatInputProvider(
                    store: store, history: history, animationPresentation: animationPresentation,
                    healthAvailability: health.dataAvailability, storyStage: speechInput.storyStage
                ).input()
                return piboSpeech.patBehavior(for: input)
            },
            isThinking: { animationPresentation.stableThinking },
            patEpisodeKey: { animationPresentation.patEpisodeKey },
            overlayOpen: {
                presentation.activeSheet != nil || fullScreenFeaturePresented
                    || statusObserverPresentation.isOpen || presentation.showSettings
            },
            foodProjectionVisible: { presentation.foodProjection != nil },
            achievementVisible: { store.animationExperience.pendingAchievement != nil },
            sproutBusy: { sproutPhase != .idle || boHarvestActive },
            hasRipeBo: { boLedger.hasRipeBo },
            dailyGuideActive: { onboarding.dailyHomeGuide != .none },
            speechVisible: { speechPresentation.line != nil },
            currentLine: { speechPresentation.line },
            lastSpeechAt: { speechPresentation.lastShownAt },
            weather: { weather.condition },
            speechValues: { speechInput.values },
            show: { speechPresentation.show($0) },
            dismiss: { speechPresentation.dismiss() }
        )
    }

    private var companionHotspots: PiboStageScene.CompanionHotspots {
        guard companion.enabled, !stagePaused else { return .none }
        return PiboStageScene.CompanionHotspots(
            grass: companion.grassHotspotEnabled,
            river: companion.riverHotspotEnabled,
            findsHiddenPibo: companion.mood.hidesBody
        )
    }

    private func performReset() {
        companion.store.reset()
        statusObserverPresentation.close()
        UserDefaults.standard.removeObject(forKey: PiboPersistenceKeys.Defaults.wellnessObserverPinnedPetIDs)
        HomeResetCoordinator.run(
            speech: piboSpeech,
            store: store,
            boLedger: boLedger,
            onboarding: onboarding,
            ornamentUnlocks: ornamentUnlocks,
            ornamentLights: ornamentLights
        )
        walkDoodleProgress.reset()
        animationPresentation.resetLifecycle()
        refreshAnimationState()
    }

}
#Preview {
    HomeView()
        .environment(PetStateStore(demoMode: true))
        .environment(PiboSpeechService())
        .environment(MorningSleepCoordinator())
        .environment(HistoryPreviewData.store)
        .environment(WeatherDataService())
        .environment(BoProgressFeedbackStore())
        .environment(BoLedgerStore())
        .environment(WalkDoodleProgressStore())
        .environment(OrnamentUnlockStore())
        .environment(OrnamentLightStore())
        .environment(OnboardingStateStore())
        .environment(StressNotifier.shared)
        .environment(HealthDataService(metrics: []))
        .environment(AuthService())
        .environment(ShadowService())
        .environment(ShadowFriendStore())
        .environment(ShadowFriendLightStore())
        .environment(ShadowSyncCoordinator(
            auth: AuthService(),
            service: ShadowService(),
            store: ShadowFriendStore(),
            lightStore: ShadowFriendLightStore()
        ))
}

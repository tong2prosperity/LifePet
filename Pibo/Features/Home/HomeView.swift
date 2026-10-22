import os
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
    @Environment(GrowthStore.self) private var growth
    @Environment(WishStore.self) private var wishes
    @Environment(DecorStore.self) private var decor
    @Environment(GrowthCoordinator.self) private var growthCoordinator
    @Environment(PiboDayStore.self) private var days
    @Environment(PiboSeasonStore.self) private var seasons
    @Environment(PolaroidStore.self) private var polaroids
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
    /// Decision 069: the pixel stage's day and season, once the stage exists.
    @State private var pixelDay: HomeDayController?
    @State private var pixelSeason: HomeSeasonController?
    /// Decision 057: which pixel growth sheet is up, if any.
    @State private var pixelSheet: PixelSheetKind?
    /// Decision 059: the paper the season's beats send home, if one is up.
    @State private var storyPaper: PiboStoryPaper?
    /// Decision 057: the queue that plays growth moments on Home one at a time.
    @State private var growthUI = HomeGrowthController()
    /// Decision 062: the badge's readout, open from the HUD without the ornament.
    @State private var readoutOpen = false
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
    /// Decision 048's pull cues on the pixel stage (armed, then released).
    @State private var pixelHarvestSound = OrnamentUnlockSoundService()
    /// Current pose's bo container top (global), for the speech bubble.
    @State private var speechAnchor: CGPoint?
    /// Pibo's feet, reported by the stage, for the state caption.
    @State private var captionAnchor: CGPoint?
    @State private var stateCaptionPresenter = HomeStateCaptionPresenter()
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

    /// Decision 062: the badge Pibo wears opens today's readout for everyone, from the
    /// status bar — nothing to buy first. The ornament still opens it in the forest.
    private var statusObserverShown: Bool {
        PiboReleaseScope.pixelHome ? (readoutOpen || statusObserverCardVisible)
            : statusObserverCardVisible
    }

    /// The report's seven columns: this week's records, oldest first.
    private var statusObserverWeek: [HealthDayRecord] {
        let calendar = Calendar.current
        let end = atmosphereClock.now
        let start = calendar.date(byAdding: .day, value: -6,
                                  to: calendar.startOfDay(for: end)) ?? end
        return history.records(from: start, to: end)
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
            canPresentSheet: {
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

    private var stageInput: HomeStageSurface.Input {
        HomeStageSurface.Input(
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
            boOverride: debugBoOverride,
            stateCaption: stateCaption
        )
    }

    /// How Pibo is and why, in words (2026-09-28). Core owns both; the
    /// caption only names them.
    private var stateCaption: PiboStateCaption {
        PiboStateCaption.resolve(.init(
            state: animationPresentation.patState,
            cause: animationPresentation.decision?.cause ?? .missingData,
            pendingCause: animationPresentation.decision?.pendingCause,
            dataUnknownReason: HomePatInputProvider.dataUnknownReason(for: health.dataAvailability),
            hasRealHealthData: store.hasRealHealthData
        ))
    }

    /// The forest is not what the person is looking at right now.
    private var stateCaptionBlocked: Bool {
        scenePhase != .active || stageRenderingPaused || stageObscured
    }

    /// Pibo is already talking, a guide or meal owns the forest, or Pibo is
    /// away from the log (hidden, in the creek, cooling off in the grass).
    private func stateCaptionSuppressed(presentedStateID: String) -> Bool {
        stateCaptionBlocked
            || speechPresentation.line != nil
            || onboarding.dailyHomeGuide != .none
            || presentation.foodProjection != nil
            || sproutPhase != .idle
            || companion.mood.hidesBody
            || presentedStateID == "dive"
            || presentedStateID == "coolhide"
    }

    // MARK: - Pixel stage (decision 069)

    /// Everything the pixel forest draws, read from the same stores the SpriteKit stage
    /// reads. Before Core's first growth answer the renderer shows its own defaults.
    private var pixelLook: PixelStageRenderer.Look {
        let environment = stageEnvironment
        let sleeping = animationPresentation.state == .sleeping
            || animationPresentation.state == .waking
        return HomePixelStageInput(
            hour: Int(environment.localHour.rounded()),
            raining: environment.weather == .rain || environment.weather == .thunderstorm,
            scene: pixelDay?.scene ?? .clearing,
            season: Int((pixelDay?.season ?? .summer).rawValue),
            snow: pixelDay?.snow ?? false,
            reduceMotion: reduceMotion,
            animationStateID: animationPresentation.stateID,
            piboVisible: !companion.mood.hidesBody,
            holdPibo: sleeping || speechPresentation.line != nil,
            growth: growth,
            cues: growthCoordinator.cues,
            mimic: 0,
            boProgress: boLedger.growthProgress,
            leafRipe: boLedger.hasRipeBo,
            decor: decor,
            hammock: ornamentUnlocks.isUnlocked(.hammock),
            observer: PiboReleaseScope.allowsOrnament(.statusObserver)
                && ornamentUnlocks.isUnlocked(.statusObserver),
            grass: companion.grassHotspotEnabled,
            cake: growthCoordinator.anniversaryToday,
            dayCount: store.dayCount,
            day: pixelDay,
            days: days,
            ambient: pixelDay?.ambient ?? 0,
            foodLook: 0,
            foodOnRight: sleeping
        ).look
    }

    /// Binds Pibo's day to the stage that was just built. Called once, from the stage's
    /// `onAppear`, with the renderer Home will keep drawing.
    private func startPixelDay(_ renderer: PixelStageRenderer) {
        guard pixelDay == nil else { return }
        let controller = HomeDayController(director: renderer.director)
        let season = HomeSeasonController(store: seasons)
        season.loadCatalog()

        let dependencies = HomeDayDependencies(
            stateID: { animationPresentation.stateID },
            hour: { stageEnvironment.localHour },
            weather: { stageEnvironment.weather },
            ownedDecor: {
                decor.ownedIn(Int((pixelDay?.scene ?? .clearing).rawValue)).map { Int($0.rawValue) }
            },
            hammock: { ornamentUnlocks.isUnlocked(.hammock) },
            observer: {
                PiboReleaseScope.allowsOrnament(.statusObserver)
                    && ornamentUnlocks.isUnlocked(.statusObserver)
            },
            growth: { growth },
            days: { days },
            dayCount: { store.dayCount },
            stepsToday: { history.record(on: .now)?.steps ?? 0 },
            hasStepsData: { health.dataAvailability.hasReliableData },
            sleepHours: { (history.record(on: .now)?.sleepTotal ?? 0) / 3600 },
            mindfulMinutes: { 0 },
            lastWorkout: {
                guard let workout = history.workouts(on: .now).max(by: { $0.end < $1.end }) else {
                    return nil
                }
                return (kind: Self.coreWorkout(workout.kindRaw),
                        endedAt: workout.end.timeIntervalSince1970 * 1000)
            },
            overlays: {
                HomeDayOverlays(
                    anyOpen: { presentation.activeSheet != nil || fullScreenFeaturePresented
                        || pixelSheet != nil || storyPaper != nil },
                    showDayMap: { open in pixelSheet = open ? .dayMap : nil },
                    showShelf: { open in pixelSheet = open ? .shelf : nil }
                )
            },
            appActive: { scenePhase == .active },
            voiceBusy: { speechPresentation.line != nil || companion.holdsSpeech },
            decorLine: { _ in },
            speak: { line in
                speechPresentation.show(PiboSpeechLine(text: line.text,
                                                      lingerDuration: line.lingerMs / 1000))
            },
            boCollected: { boLedger.lifetimeCollected },
            bodyBands: {
                guard let cues = growthCoordinator.cues else { return [-1, -1] }
                return [cues.stepsBand, cues.sleepBand]
            },
            claimStoryLine: { true },
            setStoryWaiting: { _ in },
            lastMealAt: { -1 },
            mealsToday: { [] },
            openMeal: { _, _ in }
        )
        controller.bind(dependencies)

        let host = HomeSeasonHost(
            director: { renderer.director },
            layout: { renderer.currentLayout },
            scene: { Int((pixelDay?.scene ?? .clearing).rawValue) },
            tone: { growth.tone },
            cursors: { growth },
            dayCount: { store.dayCount },
            hour: { stageEnvironment.localHour },
            boCollected: { boLedger.lifetimeCollected },
            bodyBands: {
                guard let cues = growthCoordinator.cues else { return [-1, -1] }
                return [cues.stepsBand, cues.sleepBand]
            },
            canStage: { scenePhase == .active && presentation.activeSheet == nil },
            claim: { true },
            setWaiting: { _ in },
            speak: { text in
                speechPresentation.show(PiboSpeechLine(text: text))
            },
            showStoryPaper: { page in
                // Decision 059: the report, a letter or the old notebook, over the forest.
                pixelSheet = nil
                storyPaper = page
            },
            changed: { controller.revision += 1 },
            lifeFlags: { controller.lifeFlags(Date().timeIntervalSince1970 * 1000) },
            feel: { _ in }
        )
        season.bind(host)

        controller.story = season
        renderer.brain = controller
        pixelSeason = season
        pixelDay = controller
        controller.start()
        controller.onStageLayout(renderer.currentLayout)

        // Decision 057: growth moments play on this stage — the effects queue needs a
        // target, so the controller is bound once the pixel stage exists.
        growthUI.stageEffects.attach(renderer)
        growthUI.bind(HomeGrowthController.Dependencies(
            growth: { growth },
            coordinator: { growthCoordinator },
            decor: { decor },
            ledger: { boLedger },
            speech: { speechPresentation },
            companionBusy: { companion.replySheetOpen || companion.holdsSpeech },
            dayCount: { store.dayCount },
            polaroids: { polaroids },
            appActive: { scenePhase == .active },
            overlayOpen: {
                presentation.activeSheet != nil || fullScreenFeaturePresented
                    || pixelSheet != nil || storyPaper != nil
                    || growthUI.levelUpVisible || growthUI.polaroidVisible
            },
            // Decision 058's untold trip would turn the away summary into a diary line;
            // the diary's wording is not ported yet, so the generic summary plays.
            awayDiary: { nil },
            lastWorkoutEndedAt: { store.lastWorkoutEndedAt },
            lastWorkoutKind: { nil }
        ))
        growthUI.start()

        #if DEBUG
        // `-PiboGrowthMoment=growth:level` plays one growth moment once the stage is up:
        // the simulator cannot drive the queue on its own.
        if let raw = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("-PiboGrowthMoment=") })?
            .dropFirst("-PiboGrowthMoment=".count) {
            let moment = String(raw)
            Task {
                try? await Task.sleep(for: .seconds(2))
                LPLog.day.notice("growth moment \(self.growthUI.debugRun(moment), privacy: .public)")
            }
        }
        // `-PiboSeasonMoment=season:notebook` runs one season debug step (a beat, a letter,
        // or one of the paper pages the pod and the mailbox open).
        if let raw = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("-PiboSeasonMoment=") })?
            .dropFirst("-PiboSeasonMoment=".count) {
            let moment = String(raw)
            Task {
                try? await Task.sleep(for: .seconds(2))
                LPLog.day.notice("season moment \(season.debugRun(moment), privacy: .public)")
            }
        }
        #endif

        LPLog.day.info(
            "pixel stage layout \(renderer.currentLayout.width, privacy: .public)x\(renderer.currentLayout.height, privacy: .public) ground=\(renderer.currentLayout.groundY, privacy: .public)"
        )
    }

    /// `WorkoutRecord.kindRaw` spells the same cases Core's echo workout does.
    private static func coreWorkout(_ raw: String) -> PiboCoreEchoWorkout {
        switch raw {
        case "run": .run
        case "walk": .walk
        case "cycle": .cycle
        case "swim": .swim
        case "hiit": .hiit
        case "yoga": .yoga
        case "other": .other
        default: .none
        }
    }

    private var homeScene: some View {
        let input = stageInput
        return ZStack {
            if PiboReleaseScope.pixelHome {
                // Decision 069: the procedural pixel forest. It brings its own day: the
                // controller below drives Pibo through Core's `day_choose`, and the season
                // controller stages the story's beats on the same director.
                PixelStageView(look: pixelLook,
                               onStageReady: startPixelDay,
                               onLayoutChanged: { pixelDay?.onStageLayout($0) },
                               onPat: {
                                   // Decision 061: a double tap on a shape it has taken
                                   // helps it back; it is not a pat.
                                   if pixelDay?.onPat() == true { return }
                                   stageHandlers.pat()
                                   growthUI.afterPat()
                               },
                               onGlance: {
                                   // A glance acknowledges whatever Pibo was saying.
                                   speechPresentation.dismiss()
                               },
                               onPlaceTapped: { pixelDay?.onPlaceTapped($0) ?? false },
                               onDecorTapped: { id in
                                   growthUI.onDecorTapped(id)
                               },
                               onGrassTapped: { companion.onGrassTapped() },
                               onPokeSound: {
                                   PiboSoundEffectService.shared.play(.boSproutTouch)
                               },
                               onCollectBo: { stageHandlers.collectBo() },
                               onHarvestCue: { pixelHarvestSound.playHarvest($0) },
                               onShake: { growthUI.onShake(peakAcceleration: $0) },
                               onPixelCue: { cue, hushed in
                                   PiboSoundEffectService.shared.play(cue, hushed: hushed)
                               })
            } else {
                HomeStageSurface(
                    input: input,
                    commandController: stageCommands,
                    handlers: stageHandlers
                )
            }

            HomeStateCaptionOverlay(
                caption: stateCaption,
                anchor: captionAnchor,
                isPresented: stateCaptionPresenter.isShown
                    && !stateCaptionSuppressed(presentedStateID: input.animationStateID)
            )

            walkEchoOverlay
                .zIndex(5)

            chromeContent
                .accessibilityHidden(stagePaused || statusObserverShown)
                .opacity(statusObserverShown ? 0 : 1)
                .allowsHitTesting(!statusObserverShown)

            // Decision 057's sheets, over the forest but under the full-screen covers.
            if PiboReleaseScope.pixelHome, let pixelSheet {
                PixelSheetHost(
                    kind: pixelSheet,
                    growth: growth,
                    wishes: wishes,
                    decor: decor,
                    ornaments: ornamentUnlocks,
                    ledger: boLedger,
                    dayCount: store.dayCount,
                    localHour: Int(HomeAtmosphereClock.localHour(at: atmosphereClock.now)),
                    days: days,
                    day: pixelDay,
                    season: Int((pixelDay?.season ?? .summer).rawValue),
                    onClose: { self.pixelSheet = nil },
                    onOpenFootprints: { _ in
                        // Decision 063: the walk diary lives in the footprints. The page
                        // has no day focus yet, so this lands on its newest day.
                        self.pixelSheet = nil
                        presentation.showHistory = true
                    }
                )
                .zIndex(40)
                .transition(.opacity)
            }

            // Decision 059's paper: the report home, a letter, or the old notebook.
            if PiboReleaseScope.pixelHome, let storyPaper {
                StoryPaperHost(page: storyPaper, onClose: { self.storyPaper = nil })
                    .zIndex(41)
                    .transition(.opacity)
            }

            // Decision 057's level-up reveal and evening print, over everything else.
            if PiboReleaseScope.pixelHome, growthUI.levelUpVisible {
                ZStack {
                    PixelUIColor.scrim
                        .ignoresSafeArea()
                        .onTapGesture { growthUI.closeLevelUp() }
                    LevelUpCard(level: growthUI.levelUpLevel, line: growthUI.levelUpLine,
                                onClose: { growthUI.closeLevelUp() })
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(45)
                .transition(.opacity)
            }

            if PiboReleaseScope.pixelHome, growthUI.polaroidVisible, let shot = growthUI.polaroid {
                ZStack {
                    PixelUIColor.scrim
                        .ignoresSafeArea()
                        .onTapGesture { growthUI.closePolaroid() }
                    PolaroidCard(shot: shot, onClose: { growthUI.closePolaroid() })
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(46)
                .transition(.opacity)
            }

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

            if statusObserverShown {
                Group {
                    if PiboReleaseScope.pixelHome {
                        // Decision 062: the badge's readout, printed on Pibo's paper.
                        GeometryReader { proxy in
                            StatusObserverReportHost(
                                record: history.record(on: atmosphereClock.now),
                                historyRecords: statusObserverWeek,
                                availability: health.dataAvailability,
                                usesMock: statusObserverUsesSample,
                                dayCount: store.dayCount,
                                badgeState: piboPixelActivity(animationPresentation.stateID).rawValue,
                                badgeCracked: !seasons.podFixed,
                                panelTop: 72,
                                stageWidth: proxy.size.width,
                                stageHeight: proxy.size.height,
                                onClose: closeReadout,
                                onCheckHealth: {
                                    closeReadout()
                                    speechPresentation.dismiss()
                                    presentation.activeSheet = .healthDataStatus
                                }
                            )
                        }
                    } else {
                        statusObserverPanel
                    }
                }
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
            // State caption timing (HarmonyOS parity): arrival 0.9 s, back to
            // the forest 0.7 s, a new state or cause 0.42 s, a glance at once.
            .onAppear {
                if !stateCaptionBlocked { stateCaptionPresenter.show(after: HomeStateCaptionPresenter.arrivalDelay) }
            }
            .onChange(of: stateCaptionBlocked) { _, blocked in
                if blocked {
                    stateCaptionPresenter.hide()
                } else {
                    stateCaptionPresenter.show(after: HomeStateCaptionPresenter.returnDelay)
                }
            }
            .onChange(of: stateCaption) { _, _ in
                guard !stateCaptionBlocked else { return }
                stateCaptionPresenter.show(after: HomeStateCaptionPresenter.changeDelay)
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
                stateCaptionPresenter.hide()
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
                // Screenshot hook: the corner camera tap, through the real
                // account guard (the Simulator cannot synthesize taps).
                if ProcessInfo.processInfo.arguments.contains("-PiboOpenCamera") {
                    presentation.openMealCapture(isLoggedIn: auth.phase == .loggedIn)
                }
                // Art verification: the viewfinder itself, past the account gate. The
                // Simulator has no camera and no session, so the guard above would stop at
                // the login sheet before the pixel framing guide is ever laid out.
                if ProcessInfo.processInfo.arguments.contains("-PiboOpenCameraNow") {
                    presentation.showCamera = true
                }
                // Screenshot hook for the settings page (the gear needs a tap).
                if ProcessInfo.processInfo.arguments.contains("-PiboOpenSettings") {
                    presentation.showSettings = true
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
                // `-PiboForestHour=10` pins the forest's light for screenshots, the same
                // override the 时间覆盖 chip writes.
                if let raw = ProcessInfo.processInfo.arguments
                    .first(where: { $0.hasPrefix("-PiboForestHour=") })?
                    .dropFirst("-PiboForestHour=".count),
                   let hour = Double(raw) {
                    store.debugForestHour = hour
                }
                // `-PiboPixelSheet=growth|wishes|decor|map|shelf` opens a pixel sheet on
                // launch: the simulator cannot synthesise a tap on the HUD.
                if let raw = ProcessInfo.processInfo.arguments
                    .first(where: { $0.hasPrefix("-PiboPixelSheet=") })?
                    .dropFirst("-PiboPixelSheet=".count) {
                    pixelSheet = switch raw {
                    case "growth": .growth
                    case "wishes": .wishes
                    case "decor": .decor
                    case "map": .dayMap
                    case "shelf": .shelf
                    default: nil
                    }
                }
                // `-PiboObserver=1` opens the readout: the simulator cannot tap the HUD.
                if ProcessInfo.processInfo.arguments.contains("-PiboObserver=1") {
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        if PiboReleaseScope.pixelHome {
                            readoutOpen = true
                        } else if !statusObserverPresentation.isOpen {
                            toggleStatusObserver()
                        }
                    }
                }
                #endif
                shadowSync.setSnapshotDraft(shadowSnapshotDraft)
                reconcileShadowFriendFlow()
                soundscape.setCoLightCount(coLightCount(ornamentLights.lit))
                resumeOrnamentDiscoveryIfNeeded()
            }
            .onDisappear {
                // The growth queue belongs to this screen; Home is the only place it plays.
                growthUI.stop()
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
            // On-demand login for the meal camera. Resuming waits for the
            // cover's own dismissal so the picker or camera never overlaps it.
            .fullScreenCover(
                isPresented: presentation.loginBinding,
                onDismiss: {
                    presentation.resumeAfterLogin(isLoggedIn: auth.phase == .loggedIn)
                }
            ) {
                NavigationStack {
                    LoginFlowView(
                        purpose: presentation.loginPurpose,
                        onComplete: { presentation.showLogin = false },
                        onClose: presentation.cancelLogin
                    )
                }
            }
            // Only a real session end: going back from the code page also
            // publishes `.loggedOut` (from `.codeSent`) and must keep the page.
            .onChange(of: auth.phase) { oldPhase, phase in
                if oldPhase == .loggedIn, phase == .loggedOut {
                    presentation.closeAccountSurfacesForSessionEnd()
                }
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
                        if !presentation.presentQueuedCameraIfNeeded(
                            isLoggedIn: auth.phase == .loggedIn
                        ) {
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
                // Decision 057/069: the pixel HUD owns the top-left corner and shows the
                // `bo` balance itself, exactly as HarmonyOS's `GrowthChrome` does — so the
                // old floating chip retires with the SpriteKit stage.
                balanceChip: PiboReleaseScope.pixelHome ? nil : AnyView(boBalanceChip),
                cameraEnabled: featureAccess.cameraEnabled,
                accountLoggedIn: auth.phase == .loggedIn,
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

            // Decision 057's growth HUD, top-left over the forest (HarmonyOS
            // `HomePage.GrowthChrome`). Hidden under full-screen surfaces.
            if PiboReleaseScope.pixelHome, !fullScreenFeaturePresented,
               pixelSheet == nil, storyPaper == nil,
               !growthUI.levelUpVisible, !growthUI.polaroidVisible {
                growthHud
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 12)
                    .padding(.top, 10)
                    .zIndex(6)
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
        handlers.captionAnchorChanged = { point in
            if captionAnchor != point { captionAnchor = point }
        }
        handlers.glance = { stateCaptionPresenter.show(after: .zero) }
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

    /// Decision 057/062: the growth HUD. Every value here is already a Core answer or a
    /// ledger balance; the view only shows them and routes taps.
    private var growthHud: some View {
        let hour = Int(HomeAtmosphereClock.localHour(at: atmosphereClock.now))
        let visibleWishes = wishes.visible(localHour: hour)
        let snapshot = WellnessReadout.snapshot(of: history.record(on: atmosphereClock.now))
        return GrowthHud(
            level: growth.level,
            levelProgress: growth.levelProgress(),
            xpIntoLevel: growth.xpIntoLevel,
            xpForNext: growth.xpForNext,
            hearts: growth.hearts,
            badgeState: piboPixelActivity(animationPresentation.stateID).rawValue,
            badgeCracked: !seasons.podFixed,
            readout: AppLocalization.text(
                WellnessReadout.conclusion(snapshot, availability: health.dataAvailability)
            ),
            boBalance: boLedger.availableBo,
            wishesDone: visibleWishes.filter(\.done).count,
            wishesTotal: visibleWishes.count,
            decorAvailable: decor.hasPurchasable(
                level: growth.level,
                balance: boLedger.availableBo
            ),
            onOpenGrowth: {
                LPHaptics.tap()
                pixelSheet = .growth
            },
            onOpenWishes: {
                LPHaptics.tap()
                wishes.markEveningSeen(localHour: hour)
                pixelSheet = .wishes
            },
            onOpenDecor: {
                LPHaptics.tap()
                pixelSheet = .decor
            },
            onOpenReadout: {
                LPHaptics.tap()
                if PiboReleaseScope.pixelHome {
                    // Decision 062: the badge opens today's readout for everyone, and the
                    // report prints with its own little whirr (decision 063).
                    PiboSoundEffectService.shared.play(.reportPrint)
                    readoutOpen = true
                } else {
                    PiboSoundEffectService.shared.play(.observerOpen)
                    if !statusObserverPresentation.isOpen { toggleStatusObserver() }
                }
            }
        )
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

    /// The badge's readout closes both ways it can be open.
    private func closeReadout() {
        readoutOpen = false
        closeStatusObserver()
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

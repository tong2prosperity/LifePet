import PiboCore

struct HomePresentationPolicy {
    private let sceneIsActive: () -> Bool
    private let cameraPresented: () -> Bool
    private let gamesPresented: () -> Bool
    private let historyPresented: () -> Bool
    private let walkDoodlePresented: () -> Bool
    private let settingsPresented: () -> Bool
    private let storyRecoveryPresented: () -> Bool
    private let sheetPresented: () -> Bool
    private let sheetDismissalInProgress: () -> Bool
    private let sproutFlowIsIdle: () -> Bool

    init(
        sceneIsActive: @autoclosure @escaping () -> Bool,
        cameraPresented: @autoclosure @escaping () -> Bool,
        gamesPresented: @autoclosure @escaping () -> Bool,
        historyPresented: @autoclosure @escaping () -> Bool,
        walkDoodlePresented: @autoclosure @escaping () -> Bool,
        settingsPresented: @autoclosure @escaping () -> Bool,
        storyRecoveryPresented: @autoclosure @escaping () -> Bool,
        sheetPresented: @autoclosure @escaping () -> Bool,
        sheetDismissalInProgress: @autoclosure @escaping () -> Bool,
        sproutFlowIsIdle: @autoclosure @escaping () -> Bool
    ) {
        self.sceneIsActive = sceneIsActive
        self.cameraPresented = cameraPresented
        self.gamesPresented = gamesPresented
        self.historyPresented = historyPresented
        self.walkDoodlePresented = walkDoodlePresented
        self.settingsPresented = settingsPresented
        self.storyRecoveryPresented = storyRecoveryPresented
        self.sheetPresented = sheetPresented
        self.sheetDismissalInProgress = sheetDismissalInProgress
        self.sproutFlowIsIdle = sproutFlowIsIdle
    }

    /// Production adapter for Home's feature-presentation owner. The policy
    /// keeps reading the observable reference so callers do not duplicate its
    /// individual cover flags.
    init(
        sceneIsActive: @autoclosure @escaping () -> Bool,
        presentation: HomePresentationState,
        sproutFlowIsIdle: @autoclosure @escaping () -> Bool
    ) {
        self.sceneIsActive = sceneIsActive
        cameraPresented = { presentation.showCamera }
        gamesPresented = { presentation.showGames }
        historyPresented = { presentation.showHistory }
        walkDoodlePresented = { presentation.showWalkDoodle }
        settingsPresented = { presentation.showSettings }
        storyRecoveryPresented = { presentation.showStoryRecovery }
        sheetPresented = { presentation.activeSheet != nil }
        sheetDismissalInProgress = { presentation.sheetDismissalInProgress }
        self.sproutFlowIsIdle = sproutFlowIsIdle
    }

    /// Pause the 60fps stage loop while a feature covers it — the full-screen
    /// covers plus sheets, which on iOS occlude the stage too.
    var stagePaused: Bool {
        cameraPresented()
            || gamesPresented()
            || historyPresented()
            || walkDoodlePresented()
            || settingsPresented()
            || storyRecoveryPresented()
            || sheetPresented()
    }

    var fullScreenFeaturePresented: Bool {
        cameraPresented()
            || gamesPresented()
            || historyPresented()
            || walkDoodlePresented()
            || settingsPresented()
            || storyRecoveryPresented()
    }

    var boProgressFeedbackEnabled: Bool {
        sceneIsActive()
            && !stagePaused
            && !sheetDismissalInProgress()
            && sproutFlowIsIdle()
    }

    var soundscapePresentation: SoundscapePresentation {
        guard sceneIsActive() else { return .suspended }
        guard !fullScreenFeaturePresented else { return .suspended }
        return sheetPresented() ? .suspended : .active
    }

    func statusObserverCardVisible(
        isPinned: @autoclosure () -> Bool,
        recoveryStatusGranted: @autoclosure () -> Bool,
        foodProjectionPresented: @autoclosure () -> Bool,
        transientNoticePresented: @autoclosure () -> Bool,
        shadowLightBannerPresented: @autoclosure () -> Bool
    ) -> Bool {
        sceneIsActive()
            && isPinned()
            && recoveryStatusGranted()
            && !stagePaused
            && !sheetDismissalInProgress()
            && sproutFlowIsIdle()
            && !foodProjectionPresented()
            && !transientNoticePresented()
            && !shadowLightBannerPresented()
    }

    func pendingAchievement(
        animationStateID: @autoclosure () -> String,
        pendingAchievement: @autoclosure () -> PiboAnimationAchievementPayload?
    ) -> PiboAnimationAchievementPayload? {
        guard sceneIsActive(),
              !sheetPresented(),
              !fullScreenFeaturePresented,
              PiboCoreAnimationAdapter.achievementPresentationAllowed(
                  in: animationStateID()
              ),
              let pendingAchievement = pendingAchievement()
        else { return nil }
        return pendingAchievement
    }

    func morningSleepPresentation<Presentation>(
        sleepReviewGranted: @autoclosure () -> Bool,
        consumablePresentation: @autoclosure () -> Presentation?
    ) -> Presentation? {
        guard sceneIsActive(),
              sleepReviewGranted(),
              !sheetPresented(),
              !fullScreenFeaturePresented,
              sproutFlowIsIdle(),
              let consumablePresentation = consumablePresentation()
        else { return nil }
        return consumablePresentation
    }

    func shouldPresentStressCard(
        pendingCardOpen: @autoclosure () -> Bool
    ) -> Bool {
        pendingCardOpen()
            && !fullScreenFeaturePresented
            && !sheetPresented()
    }

    func shouldAnnounceFirstRipeBo(
        hasRipeBo: @autoclosure () -> Bool,
        wasAnnounced: @autoclosure () -> Bool,
        speechIsAbsent: @autoclosure () -> Bool,
        idleSpeechContextAvailable: @autoclosure () -> Bool
    ) -> Bool {
        hasRipeBo()
            && !wasAnnounced()
            && sceneIsActive()
            && !stagePaused
            && sproutFlowIsIdle()
            && speechIsAbsent()
            && idleSpeechContextAvailable()
    }
}

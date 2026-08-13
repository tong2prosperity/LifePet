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

    var boCounterFeedbackEnabled: Bool {
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
}

import os
import SwiftData
import SwiftUI
import UserNotifications

/// Which top-level surface the shell shows. Pure so the gate is testable.
///
/// Order (2026-09-14/15 decision, supersedes 049/051 "login never blocks"):
/// first-run onboarding → required phone login → Home. A restored valid JWT
/// goes straight to Home; logout or account deletion falls back to login.
enum RootGate: Hashable {
    case onboarding
    case login
    case home

    static func resolve(
        shouldPresentFirstRun: Bool,
        isAuthenticated: Bool,
        bypassesGates: Bool = false
    ) -> RootGate {
        if bypassesGates { return .home }
        if shouldPresentFirstRun { return .onboarding }
        return isAuthenticated ? .home : .login
    }
}

/// Pibo shell: daily-persona first run, then the required login gate, then Home.
struct RootView: View {
    @Environment(OnboardingStateStore.self) private var onboarding
    @Environment(BoLedgerStore.self) private var boLedger
    @Environment(AuthService.self) private var auth
    @Environment(HealthDataService.self) private var health
    @Environment(PetStateStore.self) private var store
    @Environment(PiboSpeechService.self) private var piboSpeech
    @Environment(OrnamentUnlockStore.self) private var ornamentUnlocks
    @Environment(OrnamentLightStore.self) private var ornamentLights
    @Environment(WalkDoodleProgressStore.self) private var walkDoodleProgress
    @Environment(\.modelContext) private var modelContext
    @AppStorage(PiboPersistenceKeys.Defaults.appLanguage) private var appLanguage: String = AppLanguage.preferred.rawValue
    #if DEBUG
    @State private var showWaterLab = false
    @State private var showCharacterLab = false
    @State private var debugOnboardingPreviewStep: DailySetupStep? =
        DailyOnboardingPreviewHost.launchStep()
    /// 小游戏在首发范围外（`PiboReleaseScope.miniGames`）。`-PiboOpenMiniGame`
    /// 本身就算作打开，所以这里判一次开关只是让"谁在管这条直通"有据可查。
    @State private var debugMiniGame: MiniGameKind? = PiboReleaseScope.miniGames
        ? MiniGameKind.debugRequestedLaunchGame()
        : nil

    private var debugOpensHistory: Bool {
        ProcessInfo.processInfo.arguments.contains("-PiboOpenHistory")
    }

    /// Screenshot/automation launches jump straight to Home, past both the
    /// first run and the login gate (the simulator cannot log in by itself).
    private var debugBypassesOnboarding: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return debugOpensHistory
            // 通用跳过：截图验证首页时不需要连带打开某个别的界面。
            // 在这个开关出现之前只能借 `-PiboShowMorningSleep` 之类的参数绕过，
            // 而那些会顺手弹出一个盖住首页的 sheet。
            || arguments.contains("-PiboSkipOnboarding")
            || arguments.contains("-PiboOpenGames")
            || arguments.contains("-PiboShowStatusObserver")
            || arguments.contains("-PiboShowMorningSleep")
            || arguments.contains { $0.hasPrefix("-PiboShowAchievement=") }
            || arguments.contains("-PiboOpenMiniGame")
            || arguments.contains { $0.hasPrefix("-PiboOpenMiniGame=") }
    }
    #endif

    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguage) ?? .preferred
    }

    /// One observable read of the auth phase decides the gate, so a successful
    /// login or a logout switches immediately.
    private var gate: RootGate {
        #if DEBUG
        let bypass = debugBypassesOnboarding
        #else
        let bypass = false
        #endif
        return RootGate.resolve(
            shouldPresentFirstRun: onboarding.shouldPresentFirstRun,
            isAuthenticated: auth.phase == .loggedIn,
            bypassesGates: bypass
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                #if DEBUG
                if debugMiniGame != nil {
                    Color.clear
                        .ignoresSafeArea()
                } else {
                    gateContent
                }
                #else
                gateContent
                #endif
            }
        }
        // A gate change rebuilds the whole stack: logging out (or deleting the
        // account) closes every Home cover, sheet and pushed Settings page, and
        // the next login starts from a clean Home.
        .id(gate)
        // Language follows the stored value; the in-app 中/EN switch button was
        // removed per product direction (2026-06-09).
        .environment(\.locale, language.locale)
        .onChange(of: auth.accountDeletionRevision) { _, _ in
            resetLocalStateAfterAccountDeletion()
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-PiboWaterLab") {
                showWaterLab = true
            }
            if ProcessInfo.processInfo.arguments.contains("-PiboCharacterLab") {
                showCharacterLab = true
            }
        }
        .fullScreenCover(isPresented: $showWaterLab) {
            WaterLabView()
        }
        .fullScreenCover(isPresented: $showCharacterLab) {
            CharacterLabView()
        }
        .fullScreenCover(item: $debugMiniGame) { game in
            MiniGameHostView(kind: game, onWalkDoodleSaved: { _ in })
        }
        .fullScreenCover(item: $debugOnboardingPreviewStep) { step in
            DailyOnboardingPreviewHost(startingAt: step)
        }
        #endif
    }

    @ViewBuilder
    private var gateContent: some View {
        switch gate {
        case .home:
            HomeView()
        case .onboarding:
            if PiboReleaseScope.temporaryCooperationOnboarding {
                HealthAuthView(onContinue: {})
            } else {
                // `LegacyHealthAuthView` (rescue/amnesia story) stays in the
                // project as inventory but is no longer mounted (decision 049).
                DailyOnboardingView(
                    onboarding: onboarding,
                    onConnectHealth: connectHealth,
                    onComplete: completeDailyOnboarding
                )
            }
        case .login:
            LoginFlowView(onComplete: {})
        }
    }

    private func connectHealth() async -> HealthDataService.OnboardingReadiness? {
        LPLog.onboarding.notice("User chose: connect HealthKit")
        await health.requestAuthorization()
        let readiness = await health.onboardingReadiness()
        store.demoMode = false
        Analytics.track(.healthAuth, screen: "onboarding", ["granted": .bool(readiness.isReady)])
        return readiness
    }

    /// Completion is idempotent: a repeated callback never moves `completedAt`
    /// or the `bo` eligibility boundary, and no story consent is written.
    private func completeDailyOnboarding() {
        let completedAt = Date()
        guard onboarding.completeDailyFirstRun(at: completedAt) else { return }
        LPLog.onboarding.notice("Daily onboarding finished")
        store.petName = "PIBO"
        store.demoMode = false
        boLedger.setEligibilityBoundary(completedAt, source: .legacyOnboarding)
        LPHaptics.success()
    }

    /// The server already erased the account and tokens are gone. Schedule the
    /// full on-disk wipe for the next cold launch (before any store opens) and
    /// reset the live stores now so the user lands in first-run onboarding.
    private func resetLocalStateAfterAccountDeletion() {
        LocalDataEraser.schedule()
        HomeResetCoordinator.run(
            speech: piboSpeech,
            store: store,
            boLedger: boLedger,
            onboarding: onboarding,
            ornamentUnlocks: ornamentUnlocks,
            ornamentLights: ornamentLights
        )
        walkDoodleProgress.reset()
        do {
            try modelContext.delete(model: HealthDayRecord.self)
            try modelContext.delete(model: WorkoutRecord.self)
            try modelContext.delete(model: FoodPhoto.self)
            try modelContext.delete(model: WalkDoodleRecord.self)
            try modelContext.save()
        } catch {
            LPLog.app.error("account deletion: in-session history wipe failed: \(error.localizedDescription, privacy: .public)")
        }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

#if DEBUG
extension DailySetupStep: Identifiable {
    var id: String { rawValue }
}
#endif

#Preview {
    RootView()
        .environment(HealthDataService(metrics: []))
        .environment(MorningSleepCoordinator())
        .environment(PetStateStore())
        .environment(PiboSpeechService())
        .environment(OnboardingStateStore())
        .environment(BoLedgerStore())
        .environment(WalkDoodleProgressStore())
        .environment(OrnamentUnlockStore())
        .environment(OrnamentLightStore())
        .environment(AuthService())
        .preferredColorScheme(.light)
}

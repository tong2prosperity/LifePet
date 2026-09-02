import SwiftUI

/// Pibo shell. First launch runs the versioned six-scene local flow; account
/// login remains available from Settings and never blocks the product.
struct RootView: View {
    @Environment(OnboardingStateStore.self) private var onboarding
    @Environment(BoLedgerStore.self) private var boLedger
    @AppStorage(PiboPersistenceKeys.Defaults.appLanguage) private var appLanguage: String = AppLanguage.preferred.rawValue
    #if DEBUG
    @State private var showWaterLab = false
    @State private var showCharacterLab = false
    /// 小游戏在首发范围外（`PiboReleaseScope.miniGames`）。`-PiboOpenMiniGame`
    /// 本身就算作打开，所以这里判一次开关只是让"谁在管这条直通"有据可查。
    @State private var debugMiniGame: MiniGameKind? = PiboReleaseScope.miniGames
        ? MiniGameKind.debugRequestedLaunchGame()
        : nil

    private var debugOpensHistory: Bool {
        ProcessInfo.processInfo.arguments.contains("-PiboOpenHistory")
    }

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

    var body: some View {
        NavigationStack {
            Group {
            #if DEBUG
            if debugMiniGame != nil {
                Color.clear
                    .ignoresSafeArea()
            } else if !onboarding.shouldPresentFirstRun || debugBypassesOnboarding {
                HomeView()
            } else if PiboReleaseScope.temporaryCooperationOnboarding {
                HealthAuthView(onContinue: {})
            } else {
                LegacyHealthAuthView(onContinue: completeLegacyOnboarding)
            }
            #else
            if !onboarding.shouldPresentFirstRun {
                HomeView()
            } else if PiboReleaseScope.temporaryCooperationOnboarding {
                HealthAuthView(onContinue: {})
            } else {
                LegacyHealthAuthView(onContinue: completeLegacyOnboarding)
            }
            #endif
            }
        }
        // Language follows the stored value; the in-app 中/EN switch button was
        // removed per product direction (2026-06-09).
        .environment(\.locale, language.locale)
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
        #endif
    }

    private func completeLegacyOnboarding() {
        let completedAt = Date()
        onboarding.completeFirstRun(at: completedAt)
        boLedger.setEligibilityBoundary(completedAt, source: .legacyOnboarding)
    }
}

#Preview {
    RootView()
        .environment(HealthDataService(metrics: []))
        .environment(MorningSleepCoordinator())
        .environment(PetStateStore())
        .environment(PiboSpeechService())
        .environment(OnboardingStateStore())
        .environment(BoLedgerStore())
        .environment(WalkDoodleProgressStore())
        .preferredColorScheme(.light)
}

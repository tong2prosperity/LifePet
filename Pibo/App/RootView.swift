import SwiftUI

/// Pibo shell. On first launch we show `HealthAuthView`; once the user
/// connects (or explicitly opts into demo / "later"), we flip to the tabs.
/// The "have we asked" flag is stored in `UserDefaults` so we don't re-prompt.
struct RootView: View {
    @AppStorage(PiboPersistenceKeys.Defaults.onboardingDone) private var onboardingDone: Bool = false
    @AppStorage(PiboPersistenceKeys.Defaults.appLanguage) private var appLanguage: String = AppLanguage.preferred.rawValue
    #if DEBUG
    @State private var showWaterLab = false
    @State private var debugMiniGame: MiniGameKind? = MiniGameKind.debugRequestedLaunchGame()

    private var debugOpensHistory: Bool {
        ProcessInfo.processInfo.arguments.contains("-PiboOpenHistory")
    }

    private var debugBypassesOnboarding: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return debugOpensHistory
            || arguments.contains("-PiboOpenGames")
            || arguments.contains("-PiboShowMorningSleep")
            || arguments.contains("-PiboOpenMiniGame")
            || arguments.contains { $0.hasPrefix("-PiboOpenMiniGame=") }
    }
    #endif

    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguage) ?? .preferred
    }

    var body: some View {
        Group {
            #if DEBUG
            if debugMiniGame != nil {
                Color.clear
                    .ignoresSafeArea()
            } else if onboardingDone || debugBypassesOnboarding {
                HomeView()
            } else {
                HealthAuthView(onContinue: { onboardingDone = true })
            }
            #else
            if onboardingDone {
                // No bottom tab bar: the home is the only floor; swiping the grab
                // bar up reveals the 数据二楼 (see `HomeView`). 图鉴 / 一起 are not
                // wired to an entry point yet — re-surface later (二楼 or a menu).
                HomeView()
            } else {
                HealthAuthView(onContinue: { onboardingDone = true })
            }
            #endif
        }
        // Language follows the stored value; the in-app 中/EN switch button was
        // removed per product direction (2026-06-09).
        .environment(\.locale, language.locale)
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-PiboWaterLab") {
                showWaterLab = true
            }
        }
        .fullScreenCover(isPresented: $showWaterLab) {
            WaterLabView()
        }
        .fullScreenCover(item: $debugMiniGame) { game in
            MiniGameHostView(kind: game, onWalkDoodleSaved: { _ in })
        }
        #endif
    }
}

#Preview {
    RootView()
        .environment(HealthDataService(metrics: []))
        .environment(MorningSleepCoordinator())
        .environment(PetStateStore())
        .environment(PiboSpeechService())
        .preferredColorScheme(.light)
}

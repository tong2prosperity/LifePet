import SwiftUI
import SwiftData

/// Pibo shell. On first launch we show `HealthAuthView`; once the user
/// connects (or explicitly opts into demo / "later"), we flip to the tabs.
/// The "have we asked" flag is stored in `UserDefaults` so we don't re-prompt.
struct RootView: View {
    @AppStorage(PiboPersistenceKeys.Defaults.onboardingDone) private var onboardingDone: Bool = false
    @AppStorage(PiboPersistenceKeys.Defaults.appLanguage) private var appLanguage: String = AppLanguage.preferred.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguage) ?? .preferred
    }

    var body: some View {
        Group {
            if onboardingDone {
                // No bottom tab bar: the home is the only floor; swiping the grab
                // bar up reveals the 数据二楼 (see `HomeView`). 图鉴 / 一起 are not
                // wired to an entry point yet — re-surface later (二楼 or a menu).
                HomeView()
            } else {
                HealthAuthView(onContinue: { onboardingDone = true })
            }
        }
        // Language follows the stored value; the in-app 中/EN switch button was
        // removed per product direction (2026-06-09).
        .environment(\.locale, language.locale)
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "RootViewPreview")!
    defaults.set(false, forKey: PiboPersistenceKeys.Defaults.onboardingDone)
    return RootView()
        .defaultAppStorage(defaults)
        .environment(HealthDataService(metrics: []))
        .environment(PetStateStore())
        .environment(RootPreviewData.history)
        .modelContainer(RootPreviewData.container)
        .preferredColorScheme(.light)
}

private enum RootPreviewData {
    static let container = try! ModelContainer(
        for: HealthDayRecord.self, WorkoutRecord.self, FoodPhoto.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))

    static let history = HealthHistoryStore(context: container.mainContext)
}

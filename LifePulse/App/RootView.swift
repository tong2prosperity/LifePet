import SwiftUI

/// LifePet shell. On first launch we show `HealthAuthView`; once the user
/// connects (or explicitly opts into demo / "later"), we flip to the tabs.
/// The "have we asked" flag is stored in `UserDefaults` so we don't re-prompt.
struct RootView: View {
    @AppStorage("lifepet.onboardingDone") private var onboardingDone: Bool = false

    var body: some View {
        Group {
            if onboardingDone {
                MainTabs()
            } else {
                HealthAuthView(onContinue: { onboardingDone = true })
            }
        }
    }
}

private struct MainTabs: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("主页", systemImage: "house.fill") }
            CatalogView()
                .tabItem { Label("图鉴", systemImage: "book.fill") }
            TogetherView()
                .tabItem { Label("一起", systemImage: "person.2.fill") }
        }
        .tint(LP.Colors.coral)
    }
}

#Preview {
    RootView()
        .environment(HealthDataService(metrics: []))
        .environment(PetStateStore())
        .preferredColorScheme(.light)
}

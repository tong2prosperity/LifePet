import SwiftUI

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
                MainTabs()
            } else {
                HealthAuthView(onContinue: { onboardingDone = true })
            }
        }
        .environment(\.locale, language.locale)
        .overlay(alignment: .topTrailing) {
            LanguageMenu(selection: $appLanguage)
                .padding(.top, 8)
                .padding(.trailing, 12)
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

private struct LanguageMenu: View {
    @Binding var selection: String

    private var language: AppLanguage {
        AppLanguage(rawValue: selection) ?? .chinese
    }

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { option in
                Button {
                    selection = option.rawValue
                } label: {
                    Label(option.title, systemImage: option == language ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .semibold))
                Text(language.shortTitle)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(LP.Colors.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(LP.Colors.paperCard.opacity(0.94)))
            .overlay(Capsule(style: .continuous).strokeBorder(LP.Colors.ink, lineWidth: 1))
            .lpShadow(LP.Shadow.sm)
        }
        .accessibilityLabel(Text("语言"))
    }
}

#Preview {
    RootView()
        .environment(HealthDataService(metrics: []))
        .environment(PetStateStore())
        .preferredColorScheme(.light)
}

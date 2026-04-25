import SwiftUI

@main
struct LifePulse_Watch_AppApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)   // LP palette is light-only paper
        }
    }
}

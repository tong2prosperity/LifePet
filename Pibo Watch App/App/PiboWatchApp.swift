import SwiftUI

@main
struct PiboWatchApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)   // LP palette is light-only paper
        }
    }
}

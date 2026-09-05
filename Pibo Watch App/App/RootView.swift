import SwiftUI

struct RootView: View {
    var body: some View {
        PiboWatchHomeView()
    }
}

#Preview("Pibo Companion") {
    RootView()
        .preferredColorScheme(.dark)
}

import SwiftUI

struct RootView: View {
    @State private var isRecording = false

    var body: some View {
        if isRecording {
            RecordingView(onStop: { isRecording = false })
        } else {
            StartView(onStart: { isRecording = true })
        }
    }
}

#Preview("Idle") {
    RootView()
        .preferredColorScheme(.light)
}

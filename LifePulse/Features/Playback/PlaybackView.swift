import SwiftUI

struct PlaybackView: View {
    @State private var viewModel = PlaybackViewModel()

    var body: some View {
        VStack {
            VisualizerView()
                .frame(maxWidth: .infinity, minHeight: 200)
            Button(viewModel.isPlaying ? "Pause" : "Play") {
                viewModel.isPlaying.toggle()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

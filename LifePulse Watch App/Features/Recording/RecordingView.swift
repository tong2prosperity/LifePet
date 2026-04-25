import SwiftUI

struct RecordingView: View {
    var onStop: () -> Void = {}
    @State private var viewModel = RecordingViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Text("HR: \(formatted(viewModel.latestHeartRate, suffix: "bpm"))")
            Text("SpO₂: \(formatted(viewModel.latestSpO2, suffix: "%"))")
            Text("HRV: \(formatted(viewModel.latestHRV, suffix: "ms"))")
            Spacer(minLength: 4)
            Button("Stop") {
                Task {
                    await viewModel.stop()
                    onStop()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .task {
            await viewModel.start()
        }
    }

    private func formatted(_ v: Double?, suffix: String) -> String {
        guard let v else { return "--" }
        return "\(Int(v)) \(suffix)"
    }
}

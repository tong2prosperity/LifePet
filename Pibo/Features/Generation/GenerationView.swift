import SwiftUI

struct GenerationView: View {
    @State private var viewModel = GenerationViewModel()

    var body: some View {
        VStack {
            Text("Generation")
                .font(.headline)
            Text(String(describing: viewModel.phase))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

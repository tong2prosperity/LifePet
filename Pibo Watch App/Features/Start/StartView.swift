import SwiftUI

struct StartView: View {
    var onStart: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            Text("Pibo")
                .font(.headline)
            Button("Start", action: onStart)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

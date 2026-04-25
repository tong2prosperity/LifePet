import SwiftUI

struct StartView: View {
    var onStart: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            Text("LifePulse")
                .font(.headline)
            Button("Start", action: onStart)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

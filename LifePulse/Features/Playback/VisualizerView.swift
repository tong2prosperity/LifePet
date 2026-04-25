import SwiftUI

struct VisualizerView: View {
    var renderer: VisualizationRenderer = VisualizationRenderer()

    var body: some View {
        Canvas { context, size in
            // TODO: draw renderer.frame.bins as bars, pulse radius modulated by heartRate.
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(.black.opacity(0.05)))
        }
    }
}

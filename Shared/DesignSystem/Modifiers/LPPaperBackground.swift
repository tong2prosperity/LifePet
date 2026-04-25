import SwiftUI

extension LP {
    /// Which of the five paper tones to put behind content.
    enum PaperSurface {
        case app         // #faf7ef — root background
        case stage       // #fafaf5 — pet stage / content region
        case card        // #fffef9 — card / clickable container
        case warm        // #f4f0e4 — quote block, inline code
        case kraft       // #e7e3d9 — secondary / section background

        var color: Color {
            switch self {
            case .app:   return LP.Colors.paper
            case .stage: return LP.Colors.paperCool
            case .card:  return LP.Colors.paperCard
            case .warm:  return LP.Colors.paperWarm
            case .kraft: return LP.Colors.kraft
            }
        }
    }
}

extension View {
    /// Paint an LP paper tone behind the view.
    ///
    /// By default the background bleeds into every safe-area edge (good for
    /// root containers). Pass `edges: []` to keep it bounded — e.g. when
    /// painting a nested `.stage` or `.card` surface inside a scroll view.
    func lpPaper(_ surface: LP.PaperSurface = .app, edges: Edge.Set = .all) -> some View {
        background(surface.color.ignoresSafeArea(edges: edges))
    }
}

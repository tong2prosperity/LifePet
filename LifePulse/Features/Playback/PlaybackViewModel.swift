import Foundation
import Observation

@Observable
final class PlaybackViewModel {
    var track: GeneratedTrack?
    var isPlaying: Bool = false

    init() {}

    // TODO: own AudioPlayer + FFTTap + VisualizationRenderer; forward bins to renderer.
}

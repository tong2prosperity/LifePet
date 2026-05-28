import Foundation
import Observation

@Observable
final class GenerationViewModel {
    enum Phase: Sendable, Equatable {
        case idle
        case liveCoding
        case requesting
        case ready(GeneratedTrack)
        case failed(String)
    }

    var phase: Phase = .idle

    init() {}

    // TODO: orchestrate LiveCodingEngine -> MusicGenerationClient -> hand finished track to PlaybackViewModel.
}

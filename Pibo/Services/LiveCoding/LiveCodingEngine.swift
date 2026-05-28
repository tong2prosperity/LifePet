import Foundation
import AVFAudio

@MainActor
final class LiveCodingEngine {
    private let engine = AVAudioEngine()
    private(set) var isRunning = false

    func start() throws {
        guard !isRunning else { return }
        // TODO: build node graph — oscillators, filters, reverb — parameters driven by VitalsToMusicMapping.
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        isRunning = false
    }

    func apply(_ snapshot: VitalSnapshot) {
        // TODO: map snapshot -> node parameters via VitalsToMusicMapping.
    }
}

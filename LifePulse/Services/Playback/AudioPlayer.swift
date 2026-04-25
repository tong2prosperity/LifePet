import Foundation
import AVFAudio

@MainActor
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private(set) var currentTrack: GeneratedTrack?

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
    }

    func load(_ track: GeneratedTrack) throws {
        // TODO: schedule track file, attach FFTTap.
        currentTrack = track
    }

    func play() throws {
        if !engine.isRunning { try engine.start() }
        player.play()
    }

    func stop() {
        player.stop()
        engine.stop()
    }
}

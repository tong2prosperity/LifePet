import Foundation
import AVFAudio

/// Plays a randomly-picked memorial meme track on loop, faded in/out.
///
/// One instance per 上香 overlay presentation: started on appear, stopped on
/// dismiss. Uses `AVAudioPlayer` (file-backed, single decoder thread) instead
/// of `AVAudioEngine` — the overlay only ever plays one looping track, so the
/// engine's graph and FFT machinery would be wasted overhead.
@MainActor
final class MemorialAudioPlayer {
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    /// Bundled mp3 names (without extension). Source files live in
    /// `Pibo/Resources/`; the synchronized group bundles them.
    private static let trackNames: [String] = [
        "memorial_meme_anime_game_farewell",
        "memorial_meme_kawaii_pet_heaven",
        "memorial_meme_mascot_ascend_ultra",
        "memorial_meme_pixel_pet_ascend",
        "memorial_meme_shoujo_melancholy",
        "memorial_meme_vaporwave_memorial",
    ]

    /// Pick a random track and start an infinite loop with a soft fade-in.
    /// Safe to call repeatedly — replaces any in-flight track.
    func startRandom() {
        stop(fadeDuration: 0)

        guard let name = Self.trackNames.randomElement(),
              let url = Bundle.main.url(forResource: name, withExtension: "mp3")
        else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])

            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0
            p.prepareToPlay()
            p.play()
            p.setVolume(0.85, fadeDuration: 0.6)
            player = p
        } catch {
            // Audio is ambient — silent failure is fine for a hackathon demo.
        }
    }

    /// Fade out and stop. The session is left active for the fade-out window
    /// then deactivated when the player is fully released.
    func stop(fadeDuration: TimeInterval = 0.4) {
        stopTask?.cancel()
        guard let p = player else { return }
        player = nil

        if fadeDuration > 0 {
            p.setVolume(0, fadeDuration: fadeDuration)
            stopTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(fadeDuration))
                p.stop()
                try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            }
        } else {
            p.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    deinit {
        // Capture the player into a local before nilling so we don't touch
        // self after the actor hop returns.
        let p = player
        let task = stopTask
        Task { @MainActor in
            task?.cancel()
            p?.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }
}

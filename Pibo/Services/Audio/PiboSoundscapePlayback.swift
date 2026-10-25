import AVFAudio
import Foundation
import os

nonisolated protocol PiboSoundscapePlaying: AnyObject {
    var isPlaying: Bool { get }
    var duration: TimeInterval { get }
    func play() -> Bool
    func setVolume(_ volume: Float, duration: TimeInterval)
    func stop()
}

/// Runs on the same queue as cues and the session. No player is created until
/// activation succeeds; stop/restart cannot reorder a delayed deactivation.
nonisolated final class PiboSoundscapePlayback: @unchecked Sendable {
    private let runtime: PiboAudioRuntime
    private let bundle: Bundle
    private let owner = UUID()
    private let makePlayer: @Sendable (URL, Bool) throws -> any PiboSoundscapePlaying
    private var queue: DispatchQueue { runtime.queue }
    private var players: [SoundscapeAsset: any PiboSoundscapePlaying] = [:]
    private var stops: [SoundscapeAsset: DispatchWorkItem] = [:]
    private var missingAssets: Set<SoundscapeAsset> = []
    private var generation = 0
    private var thunder: (any PiboSoundscapePlaying)?
    private var thunderEnabled = false
    private var thunderEpoch = 0
    private var thunderScheduled = false
    private var thunderMultiplier: Float = 0
    private var thunderGain: Float = 0
    private var previousThunder: SoundscapeAsset?

    init(runtime: PiboAudioRuntime = .shared, bundle: Bundle = .main,
         makePlayer: @escaping @Sendable (URL, Bool) throws -> any PiboSoundscapePlaying = {
             try PiboSoundscapePlayer(url: $0, looping: $1)
         }) {
        self.runtime = runtime
        self.bundle = bundle
        self.makePlayer = makePlayer
    }

    func apply(profile: SoundscapeProfile?, multiplier: Float, playing: Bool) {
        queue.async { [self] in
            generation += 1
            guard playing, let profile else {
                fadeOut()
                return
            }
            reconcile(profile: profile, multiplier: multiplier, attempt: 0)
        }
    }

    private enum PlaybackFailure: Error { case playerRefused }

    private func reconcile(profile: SoundscapeProfile, multiplier: Float, attempt: Int) {
        do {
            try runtime.beginPlayback(owner: owner)
            var accepted = true
            for asset in SoundscapeAsset.loopAssets {
                if !setLoop((profile.loopVolumes[asset] ?? 0) * multiplier, asset: asset) { accepted = false }
            }
            guard accepted else { throw PlaybackFailure.playerRefused }
            thunderMultiplier = multiplier
            thunder?.setVolume(thunderGain * multiplier, duration: 0.25)
            if !profile.thunderEnabled { stopThunder() }
            else {
                thunderEnabled = true
                scheduleThunder(after: Double.random(in: 3...8))
            }
        } catch {
            LPLog.audio.error("soundscape start failed: \(error.localizedDescription, privacy: .public)")
            // A cold launch or debugger resume can temporarily deny activation.
            // Retry only the latest desired mix; never revive audio after stopping.
            let delays: [Double] = [0.25, 0.75, 1.5]
            guard attempt < delays.count else { return }
            let expected = generation
            queue.asyncAfter(deadline: .now() + delays[attempt]) { [self] in
                guard generation == expected else { return }
                reconcile(profile: profile, multiplier: multiplier, attempt: attempt + 1)
            }
        }
    }

    func stop(invalidateSession: Bool = false) {
        queue.async { [self] in
            generation += 1
            stopThunder()
            for task in stops.values { task.cancel() }
            stops.removeAll()
            for player in players.values { player.stop() }
            players.removeAll()
            if invalidateSession { runtime.invalidate() }
            runtime.endPlayback(owner: owner)
        }
    }

    @discardableResult
    private func setLoop(_ target: Float, asset: SoundscapeAsset) -> Bool {
        stops.removeValue(forKey: asset)?.cancel()
        if target > 0.001 {
            do {
                let player: any PiboSoundscapePlaying
                if let cached = players[asset] { player = cached }
                else {
                    guard let url = url(for: asset) else { return true }
                    player = try makePlayer(url, true)
                    players[asset] = player
                }
                if !player.isPlaying {
                    guard player.play() else {
                        players.removeValue(forKey: asset)
                        runtime.invalidate()
                        LPLog.audio.error("soundscape player refused asset=\(asset.rawValue, privacy: .public)")
                        return false
                    }
                    LPLog.audio.info("soundscape playing asset=\(asset.rawValue, privacy: .public)")
                }
                player.setVolume(target, duration: 1.8)
            } catch {
                LPLog.audio.error("soundscape load failed asset=\(asset.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return false
            }
        } else if let player = players[asset], player.isPlaying {
            player.setVolume(0, duration: 0.35)
            let task = DispatchWorkItem { player.stop() }
            stops[asset] = task
            queue.asyncAfter(deadline: .now() + 0.35, execute: task)
        }
        return true
    }

    private func fadeOut() {
        for asset in SoundscapeAsset.loopAssets { setLoop(0, asset: asset) }
        stopThunder()
        let expected = generation
        queue.asyncAfter(deadline: .now() + 0.4) { [self] in
            guard generation == expected else { return }
            runtime.endPlayback(owner: owner)
        }
    }

    private func scheduleThunder(after delay: TimeInterval) {
        guard thunderEnabled, !thunderScheduled else { return }
        thunderScheduled = true
        let expected = thunderEpoch
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            guard expected == thunderEpoch, thunderEnabled else { return }
            thunderScheduled = false
            let duration = playThunder()
            scheduleThunder(after: duration + Double.random(in: 12...30))
        }
    }

    private func playThunder() -> TimeInterval {
        let candidates = SoundscapeAsset.thunderAssets.filter { $0 != previousThunder }
        guard let asset = candidates.randomElement(), let url = url(for: asset) else { return 0 }
        do {
            try runtime.beginPlayback(owner: owner)
            let player = try makePlayer(url, false)
            thunderGain = Float.random(in: 0.55...0.80)
            player.setVolume(thunderGain * thunderMultiplier, duration: 0)
            guard player.play() else { runtime.invalidate(); return 0 }
            thunder = player
            previousThunder = asset
            return player.duration
        } catch {
            LPLog.audio.error("thunder playback failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    private func stopThunder() {
        thunderEpoch += 1
        thunderScheduled = false
        thunderEnabled = false
        thunder?.stop()
        thunder = nil
    }

    private func url(for asset: SoundscapeAsset) -> URL? {
        let url = bundle.url(forResource: asset.rawValue, withExtension: "m4a", subdirectory: "Audio/Ambience")
            ?? bundle.url(forResource: asset.rawValue, withExtension: "m4a")
        if url == nil, missingAssets.insert(asset).inserted {
            LPLog.audio.error("soundscape asset missing: \(asset.rawValue, privacy: .public).m4a")
        }
        return url
    }
}

nonisolated private final class PiboSoundscapePlayer: PiboSoundscapePlaying {
    private let player: AVAudioPlayer
    var isPlaying: Bool { player.isPlaying }
    var duration: TimeInterval { player.duration }

    init(url: URL, looping: Bool) throws {
        player = try AVAudioPlayer(contentsOf: url)
        player.numberOfLoops = looping ? -1 : 0
        player.volume = 0
        player.prepareToPlay()
    }

    func play() -> Bool { player.play() }
    func setVolume(_ volume: Float, duration: TimeInterval) {
        player.setVolume(volume, fadeDuration: duration)
    }
    func stop() { player.stop(); player.currentTime = 0 }
}

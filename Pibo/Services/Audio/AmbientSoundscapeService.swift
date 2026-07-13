import AVFAudio
import Foundation
import os

@MainActor
final class AmbientSoundscapeService {
    private let bundle: Bundle
    private let session: AVAudioSession
    private var profile: SoundscapeProfile?
    private var presentation: SoundscapePresentation = .suspended
    private var enabled = true
    private var interrupted = false
    private var externalAudioSuppressed = false
    private var sessionActive = false

    private var loopPlayers: [SoundscapeAsset: AVAudioPlayer] = [:]
    private var desiredLoopVolumes: [SoundscapeAsset: Float] = [:]
    private var loopStopTasks: [SoundscapeAsset: Task<Void, Never>] = [:]
    private var sessionStopTask: Task<Void, Never>?
    private var thunderTask: Task<Void, Never>?
    private var thunderPlayer: AVAudioPlayer?
    private var thunderGain: Float = 0
    private var previousThunder: SoundscapeAsset?

    private var missingAssets: Set<SoundscapeAsset> = []
    private var didLogSessionFailure = false

    init(bundle: Bundle = .main, session: AVAudioSession = .sharedInstance()) {
        self.bundle = bundle
        self.session = session
    }

    func apply(environment: PiboStageEnvironment, date: Date, petID: UUID) {
        profile = SoundscapeResolver.resolve(
            environment: environment,
            date: date,
            petID: petID
        )
        updateMix()
    }

    func setPresentation(_ presentation: SoundscapePresentation) {
        guard self.presentation != presentation else { return }
        self.presentation = presentation
        updateMix()
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        updateMix()
    }

    func refreshExternalAudioSuppression() {
        let shouldSuppress = session.secondaryAudioShouldBeSilencedHint
        guard externalAudioSuppressed != shouldSuppress else { return }
        externalAudioSuppressed = shouldSuppress
        updateMix()
    }

    func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            interrupted = true
            updateMix()
        case .ended:
            interrupted = false
            updateMix()
        @unknown default:
            break
        }
    }

    func handleSecondaryAudioHint(_ notification: Notification) {
        if let rawType = notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
           let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: rawType) {
            externalAudioSuppressed = type == .begin
        } else {
            externalAudioSuppressed = session.secondaryAudioShouldBeSilencedHint
        }
        updateMix()
    }

    func stop() {
        sessionStopTask?.cancel()
        sessionStopTask = nil
        stopThunder()
        for task in loopStopTasks.values { task.cancel() }
        loopStopTasks.removeAll()
        for player in loopPlayers.values {
            player.stop()
            player.currentTime = 0
            player.volume = 0
        }
        desiredLoopVolumes.removeAll()
        deactivateSession()
    }

    private var shouldPlay: Bool {
        enabled
            && presentation != .suspended
            && !interrupted
            && !externalAudioSuppressed
            && profile != nil
    }

    private func updateMix() {
        guard shouldPlay, let profile else {
            fadeAllLoops(to: 0, duration: 0.35)
            stopThunder()
            scheduleSessionDeactivation(after: 0.4)
            return
        }

        sessionStopTask?.cancel()
        sessionStopTask = nil
        guard activateSession() else { return }

        let multiplier = presentation.volumeMultiplier
        for asset in SoundscapeAsset.loopAssets {
            let target = (profile.loopVolumes[asset] ?? 0) * multiplier
            setLoopVolume(target, for: asset, duration: 1.8)
        }
        thunderPlayer?.setVolume(thunderGain * multiplier, fadeDuration: 0.25)
        reconcileThunder(enabled: profile.thunderEnabled)
    }

    private func fadeAllLoops(to target: Float, duration: TimeInterval) {
        for asset in SoundscapeAsset.loopAssets {
            setLoopVolume(target, for: asset, duration: duration)
        }
    }

    private func setLoopVolume(
        _ target: Float,
        for asset: SoundscapeAsset,
        duration: TimeInterval
    ) {
        desiredLoopVolumes[asset] = target
        loopStopTasks[asset]?.cancel()
        loopStopTasks[asset] = nil

        if target > 0.001 {
            guard let player = loopPlayer(for: asset) else { return }
            if !player.isPlaying {
                player.currentTime = 0
                player.volume = 0
                player.play()
            }
            player.setVolume(target, fadeDuration: duration)
            return
        }

        guard let player = loopPlayers[asset], player.isPlaying else { return }
        player.setVolume(0, fadeDuration: duration)
        loopStopTasks[asset] = Task { @MainActor [weak self, weak player] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled,
                  let self,
                  (self.desiredLoopVolumes[asset] ?? 0) <= 0.001 else { return }
            player?.stop()
            player?.currentTime = 0
        }
    }

    private func loopPlayer(for asset: SoundscapeAsset) -> AVAudioPlayer? {
        if let player = loopPlayers[asset] { return player }
        guard let url = resourceURL(for: asset) else {
            logMissingAssetOnce(asset)
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            loopPlayers[asset] = player
            return player
        } catch {
            LPLog.audio.error("soundscape load failed asset=\(asset.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func reconcileThunder(enabled: Bool) {
        guard enabled, shouldPlay else {
            stopThunder()
            return
        }
        guard thunderTask == nil else { return }
        thunderTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Double.random(in: 3...8)))
            while !Task.isCancelled {
                guard let self, self.shouldPlay, self.profile?.thunderEnabled == true else { return }
                let duration = self.playThunder()
                try? await Task.sleep(for: .seconds(duration + Double.random(in: 12...30)))
            }
        }
    }

    @discardableResult
    private func playThunder() -> TimeInterval {
        let candidates = SoundscapeAsset.thunderAssets.filter { $0 != previousThunder }
        guard let asset = candidates.randomElement(),
              let url = resourceURL(for: asset) else {
            if let missing = candidates.first { logMissingAssetOnce(missing) }
            return 0
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            thunderGain = Float.random(in: 0.55...0.80)
            player.volume = thunderGain * presentation.volumeMultiplier
            player.prepareToPlay()
            player.play()
            thunderPlayer = player
            previousThunder = asset
            return player.duration
        } catch {
            LPLog.audio.error("thunder load failed asset=\(asset.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    private func stopThunder() {
        thunderTask?.cancel()
        thunderTask = nil
        thunderPlayer?.stop()
        thunderPlayer = nil
        thunderGain = 0
    }

    private func resourceURL(for asset: SoundscapeAsset) -> URL? {
        bundle.url(forResource: asset.rawValue, withExtension: "m4a", subdirectory: "Audio/Ambience")
            ?? bundle.url(forResource: asset.rawValue, withExtension: "m4a")
    }

    private func logMissingAssetOnce(_ asset: SoundscapeAsset) {
        guard missingAssets.insert(asset).inserted else { return }
        LPLog.audio.error("soundscape asset missing: \(asset.rawValue, privacy: .public).m4a")
    }

    private func activateSession() -> Bool {
        guard !sessionActive else { return true }
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            sessionActive = true
            didLogSessionFailure = false
            return true
        } catch {
            if !didLogSessionFailure {
                didLogSessionFailure = true
                LPLog.audio.error("soundscape session activation failed: \(error.localizedDescription, privacy: .public)")
            }
            return false
        }
    }

    private func scheduleSessionDeactivation(after duration: TimeInterval) {
        sessionStopTask?.cancel()
        guard sessionActive else { return }
        sessionStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, !self.shouldPlay else { return }
            self.deactivateSession()
        }
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        sessionActive = false
    }
}

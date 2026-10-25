import AVFAudio
import Foundation
import os
import PiboCore

@MainActor
final class AmbientSoundscapeService {
    private let session: AVAudioSession
    private let playback: PiboSoundscapePlayback
    private var profile: SoundscapeProfile?
    private var presentation: SoundscapePresentation = .suspended
    private var enabled = true
    private var interrupted = false
    private var externalAudioSuppressed = false
    private var coLightGain: Float = 1

    init(bundle: Bundle = .main, session: AVAudioSession = .sharedInstance(),
         runtime: PiboAudioRuntime = .shared) {
        self.session = session
        self.playback = PiboSoundscapePlayback(runtime: runtime, bundle: bundle)
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

    func setCoLightCount(_ count: Int) {
        let value = Float(PiboCoreSoundscape.coLightGain(litLanternCount: count))
        guard value != coLightGain else { return }
        coLightGain = value
        updateMix()
    }

    func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            interrupted = true
            playback.stop(invalidateSession: true)
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

    func stop() { playback.stop() }

    /// Foregrounding can follow a cold launch, an interruption, or a debugger pause.
    /// Re-read the hint even when its value did not change and reconcile playback.
    func resume() {
        interrupted = false
        externalAudioSuppressed = session.secondaryAudioShouldBeSilencedHint
        playback.stop(invalidateSession: true)
        updateMix()
    }

    func handleMediaServicesReset() {
        playback.stop(invalidateSession: true)
        updateMix()
    }

    private var shouldPlay: Bool {
        enabled
            && presentation != .suspended
            && !interrupted
            && !externalAudioSuppressed
            && profile != nil
    }

    private func updateMix() {
        playback.apply(profile: profile,
                       multiplier: presentation.volumeMultiplier * coLightGain,
                       playing: shouldPlay)
    }
}

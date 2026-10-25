import AVFAudio
import Foundation
import os
import UIKit

/// Short Home cues from `pibo-media` `audio.home-sfx`. Raw values are the
/// runtime file stems (`sfx_<raw>.m4a`) and are shared with HarmonyOS.
enum PiboSoundEffect: String, CaseIterable {
    case patStable = "pat_stable"
    case patEnergetic = "pat_energetic"
    case patTired = "pat_tired"
    case patSleepy = "pat_sleepy"
    case stateTransition = "state_transition"
    case boSproutTouch = "bo_sprout_touch"
    case boGrowthSparkle = "bo_growth_sparkle"
    case mealStickerPop = "meal_sticker_pop"
    case onboardingComplete = "onboarding_complete"
    case hammockCreak = "hammock_creak"
    case observerOpen = "observer_open"
    case footprintsOpen = "footprints_open"

    var assetName: String { "sfx_\(rawValue)" }

    /// Files are normalized to one loudness reference; the mix lives here so a
    /// level change never needs a media re-render. Sleep-side cues stay quiet
    /// so a pat never reads as waking Pibo up. Same table as HarmonyOS.
    var volume: Float {
        switch self {
        case .patSleepy: 0.14
        case .stateTransition: 0.18
        case .boGrowthSparkle: 0.2
        case .hammockCreak, .footprintsOpen: 0.22
        case .patTired, .observerOpen: 0.26
        case .boSproutTouch: 0.28
        case .patStable, .patEnergetic, .mealStickerPop, .onboardingComplete: 0.3
        }
    }

    /// The pat cue follows the state Pibo is visibly reacting in, like the haptic.
    static func pat(for state: PiboActivityState) -> PiboSoundEffect {
        switch state {
        case .energetic: .patEnergetic
        case .tired: .patTired
        case .sleeping, .waking: .patSleepy
        case .stable, .dataUnknown: .patStable
        }
    }
}

/// App-wide one-shot cue player. Visuals and haptics always carry the same
/// information, so a cue is skipped — never queued — when effects are off, the
/// app is not active, or Reduce Motion is on.
///
/// The shared audio runtime uses `.ambient` for standalone cues and preserves
/// `.playback` while environmental loops own it. Category selection happens on
/// the audio queue after activation, never from a speculative MainActor flag.
@MainActor
final class PiboSoundEffectService {
    static let shared = PiboSoundEffectService()

    /// A second trigger of the same cue inside this window is dropped; faster
    /// repeats restart the cue from the top.
    static let minRepeatInterval: TimeInterval = 0.08

    private let bundle: Bundle
    private let playback: PiboCuePlayback
    private let runtime: PiboAudioRuntime
    private let defaults: UserDefaults
    private var appActive: Bool
    private var lastPlayedAt: [PiboSoundEffect: Date] = [:]
    private var missingAssets: Set<PiboSoundEffect> = []
    // Decision 063: the pixel stage's own cues live in their own folder and have their own
    // volume table; they are short enough to keep their players alongside the Home cues.
    private var lastPixelPlayedAt: [PiboPixelSound: Date] = [:]
    private var missingPixelAssets: Set<PiboPixelSound> = []

    init(
        bundle: Bundle = .main,
        runtime: PiboAudioRuntime = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.bundle = bundle
        self.playback = PiboCuePlayback(runtime: runtime)
        self.runtime = runtime
        self.defaults = defaults
        self.appActive = UIApplication.shared.applicationState == .active
        playback.setEnabled(isEnabled && appActive)
    }

    var isEnabled: Bool {
        defaults.object(forKey: PiboPersistenceKeys.Defaults.soundEffectsEnabled) as? Bool ?? true
    }

    static func resourceURL(for effect: PiboSoundEffect, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: effect.assetName, withExtension: "m4a", subdirectory: "Audio/HomeSFX")
            ?? bundle.url(forResource: effect.assetName, withExtension: "m4a")
    }

    /// The pixel stage's own cues, rendered by `tools/render_pixel_sfx.mjs` on the HarmonyOS
    /// side and copied here unchanged (`px_<rawValue>.m4a`).
    static func resourceURL(for sound: PiboPixelSound, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: sound.assetName, withExtension: "m4a", subdirectory: "Audio/PixelSFX")
            ?? bundle.url(forResource: sound.assetName, withExtension: "m4a")
    }

    /// Decodes every cue up front so the first pat is not late.
    func preload() {
        guard isEnabled, appActive else { return }
        let urls = PiboSoundEffect.allCases.compactMap { resourceURL(for: $0) }
            + PiboPixelSound.allCases.compactMap { resourceURL(for: $0) }
        playback.preload(urls)
    }

    /// Settings toggle: drop decoded buffers when off, warm them when back on.
    func setEnabled(_ enabled: Bool) {
        playback.setEnabled(enabled && appActive)
        if enabled { preload() }
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        if active { runtime.invalidateAsync() }
        playback.setEnabled(active && isEnabled)
        if active { preload() }
    }

    func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        runtime.invalidateAsync()
        if type == .began { playback.setEnabled(false) }
        else {
            playback.setEnabled(appActive && isEnabled)
            preload()
        }
    }

    func handleMediaServicesReset() {
        runtime.invalidateAsync()
        playback.stop()
        preload()
    }

    func play(_ effect: PiboSoundEffect) {
        guard isEnabled,
              UIApplication.shared.applicationState == .active,
              !UIAccessibility.isReduceMotionEnabled
        else { return }
        let now = Date()
        if let last = lastPlayedAt[effect], now.timeIntervalSince(last) < Self.minRepeatInterval { return }
        guard let url = resourceURL(for: effect) else { return }
        lastPlayedAt[effect] = now
        let volume = effect.volume
        playback.play(url, volume: volume)
        // One line per discrete interaction — it is what makes the cue audible
        // in a log when the device audit cannot be done by ear.
        LPLog.audio.debug("cue \(effect.rawValue, privacy: .public) at \(effect.volume, privacy: .public)")
    }

    /// A pixel stage cue. `hushed` drops it to `PIBO_PIXEL_SOUND_HUSH` — at night or while
    /// Pibo sleeps, where a shape change should not sound like an alarm.
    func play(_ sound: PiboPixelSound, hushed: Bool = false) {
        guard isEnabled,
              UIApplication.shared.applicationState == .active,
              !UIAccessibility.isReduceMotionEnabled
        else { return }
        let now = Date()
        if let last = lastPixelPlayedAt[sound], now.timeIntervalSince(last) < Self.minRepeatInterval { return }
        guard let url = resourceURL(for: sound) else { return }
        lastPixelPlayedAt[sound] = now
        let volume = piboPixelSoundVolume(sound) * (hushed ? PIBO_PIXEL_SOUND_HUSH : 1)
        playback.play(url, volume: volume)
        LPLog.audio.debug("pixel cue \(sound.rawValue, privacy: .public) at \(volume, privacy: .public)")
    }

    private func resourceURL(for effect: PiboSoundEffect) -> URL? {
        let url = Self.resourceURL(for: effect, in: bundle)
        if url == nil, missingAssets.insert(effect).inserted {
            LPLog.audio.error("sound effect missing: \(effect.assetName, privacy: .public).m4a")
        }
        return url
    }

    private func resourceURL(for sound: PiboPixelSound) -> URL? {
        let url = Self.resourceURL(for: sound, in: bundle)
        if url == nil, missingPixelAssets.insert(sound).inserted {
            LPLog.audio.error("pixel cue missing: \(sound.assetName, privacy: .public).m4a")
        }
        return url
    }
}

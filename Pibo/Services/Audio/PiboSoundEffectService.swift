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
/// The session is `.ambient` so the ring/silent switch silences cues and other
/// apps' music keeps playing (HarmonyOS reads the ringer mode instead). While
/// the ambient soundscape holds its `.playback` session the category is left
/// alone — switching it underneath the loops would mute them in silent mode.
@MainActor
final class PiboSoundEffectService {
    static let shared = PiboSoundEffectService()

    /// A second trigger of the same cue inside this window is dropped; faster
    /// repeats restart the cue from the top.
    static let minRepeatInterval: TimeInterval = 0.08

    private let bundle: Bundle
    private let session: AVAudioSession
    private let defaults: UserDefaults
    private var players: [PiboSoundEffect: AVAudioPlayer] = [:]
    private var lastPlayedAt: [PiboSoundEffect: Date] = [:]
    private var missingAssets: Set<PiboSoundEffect> = []
    // Decision 063: the pixel stage's own cues live in their own folder and have their own
    // volume table; they are short enough to keep their players alongside the Home cues.
    private var pixelPlayers: [PiboPixelSound: AVAudioPlayer] = [:]
    private var lastPixelPlayedAt: [PiboPixelSound: Date] = [:]
    private var missingPixelAssets: Set<PiboPixelSound> = []

    init(
        bundle: Bundle = .main,
        session: AVAudioSession = .sharedInstance(),
        defaults: UserDefaults = .standard
    ) {
        self.bundle = bundle
        self.session = session
        self.defaults = defaults
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
        guard isEnabled else { return }
        for effect in PiboSoundEffect.allCases { _ = player(for: effect) }
        for sound in PiboPixelSound.allCases { _ = pixelPlayer(for: sound) }
    }

    /// Settings toggle: drop decoded buffers when off, warm them when back on.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            preload()
        } else {
            for player in players.values { player.stop() }
            players.removeAll()
            for player in pixelPlayers.values { player.stop() }
            pixelPlayers.removeAll()
        }
    }

    func play(_ effect: PiboSoundEffect) {
        guard isEnabled,
              UIApplication.shared.applicationState == .active,
              !UIAccessibility.isReduceMotionEnabled
        else { return }
        let now = Date()
        if let last = lastPlayedAt[effect], now.timeIntervalSince(last) < Self.minRepeatInterval { return }
        guard prepareSession(), let player = player(for: effect) else { return }
        lastPlayedAt[effect] = now
        player.currentTime = 0
        player.volume = effect.volume
        player.play()
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
        guard prepareSession(), let player = pixelPlayer(for: sound) else { return }
        lastPixelPlayedAt[sound] = now
        player.currentTime = 0
        player.volume = piboPixelSoundVolume(sound) * (hushed ? PIBO_PIXEL_SOUND_HUSH : 1)
        player.play()
        LPLog.audio.debug("pixel cue \(sound.rawValue, privacy: .public) at \(player.volume, privacy: .public)")
    }

    private func player(for effect: PiboSoundEffect) -> AVAudioPlayer? {
        if let player = players[effect] { return player }
        guard let url = Self.resourceURL(for: effect, in: bundle) else {
            if missingAssets.insert(effect).inserted {
                LPLog.audio.error("sound effect missing: \(effect.assetName, privacy: .public).m4a")
            }
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.prepareToPlay()
            players[effect] = player
            return player
        } catch {
            LPLog.audio.error("sound effect \(effect.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func pixelPlayer(for sound: PiboPixelSound) -> AVAudioPlayer? {
        if let player = pixelPlayers[sound] { return player }
        guard let url = Self.resourceURL(for: sound, in: bundle) else {
            if missingPixelAssets.insert(sound).inserted {
                LPLog.audio.error("pixel cue missing: \(sound.assetName, privacy: .public).m4a")
            }
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.prepareToPlay()
            pixelPlayers[sound] = player
            return player
        } catch {
            LPLog.audio.error("pixel cue \(sound.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func prepareSession() -> Bool {
        if AmbientSoundscapeService.holdsPlaybackSession { return true }
        do {
            if session.category != .ambient {
                try session.setCategory(.ambient, mode: .default)
            }
            try session.setActive(true)
            return true
        } catch {
            LPLog.audio.error("sound effect session failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

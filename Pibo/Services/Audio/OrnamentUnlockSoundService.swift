import AVFAudio
import Foundation
import os

@MainActor
final class OrnamentUnlockSoundService {
    static let investmentAssetName = "ornament_bo_invest"

    static var allAssetNames: [String] {
        [investmentAssetName] + PiboOrnament.ID.allCases.map(completionAssetName(for:))
    }

    static func completionAssetName(for id: PiboOrnament.ID) -> String {
        "ornament_\(id.rawValue.snakeCased)_complete"
    }

    private let bundle: Bundle
    private let session: AVAudioSession
    private var player: AVAudioPlayer?
    private var enabled = true
    private var interrupted = false
    private var externalAudioSuppressed = false
    private var missingAssets: Set<String> = []

    init(bundle: Bundle = .main, session: AVAudioSession = .sharedInstance()) {
        self.bundle = bundle
        self.session = session
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if !enabled { stop() }
    }

    func refreshExternalAudioSuppression() {
        externalAudioSuppressed = session.secondaryAudioShouldBeSilencedHint
        if externalAudioSuppressed { stop() }
    }

    func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        interrupted = type == .began
        if interrupted { stop() }
    }

    func handleSecondaryAudioHint(_ notification: Notification) {
        if let rawType = notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
           let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: rawType) {
            externalAudioSuppressed = type == .begin
        } else {
            externalAudioSuppressed = session.secondaryAudioShouldBeSilencedHint
        }
        if externalAudioSuppressed { stop() }
    }

    func playInvestment() {
        play(Self.investmentAssetName)
    }

    func playCompletion(for id: PiboOrnament.ID) {
        play(Self.completionAssetName(for: id))
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private var canPlay: Bool {
        enabled && !interrupted && !externalAudioSuppressed
    }

    private func play(_ name: String) {
        guard canPlay else { return }
        player?.stop()
        player = nil
        guard let url = bundle.url(
            forResource: name,
            withExtension: "m4a",
            subdirectory: "Audio/OrnamentUnlock"
        ) ?? bundle.url(forResource: name, withExtension: "m4a") else {
            if missingAssets.insert(name).inserted {
                LPLog.audio.error("ornament sound missing: \(name, privacy: .public).m4a")
            }
            return
        }
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let next = try AVAudioPlayer(contentsOf: url)
            next.numberOfLoops = 0
            next.volume = 0.72
            next.prepareToPlay()
            next.play()
            player = next
        } catch {
            LPLog.audio.error("ornament sound failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension String {
    var snakeCased: String {
        unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar), !result.isEmpty {
                result.append("_")
            }
            result.append(String(scalar).lowercased())
        }
    }
}

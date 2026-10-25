import AVFAudio
import Foundation
import os

nonisolated protocol PiboCuePlaying: AnyObject {
    func play(volume: Float) -> Bool
    func stop()
}

/// Decoding and prepareToPlay can also activate the audio session implicitly.
/// Keep the entire player lifecycle off MainActor, in order with session activation.
/// Queue confinement protects the players and prevents a delayed play after disabling.
nonisolated final class PiboCuePlayback: @unchecked Sendable {
    private let runtime: PiboAudioRuntime
    private var queue: DispatchQueue { runtime.queue }
    private let category: AVAudioSession.Category
    private let allowsOverlap: Bool
    private let sessionPreparation: (@Sendable () throws -> Void)?
    private let makePlayer: @Sendable (URL) throws -> any PiboCuePlaying
    private var enabled = true
    private var players: [URL: any PiboCuePlaying] = [:]

    init(
        runtime: PiboAudioRuntime = .shared,
        category: AVAudioSession.Category = .ambient,
        allowsOverlap: Bool = true,
        sessionPreparation: (@Sendable () throws -> Void)? = nil,
        makePlayer: @escaping @Sendable (URL) throws -> any PiboCuePlaying = { try PiboCueAudioPlayer(url: $0) }
    ) {
        self.runtime = runtime
        self.category = category
        self.allowsOverlap = allowsOverlap
        self.sessionPreparation = sessionPreparation
        self.makePlayer = makePlayer
    }

    func setEnabled(_ enabled: Bool) {
        queue.async { [self] in
            self.enabled = enabled
            if !enabled {
                for player in players.values { player.stop() }
                players.removeAll()
            }
        }
    }

    func preload(_ urls: [URL]) {
        queue.async { [self] in
            guard enabled else { return }
            perform {
                try prepareSession()
                for url in urls { _ = try player(for: url) }
            }
        }
    }

    func play(_ url: URL, volume: Float) {
        queue.async { [self] in
            guard enabled else { return }
            perform {
                if !allowsOverlap { stopPlayers() }
                try prepareSession()
                if try !player(for: url).play(volume: volume) {
                    runtime.invalidate()
                    players.removeValue(forKey: url)
                    LPLog.audio.error("audio player refused cue: \(url.lastPathComponent, privacy: .public)")
                } else {
                    LPLog.audio.info("cue started asset=\(url.lastPathComponent, privacy: .public)")
                }
            }
        }
    }

    /// Wait for operations already submitted, without blocking the caller's thread.
    func drain() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    func stop() { queue.async { self.stopPlayers() } }

    private func stopPlayers() {
        for player in players.values { player.stop() }
        players.removeAll()
    }

    private func prepareSession() throws {
        dispatchPrecondition(condition: .onQueue(queue))
        if let sessionPreparation {
            try sessionPreparation()
            return
        }
        try runtime.prepareCue(category: category)
    }

    private func player(for url: URL) throws -> any PiboCuePlaying {
        if let player = players[url] { return player }
        let player = try makePlayer(url)
        players[url] = player
        return player
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() }
        catch { LPLog.audio.error("cue playback failed: \(error.localizedDescription, privacy: .public)") }
    }
}

nonisolated private final class PiboCueAudioPlayer: PiboCuePlaying {
    private let player: AVAudioPlayer

    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        player.numberOfLoops = 0
        player.prepareToPlay()
    }

    func play(volume: Float) -> Bool {
        player.currentTime = 0
        player.volume = volume
        return player.play()
    }

    func stop() { player.stop() }
}

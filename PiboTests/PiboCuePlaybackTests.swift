import Foundation
import Testing
@testable import Pibo

struct PiboCuePlaybackTests {
    nonisolated private final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []
        func append(_ value: String) {
            #expect(!Thread.isMainThread, "session/player work must never run on the UI thread")
            lock.lock()
            values.append(value)
            lock.unlock()
        }
        func read() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    nonisolated private final class Player: PiboCuePlaying {
        let events: Events
        init(_ events: Events) { self.events = events; events.append("decode") }
        func play(volume: Float) -> Bool { events.append("play"); return true }
        func stop() { events.append("stop") }
    }

    @Test func activationDecodingPlaybackAndDisableStayInOrderOffMainThread() async {
        let events = Events()
        let playback = PiboCuePlayback(sessionPreparation: { events.append("activate") },
                                       makePlayer: { _ in Player(events) })
        let url = URL(fileURLWithPath: "/cue.m4a")
        playback.preload([url])
        playback.play(url, volume: 0.3)
        playback.setEnabled(false)
        playback.play(url, volume: 0.3)
        await playback.drain()
        #expect(events.read() == ["activate", "decode", "activate", "play", "stop"])
        playback.setEnabled(true)
        playback.play(url, volume: 0.3)
        await playback.drain()
        #expect(events.read().suffix(3) == ["activate", "decode", "play"])
    }

    @Test func failedActivationDoesNotDecodeOrPlay() async {
        enum Unavailable: Error { case session }
        let events = Events()
        let playback = PiboCuePlayback(sessionPreparation: { throw Unavailable.session },
                                       makePlayer: { _ in Player(events) })
        playback.play(URL(fileURLWithPath: "/cue.m4a"), volume: 0.3)
        await playback.drain()
        #expect(events.read().isEmpty)
    }
}

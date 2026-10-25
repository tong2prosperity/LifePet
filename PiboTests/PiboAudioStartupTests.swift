import AVFAudio
import Foundation
import Testing
@testable import Pibo

@MainActor
struct PiboAudioStartupTests {
    nonisolated private final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        func append(_ entry: String) {
            #expect(!Thread.isMainThread)
            lock.lock()
            entries.append(entry)
            lock.unlock()
        }
        func read() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return entries
        }
    }

    nonisolated private final class Loop: PiboSoundscapePlaying {
        let events: Events
        var isPlaying = false
        let duration: TimeInterval = 1
        init(_ events: Events) { self.events = events; events.append("loop.decode") }
        func play() -> Bool { events.append("loop.play"); isPlaying = true; return true }
        func setVolume(_ volume: Float, duration: TimeInterval) {}
        func stop() { events.append("loop.stop"); isPlaying = false }
    }

    nonisolated private final class Cue: PiboCuePlaying {
        let events: Events
        let succeeds: Bool
        init(_ events: Events, succeeds: Bool = true) {
            self.events = events
            self.succeeds = succeeds
            events.append("cue.decode")
        }
        func play(volume: Float) -> Bool { events.append("cue.play"); return succeeds }
        func stop() { events.append("cue.stop") }
    }

    private let profile = SoundscapeProfile(biome: .forest, loopVolumes: [.forestDay: 0.3], thunderEnabled: false)
    private let cueURL = URL(fileURLWithPath: "/cue.m4a")

    nonisolated private static func waitForSignal(_ semaphore: DispatchSemaphore) -> Bool {
        semaphore.wait(timeout: .now() + 5) == .success
    }

    @Test func coldLaunchWaitsForActivationAndCueCannotChangeTheLoopCategory() async {
        let events = Events()
        let began = DispatchSemaphore(value: 0)
        let finish = DispatchSemaphore(value: 0)
        let runtime = PiboAudioRuntime(activate: { category in
            events.append("activate.\(category.rawValue).begin")
            began.signal()
            #expect(finish.wait(timeout: .now() + 5) == .success)
            events.append("activate.end")
        }, deactivate: { events.append("deactivate") })
        let loops = PiboSoundscapePlayback(runtime: runtime, makePlayer: { _, _ in Loop(events) })
        let cues = PiboCuePlayback(runtime: runtime, makePlayer: { _ in Cue(events) })
        loops.apply(profile: profile, multiplier: 1, playing: true)
        cues.preload([cueURL])
        cues.play(cueURL, volume: 0.3)
        let started = await Task.detached { Self.waitForSignal(began) }.value
        #expect(started)
        #expect(events.read() == ["activate.AVAudioSessionCategoryPlayback.begin"],
                "nothing may decode/play or switch to ambient before activation finishes")
        finish.signal()
        await runtime.drain()
        #expect(events.read() == ["activate.AVAudioSessionCategoryPlayback.begin", "activate.end",
                                 "loop.decode", "loop.play", "cue.decode", "cue.play"])
        loops.stop()
        cues.stop()
        await runtime.drain()
    }

    @Test func failedColdActivationCanRecoverOnTheNextReconciliation() async {
        enum Failure: Error { case unavailable }
        let events = Events()
        let runtime = PiboAudioRuntime(activate: { _ in
            events.append("activate")
            if events.read().count == 1 { throw Failure.unavailable }
        }, deactivate: { events.append("deactivate") })
        let loops = PiboSoundscapePlayback(runtime: runtime, makePlayer: { _, _ in Loop(events) })
        loops.apply(profile: profile, multiplier: 1, playing: true)
        await runtime.drain()
        #expect(events.read() == ["activate"])
        loops.apply(profile: profile, multiplier: 1, playing: true)
        await runtime.drain()
        #expect(events.read() == ["activate", "activate", "loop.decode", "loop.play"])
        loops.stop()
        await runtime.drain()
    }

    @Test func delayedFadeOutCannotDeactivateAResumedForest() async throws {
        let events = Events()
        let runtime = PiboAudioRuntime(activate: { _ in events.append("activate") },
                                       deactivate: { events.append("deactivate") })
        let loops = PiboSoundscapePlayback(runtime: runtime, makePlayer: { _, _ in Loop(events) })
        loops.apply(profile: profile, multiplier: 1, playing: true)
        loops.apply(profile: profile, multiplier: 0, playing: false)
        loops.apply(profile: profile, multiplier: 1, playing: true)
        await runtime.drain()
        try await Task.sleep(for: .milliseconds(500))
        await runtime.drain()
        #expect(events.read() == ["activate", "loop.decode", "loop.play"])
        loops.stop()
        await runtime.drain()
    }

    @Test func temporaryColdFailureRetriesWithoutLeavingHome() async throws {
        enum Failure: Error { case unavailable }
        let events = Events()
        let runtime = PiboAudioRuntime(activate: { _ in
            events.append("activate")
            if events.read().count == 1 { throw Failure.unavailable }
        }, deactivate: { events.append("deactivate") })
        let loops = PiboSoundscapePlayback(runtime: runtime, makePlayer: { _, _ in Loop(events) })
        loops.apply(profile: profile, multiplier: 1, playing: true)
        await runtime.drain()
        try await Task.sleep(for: .milliseconds(500))
        await runtime.drain()
        #expect(events.read() == ["activate", "activate", "loop.decode", "loop.play"])
        loops.stop()
        await runtime.drain()
    }

    @Test func stoppingBeforeActivationRetryCannotReviveSound() async throws {
        enum Failure: Error { case unavailable }
        let events = Events()
        let runtime = PiboAudioRuntime(activate: { _ in
            events.append("activate")
            throw Failure.unavailable
        }, deactivate: {})
        let loops = PiboSoundscapePlayback(runtime: runtime, makePlayer: { _, _ in Loop(events) })
        loops.apply(profile: profile, multiplier: 1, playing: true)
        await runtime.drain()
        loops.stop()
        try await Task.sleep(for: .milliseconds(500))
        await runtime.drain()
        #expect(events.read() == ["activate"])
    }

    @Test func mediaResetDropsPreparedPlayersAndReactivatesBeforePlayback() async {
        let events = Events()
        let runtime = PiboAudioRuntime(activate: { _ in events.append("activate") },
                                       deactivate: { events.append("deactivate") })
        let loops = PiboSoundscapePlayback(runtime: runtime, makePlayer: { _, _ in Loop(events) })
        loops.apply(profile: profile, multiplier: 1, playing: true)
        loops.stop(invalidateSession: true)
        loops.apply(profile: profile, multiplier: 1, playing: true)
        await runtime.drain()
        #expect(events.read() == ["activate", "loop.decode", "loop.play", "loop.stop",
                                 "activate", "loop.decode", "loop.play"])
        loops.stop()
        await runtime.drain()
    }

    @Test func refusedCueDoesNotLeaveAnActiveSessionOrPlayerCached() async {
        let events = Events()
        let runtime = PiboAudioRuntime(activate: { _ in events.append("activate") },
                                       deactivate: {})
        let cues = PiboCuePlayback(runtime: runtime, makePlayer: { _ in
            Cue(events, succeeds: events.read().filter { $0 == "cue.decode" }.count > 0)
        })
        cues.play(cueURL, volume: 0.3)
        cues.play(cueURL, volume: 0.3)
        await runtime.drain()
        #expect(events.read() == ["activate", "cue.decode", "cue.play", "activate", "cue.decode", "cue.play"])
    }
}

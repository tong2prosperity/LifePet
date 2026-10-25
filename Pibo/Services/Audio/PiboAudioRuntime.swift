import AVFAudio
import Foundation
import os

/// The process has one AVAudioSession. All three players share its queue and
/// only record activation after it succeeds, before decoding or playing audio.
nonisolated final class PiboAudioRuntime: @unchecked Sendable {
    static let shared = PiboAudioRuntime()
    let queue = DispatchQueue(label: "com.piboworld.audio", qos: .userInitiated)

    private let activate: @Sendable (AVAudioSession.Category) throws -> Void
    private let deactivate: @Sendable () throws -> Void
    private var category: AVAudioSession.Category?
    private var playbackOwners: Set<UUID> = []

    init(
        activate: @escaping @Sendable (AVAudioSession.Category) throws -> Void = { category in
            let session = AVAudioSession.sharedInstance()
            if session.category != category {
                try session.setCategory(category, mode: .default,
                                        options: category == .playback ? [.mixWithOthers] : [])
            }
            try session.setActive(true)
        },
        deactivate: @escaping @Sendable () throws -> Void = {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    ) {
        self.activate = activate
        self.deactivate = deactivate
    }

    func prepareCue(category requested: AVAudioSession.Category = .ambient) throws {
        dispatchPrecondition(condition: .onQueue(queue))
        try ensureActive(playbackOwners.isEmpty ? requested : .playback)
    }

    func beginPlayback(owner: UUID) throws {
        dispatchPrecondition(condition: .onQueue(queue))
        try ensureActive(.playback)
        playbackOwners.insert(owner)
    }

    func endPlayback(owner: UUID) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard playbackOwners.remove(owner) != nil, playbackOwners.isEmpty, category != nil else { return }
        category = nil
        do { try deactivate() }
        catch { LPLog.audio.error("audio session deactivation failed: \(error.localizedDescription, privacy: .public)") }
    }

    /// Called on the audio queue after interruption, foregrounding or media reset.
    /// A cached category is not evidence that the system still has an active session.
    func invalidate() {
        dispatchPrecondition(condition: .onQueue(queue))
        category = nil
    }

    func invalidateAsync() { queue.async { self.invalidate() } }

    func drain() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    private func ensureActive(_ requested: AVAudioSession.Category) throws {
        guard category != requested else { return }
        // Failure must not leave a successful-looking activation cached.
        category = nil
        try activate(requested)
        category = requested
        LPLog.audio.info("audio session active category=\(requested.rawValue, privacy: .public)")
    }
}

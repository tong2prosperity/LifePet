import Foundation
import Observation
import SwiftUI

/// Owns the transient Home speech bubble and its one pending auto-clear task.
/// Speech selection stays in `PiboSpeechService`; this type only presents the
/// already-resolved line with the existing Home animations and linger policy.
@MainActor
@Observable
final class HomeSpeechPresentationController {
    typealias ClearScheduler = @MainActor (
        _ duration: TimeInterval,
        _ clear: @escaping @MainActor () -> Void
    ) -> Task<Void, Never>

    private(set) var line: PiboSpeechLine?

    @ObservationIgnored private var clearTask: Task<Void, Never>?
    @ObservationIgnored private let scheduleClear: ClearScheduler

    init(
        line: PiboSpeechLine? = nil,
        scheduleClear: @escaping ClearScheduler = { duration, clear in
            Task {
                try? await Task.sleep(for: .seconds(duration))
                if !Task.isCancelled { clear() }
            }
        }
    ) {
        self.line = line
        self.scheduleClear = scheduleClear
    }

    func dismiss() {
        clearTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { line = nil }
    }

    func show(_ line: PiboSpeechLine) {
        clearTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
            self.line = line
        }
        let linger = HomeSpeechPresentationPolicy.lingerDuration(for: line)
        clearTask = scheduleClear(linger) { [self] in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                self.line = nil
            }
        }
    }

    func show(_ speech: PiboSpeech) {
        show(HomeSpeechPresentationPolicy.line(for: speech))
    }
}

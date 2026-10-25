import Foundation
import Observation

/// An old capture may finish after cancellation (Photos/Vision/file I/O need not
/// cooperate). Only the current attempt may update the camera or clear its task.
@MainActor
@Observable
final class CameraCaptureTaskController {
    private(set) var isRunning = false
    private(set) var isProcessing = false
    @ObservationIgnored private var currentID: UUID?
    @ObservationIgnored private var task: Task<Void, Never>?

    func run(processing: Bool = true, _ operation: @escaping @MainActor (UUID) async -> Void) {
        cancel()
        let id = UUID()
        currentID = id
        isRunning = true
        isProcessing = processing
        task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await operation(id)
            self?.finish(id)
        }
    }

    func isCurrent(_ id: UUID) -> Bool { currentID == id && !Task.isCancelled }

    func markProcessing(_ id: UUID) {
        guard isCurrent(id) else { return }
        isProcessing = true
    }

    func cancel() {
        currentID = nil
        task?.cancel()
        task = nil
        isRunning = false
        isProcessing = false
    }

    func waitForCurrent() async { await task?.value }

    private func finish(_ id: UUID) {
        guard currentID == id else { return }
        currentID = nil
        task = nil
        isRunning = false
        isProcessing = false
    }
}

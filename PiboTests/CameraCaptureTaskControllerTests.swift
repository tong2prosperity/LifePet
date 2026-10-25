import Foundation
import Testing
@testable import Pibo

@MainActor
struct CameraCaptureTaskControllerTests {
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var opened = false
        func wait() async {
            if opened { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() { opened = true; continuation?.resume(); continuation = nil }
    }

    @Test func oldCompletionCannotClearOrUpdateANewerCapture() async {
        let controller = CameraCaptureTaskController()
        let old = Gate(), next = Gate()
        var effects: [String] = []
        controller.run { id in
            await old.wait()
            if controller.isCurrent(id) { effects.append("old") }
        }
        await Task.yield()
        controller.cancel()
        controller.run { id in
            await next.wait()
            if controller.isCurrent(id) { effects.append("next") }
        }
        await Task.yield()
        old.open()
        await Task.yield()
        #expect(controller.isRunning)
        #expect(controller.isProcessing)
        #expect(effects.isEmpty)
        next.open()
        await controller.waitForCurrent()
        #expect(effects == ["next"])
        #expect(!controller.isRunning)
    }

    @Test func cancellationDuringPostSaveWorkCannotDismissOrCelebrate() async {
        let controller = CameraCaptureTaskController()
        let write = Gate()
        var dismissed = false
        controller.run(processing: false) { id in
            #expect(!controller.isProcessing)
            controller.markProcessing(id)
            await write.wait() // represents a non-cooperative thumbnail write
            guard controller.isCurrent(id) else { return }
            dismissed = true
        }
        await Task.yield()
        #expect(controller.isProcessing)
        controller.cancel()
        write.open()
        await Task.yield()
        #expect(!dismissed)
        #expect(!controller.isRunning)
        #expect(!controller.isProcessing)
    }
}

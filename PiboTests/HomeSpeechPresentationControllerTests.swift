import Foundation
import Testing
@testable import Pibo

@MainActor
struct HomeSpeechPresentationControllerTests {
    @Test func showUsesLingerPolicyAndScheduledClear() {
        var scheduledDuration: TimeInterval?
        var scheduledClear: (@MainActor () -> Void)?
        let controller = HomeSpeechPresentationController { duration, clear in
            scheduledDuration = duration
            scheduledClear = clear
            return Task {}
        }
        let line = PiboSpeechLine(text: "data", data: .init(
            prefix: "",
            value: "1",
            suffix: ""
        ))

        controller.show(line)

        #expect(controller.line == line)
        #expect(scheduledDuration == 5)
        scheduledClear?()
        #expect(controller.line == nil)
    }

    @Test func replacingSpeechCancelsThePreviousClearTask() {
        var tasks: [Task<Void, Never>] = []
        let controller = HomeSpeechPresentationController { _, _ in
            let task = Task<Void, Never> {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {}
            }
            tasks.append(task)
            return task
        }

        controller.show(PiboSpeechLine(text: "first"))
        controller.show(PiboSpeechLine(text: "second"))

        #expect(tasks.count == 2)
        #expect(tasks[0].isCancelled)
        #expect(!tasks[1].isCancelled)
        #expect(controller.line?.text == "second")
        tasks.forEach { $0.cancel() }
    }

    @Test func dismissCancelsPendingClearAndRemovesLine() {
        var task: Task<Void, Never>?
        let controller = HomeSpeechPresentationController { _, _ in
            let scheduled = Task<Void, Never> {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {}
            }
            task = scheduled
            return scheduled
        }
        controller.show(PiboSpeechLine(text: "line"))

        controller.dismiss()

        #expect(task?.isCancelled == true)
        #expect(controller.line == nil)
    }

    @Test func resolvedSpeechKeepsPresentationMapping() {
        let controller = HomeSpeechPresentationController { _, _ in Task {} }

        controller.show(PiboSpeech(
            id: "story",
            text: "remembered",
            presentation: .story,
            cueKey: "story.cue"
        ))

        #expect(controller.line?.text == "remembered")
        #expect(controller.line?.mood == .normal)
        #expect(controller.line?.isStoryClue == true)
    }
}

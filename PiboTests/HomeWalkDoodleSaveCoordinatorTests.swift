import Testing
@testable import Pibo

@MainActor
struct HomeWalkDoodleSaveCoordinatorTests {
    @Test func persistsResolvesAndShowsInOrder() {
        let result = makeResult()
        let speech = PiboSpeech(
            id: "walk-line",
            text: "I recorded that route.",
            presentation: .normal,
            cueKey: "walk.completed"
        )
        var events: [String] = []

        HomeWalkDoodleSaveCoordinator.run(
            result: result,
            persist: { persisted in
                #expect(persisted == result)
                events.append("persist")
            },
            resolveSpeech: { cues, context in
                #expect(cues.count == 1)
                guard let cue = cues.first else {
                    Issue.record("Walk completion must resolve one semantic cue")
                    return nil
                }
                #expect(cue.key == "walk.completed")
                #expect(cue.values == [
                    "distance": "346",
                    "distanceUnit": "米",
                    "minutes": "3",
                ])
                #expect(context.surface == .home)
                #expect(context.trigger == .completed)
                #expect(context.length == .short)
                events.append("resolve")
                return speech
            },
            show: { resolved in
                #expect(resolved == speech)
                events.append("show")
            }
        )

        #expect(events == ["persist", "resolve", "show"])
    }

    @Test func silenceStillPersistsAndResolvesWithoutShowing() {
        let result = makeResult()
        var events: [String] = []

        HomeWalkDoodleSaveCoordinator.run(
            result: result,
            persist: { _ in events.append("persist") },
            resolveSpeech: { _, _ in
                events.append("resolve")
                return nil
            },
            show: { _ in events.append("show") }
        )

        #expect(events == ["persist", "resolve"])
    }

    private func makeResult() -> WalkDoodleResult {
        WalkDoodleResult(
            coordinates: [],
            distanceMeters: 345.7,
            areaSquareMeters: 128.9,
            duration: 181,
            title: nil
        )
    }
}

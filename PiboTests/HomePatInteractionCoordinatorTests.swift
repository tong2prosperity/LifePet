import XCTest
@testable import Pibo

@MainActor
final class HomePatInteractionCoordinatorTests: XCTestCase {
    func testAngryEntryPreservesRefreshTransitionSpeechAndAnalyticsOrder() {
        let recorder = Recorder(
            currentStates: ["angry", "angry"],
            enteredAngry: true
        )

        HomePatInteractionCoordinator.run(
            localHour: 14.5,
            sourceStateID: "pibo-state-stable-forest-idle",
            handlers: recorder.handlers
        )

        XCTAssertEqual(
            recorder.events,
            [
                "register:14.5:true", "refresh", "state:angry",
                "event:angry", "state:angry",
                "line:pibo:angry", "reaction:angry",
            ]
        )
        XCTAssertEqual(recorder.resolveCount, 0)
    }

    func testSleepingStateDoesNotTransitionOrResolveSpeech() {
        let recorder = Recorder(currentStates: ["pibo-state-sleeping-hammock-idle-a", "pibo-state-sleeping-hammock-idle-a"])

        HomePatInteractionCoordinator.run(
            localHour: 2,
            sourceStateID: "pibo-state-sleeping-hammock-idle-a",
            handlers: recorder.handlers
        )

        XCTAssertEqual(
            recorder.events,
            [
                "register:2.0:false", "refresh", "state:pibo-state-sleeping-hammock-idle-a", "state:pibo-state-sleeping-hammock-idle-a",
                "line:system:normal", "reaction:protected_state",
            ]
        )
        XCTAssertEqual(recorder.resolveCount, 0)
    }

    func testAwakeStateResolvesOnceAndStaysSilentWhenPolicyDeclines() {
        let recorder = Recorder(
            currentStates: ["pibo-state-waking-hammock-idle", "pibo-state-waking-hammock-idle"],
            resolution: .init(
                speech: nil,
                shouldSpeak: false,
                countsTowardAngry: false
            )
        )

        HomePatInteractionCoordinator.run(
            localHour: 8,
            sourceStateID: "pibo-state-waking-hammock-idle",
            handlers: recorder.handlers
        )

        XCTAssertEqual(
            recorder.events,
            [
                "register:8.0:false", "refresh", "state:pibo-state-waking-hammock-idle", "state:pibo-state-waking-hammock-idle",
                "resolve:false:true", "reaction:silent",
            ]
        )
        XCTAssertEqual(recorder.resolveCount, 1)
    }

    func testAwakeStateShowsAuthoredLineWhenPolicyAllowsIt() {
        let recorder = Recorder(
            currentStates: ["pibo-state-waking-hammock-idle", "pibo-state-waking-hammock-idle"],
            resolution: .init(
                speech: nil,
                shouldSpeak: true,
                countsTowardAngry: false
            )
        )

        HomePatInteractionCoordinator.run(
            localHour: 8,
            sourceStateID: "pibo-state-waking-hammock-idle",
            handlers: recorder.handlers
        )

        XCTAssertEqual(
            recorder.events.suffix(3),
            [
                "resolve:false:true", "line:pibo:normal", "reaction:protected_state",
            ]
        )
        XCTAssertEqual(recorder.resolveCount, 1)
    }

    func testOrdinaryStateShowsResolvedSpeechBeforeTrackingReaction() {
        let speech = PiboSpeech(
            id: "test",
            text: "resolved",
            presentation: .murmur,
            cueKey: "test"
        )
        let recorder = Recorder(
            currentStates: ["pibo-state-stable-forest-idle", "pibo-state-stable-forest-idle"],
            resolution: .init(
                speech: speech,
                shouldSpeak: true,
                countsTowardAngry: true
            )
        )

        HomePatInteractionCoordinator.run(
            localHour: 12,
            sourceStateID: "pibo-state-stable-forest-idle",
            handlers: recorder.handlers
        )

        XCTAssertEqual(
            recorder.events.suffix(3),
            ["resolve:false:false", "speech:resolved:murmur", "reaction:spoke"]
        )
        XCTAssertEqual(recorder.resolveCount, 1)
    }

    func testAngryStateStaysSilentWithoutResolvingSpeech() {
        let recorder = Recorder(currentStates: ["angry", "angry"])

        HomePatInteractionCoordinator.run(
            localHour: 12,
            sourceStateID: "angry",
            handlers: recorder.handlers
        )

        XCTAssertEqual(recorder.events.last, "reaction:silent")
        XCTAssertEqual(recorder.resolveCount, 0)
    }
}

@MainActor
private final class Recorder {
    var events: [String] = []
    var resolveCount = 0

    private var currentStates: [String]
    private let enteredAngry: Bool
    private let resolution: PiboHomePatResolution

    init(
        currentStates: [String],
        enteredAngry: Bool = false,
        resolution: PiboHomePatResolution = .init(
            speech: nil,
            shouldSpeak: false,
            countsTowardAngry: true
        )
    ) {
        self.currentStates = currentStates
        self.enteredAngry = enteredAngry
        self.resolution = resolution
    }

    var handlers: HomePatInteractionCoordinator.Handlers {
        .init(
            registerActualPat: { [self] localHour, countsTowardAngry in
                events.append("register:\(localHour):\(countsTowardAngry)")
                return enteredAngry
            },
            refreshAnimationState: { [self] in events.append("refresh") },
            currentAnimationStateID: { [self] in
                let state = currentStates.removeFirst()
                events.append("state:\(state)")
                return state
            },
            transitionAnimation: { [self] stateID, intent in
                events.append("transition:\(stateID):\(intent)")
            },
            performAnimationEvent: { [self] stateID in
                events.append("event:\(stateID)")
            },
            resolvePatSpeech: { [self] context in
                resolveCount += 1
                events.append("resolve:\(context.sleeping):\(context.resting)")
                return resolution
            },
            showAnimationLine: { [self] line in
                let source = line.source == .system ? "system" : "pibo"
                let mood = switch line.mood {
                case .normal: "normal"
                case .angry: "angry"
                case .murmur: "murmur"
                }
                events.append("line:\(source):\(mood)")
            },
            showResolvedSpeech: { [self] speech in
                events.append("speech:\(speech.text):\(speech.presentation.rawValue)")
            },
            trackReaction: { [self] reaction in
                events.append("reaction:\(reaction.rawValue)")
            }
        )
    }
}

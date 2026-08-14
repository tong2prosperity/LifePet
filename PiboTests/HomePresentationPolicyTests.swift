import XCTest
@testable import Pibo

@MainActor
final class HomePresentationPolicyTests: XCTestCase {
    func testEveryCoverAndSheetPausesTheStage() {
        XCTAssertFalse(stagePaused())

        for occupiedIndex in 0..<7 {
            var occupied = Array(repeating: false, count: 7)
            occupied[occupiedIndex] = true

            XCTAssertTrue(stagePaused(occupied), "Condition \(occupiedIndex) did not pause")
        }
    }

    func testEveryCoverCountsAsFullScreen() {
        XCTAssertFalse(fullScreenFeaturePresented())

        for occupiedIndex in 0..<6 {
            var occupied = Array(repeating: false, count: 6)
            occupied[occupiedIndex] = true

            XCTAssertTrue(
                fullScreenFeaturePresented(occupied),
                "Condition \(occupiedIndex) did not count as full-screen"
            )
        }
    }

    func testSheetPausesStageWithoutBecomingAFullScreenFeature() {
        XCTAssertTrue(stagePaused([false, false, false, false, false, false, true]))
        XCTAssertFalse(fullScreenFeaturePresented())
    }

    func testBoCounterFeedbackRequiresAnActiveUnoccupiedSettledHome() {
        XCTAssertTrue(policy().boCounterFeedbackEnabled)
        XCTAssertFalse(policy(sceneIsActive: false).boCounterFeedbackEnabled)
        XCTAssertFalse(policy(occupied: [true, false, false, false, false, false, false])
            .boCounterFeedbackEnabled)
        XCTAssertFalse(policy(sheetDismissalInProgress: true).boCounterFeedbackEnabled)
        XCTAssertFalse(policy(sproutFlowIsIdle: false).boCounterFeedbackEnabled)
    }

    func testSoundscapeIsActiveOnlyForAnActiveUncoveredHome() {
        XCTAssertEqual(policy().soundscapePresentation, .active)
        XCTAssertEqual(policy(sceneIsActive: false).soundscapePresentation, .suspended)
        XCTAssertEqual(
            policy(occupied: [true, false, false, false, false, false, false])
                .soundscapePresentation,
            .suspended
        )
        XCTAssertEqual(
            policy(occupied: [false, false, false, false, false, false, true])
                .soundscapePresentation,
            .suspended
        )
    }

    func testStagePauseKeepsLeftToRightShortCircuiting() {
        let probe = ReadProbe()

        let policy = HomePresentationPolicy(
            sceneIsActive: true,
            cameraPresented: true,
            gamesPresented: probe.read(false),
            historyPresented: probe.read(false),
            walkDoodlePresented: probe.read(false),
            settingsPresented: probe.read(false),
            storyRecoveryPresented: probe.read(false),
            sheetPresented: probe.read(false),
            sheetDismissalInProgress: false,
            sproutFlowIsIdle: true
        )

        XCTAssertTrue(policy.stagePaused)
        XCTAssertEqual(probe.count, 0)
    }

    func testInactiveSceneShortCircuitsFeedbackAndSoundscapeInputs() {
        let feedbackProbe = ReadProbe()
        let soundscapeProbe = ReadProbe()

        let feedbackPolicy = HomePresentationPolicy(
            sceneIsActive: false,
            cameraPresented: feedbackProbe.read(false),
            gamesPresented: feedbackProbe.read(false),
            historyPresented: feedbackProbe.read(false),
            walkDoodlePresented: feedbackProbe.read(false),
            settingsPresented: feedbackProbe.read(false),
            storyRecoveryPresented: feedbackProbe.read(false),
            sheetPresented: feedbackProbe.read(false),
            sheetDismissalInProgress: feedbackProbe.read(false),
            sproutFlowIsIdle: feedbackProbe.read(true)
        )
        XCTAssertFalse(feedbackPolicy.boCounterFeedbackEnabled)
        XCTAssertEqual(feedbackProbe.count, 0)

        let soundscapePolicy = HomePresentationPolicy(
            sceneIsActive: false,
            cameraPresented: soundscapeProbe.read(false),
            gamesPresented: soundscapeProbe.read(false),
            historyPresented: soundscapeProbe.read(false),
            walkDoodlePresented: soundscapeProbe.read(false),
            settingsPresented: soundscapeProbe.read(false),
            storyRecoveryPresented: soundscapeProbe.read(false),
            sheetPresented: soundscapeProbe.read(false),
            sheetDismissalInProgress: soundscapeProbe.read(false),
            sproutFlowIsIdle: soundscapeProbe.read(true)
        )
        XCTAssertEqual(soundscapePolicy.soundscapePresentation, .suspended)
        XCTAssertEqual(soundscapeProbe.count, 0)
    }

    func testPresentationAdapterReadsEveryLiveCoverFlag() {
        let presentation = HomeFeaturePresentationState()
        let policy = HomePresentationPolicy(
            sceneIsActive: true,
            presentation: presentation,
            sheetPresented: false,
            sheetDismissalInProgress: false,
            sproutFlowIsIdle: true
        )

        let setPresented: [(HomeFeaturePresentationState) -> Void] = [
            { $0.showCamera = true },
            { $0.showGames = true },
            { $0.showHistory = true },
            { $0.showWalkDoodle = true },
            { $0.showSettings = true },
            { $0.showStoryRecovery = true },
        ]
        for update in setPresented {
            update(presentation)
            XCTAssertTrue(policy.stagePaused)
            XCTAssertTrue(policy.fullScreenFeaturePresented)
            presentation.showCamera = false
            presentation.showGames = false
            presentation.showHistory = false
            presentation.showWalkDoodle = false
            presentation.showSettings = false
            presentation.showStoryRecovery = false
        }
    }

    private func stagePaused(_ occupied: [Bool] = Array(repeating: false, count: 7)) -> Bool {
        policy(occupied: occupied).stagePaused
    }

    private func fullScreenFeaturePresented(
        _ occupied: [Bool] = Array(repeating: false, count: 6)
    ) -> Bool {
        policy(occupied: occupied).fullScreenFeaturePresented
    }

    private func policy(
        sceneIsActive: Bool = true,
        occupied: [Bool] = Array(repeating: false, count: 7),
        sheetDismissalInProgress: Bool = false,
        sproutFlowIsIdle: Bool = true
    ) -> HomePresentationPolicy {
        HomePresentationPolicy(
            sceneIsActive: sceneIsActive,
            cameraPresented: occupied[0],
            gamesPresented: occupied[1],
            historyPresented: occupied[2],
            walkDoodlePresented: occupied[3],
            settingsPresented: occupied[4],
            storyRecoveryPresented: occupied[5],
            sheetPresented: occupied[6],
            sheetDismissalInProgress: sheetDismissalInProgress,
            sproutFlowIsIdle: sproutFlowIsIdle
        )
    }
}

private final class ReadProbe {
    private(set) var count = 0

    func read(_ value: Bool) -> Bool {
        count += 1
        return value
    }
}

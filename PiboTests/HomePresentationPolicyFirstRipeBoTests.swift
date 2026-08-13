import XCTest
@testable import Pibo

@MainActor
final class HomePresentationPolicyFirstRipeBoTests: XCTestCase {
    func testAnnouncementRequiresEveryEligibilityCondition() {
        XCTAssertTrue(shouldAnnounce())
        XCTAssertFalse(shouldAnnounce(hasRipeBo: false))
        XCTAssertFalse(shouldAnnounce(wasAnnounced: true))
        XCTAssertFalse(shouldAnnounce(sceneIsActive: false))
        XCTAssertFalse(shouldAnnounce(stagePaused: true))
        XCTAssertFalse(shouldAnnounce(sproutFlowIsIdle: false))
        XCTAssertFalse(shouldAnnounce(speechIsAbsent: false))
        XCTAssertFalse(shouldAnnounce(idleSpeechContextAvailable: false))
    }

    func testAnnouncementPreservesGuardReadOrder() {
        let probe = ReadProbe()
        let policy = HomePresentationPolicy(
            sceneIsActive: probe.read(true, named: "scene"),
            cameraPresented: probe.read(false, named: "camera"),
            gamesPresented: probe.read(false, named: "games"),
            historyPresented: probe.read(false, named: "history"),
            walkDoodlePresented: probe.read(false, named: "doodle"),
            settingsPresented: probe.read(false, named: "settings"),
            storyRecoveryPresented: probe.read(false, named: "recovery"),
            sheetPresented: probe.read(false, named: "sheet"),
            sheetDismissalInProgress: false,
            sproutFlowIsIdle: probe.read(true, named: "sprout")
        )

        XCTAssertTrue(policy.shouldAnnounceFirstRipeBo(
            hasRipeBo: probe.read(true, named: "ripe"),
            wasAnnounced: probe.read(false, named: "announced"),
            speechIsAbsent: probe.read(true, named: "speech"),
            idleSpeechContextAvailable: probe.read(true, named: "context")
        ))
        XCTAssertEqual(
            probe.names,
            [
                "ripe", "announced", "scene", "camera", "games", "history",
                "doodle", "settings", "recovery", "sheet", "sprout", "speech",
                "context",
            ]
        )
    }

    func testAnExistingAnnouncementShortCircuitsAllHomeStateReads() {
        let probe = ReadProbe()
        let policy = HomePresentationPolicy(
            sceneIsActive: probe.read(true, named: "scene"),
            cameraPresented: probe.read(false, named: "camera"),
            gamesPresented: probe.read(false, named: "games"),
            historyPresented: probe.read(false, named: "history"),
            walkDoodlePresented: probe.read(false, named: "doodle"),
            settingsPresented: probe.read(false, named: "settings"),
            storyRecoveryPresented: probe.read(false, named: "recovery"),
            sheetPresented: probe.read(false, named: "sheet"),
            sheetDismissalInProgress: false,
            sproutFlowIsIdle: probe.read(true, named: "sprout")
        )

        XCTAssertFalse(policy.shouldAnnounceFirstRipeBo(
            hasRipeBo: probe.read(true, named: "ripe"),
            wasAnnounced: probe.read(true, named: "announced"),
            speechIsAbsent: probe.read(true, named: "speech"),
            idleSpeechContextAvailable: probe.read(true, named: "context")
        ))
        XCTAssertEqual(probe.names, ["ripe", "announced"])
    }

    private func shouldAnnounce(
        hasRipeBo: Bool = true,
        wasAnnounced: Bool = false,
        sceneIsActive: Bool = true,
        stagePaused: Bool = false,
        sproutFlowIsIdle: Bool = true,
        speechIsAbsent: Bool = true,
        idleSpeechContextAvailable: Bool = true
    ) -> Bool {
        let policy = HomePresentationPolicy(
            sceneIsActive: sceneIsActive,
            cameraPresented: stagePaused,
            gamesPresented: false,
            historyPresented: false,
            walkDoodlePresented: false,
            settingsPresented: false,
            storyRecoveryPresented: false,
            sheetPresented: false,
            sheetDismissalInProgress: false,
            sproutFlowIsIdle: sproutFlowIsIdle
        )
        return policy.shouldAnnounceFirstRipeBo(
            hasRipeBo: hasRipeBo,
            wasAnnounced: wasAnnounced,
            speechIsAbsent: speechIsAbsent,
            idleSpeechContextAvailable: idleSpeechContextAvailable
        )
    }
}

@MainActor
private final class ReadProbe {
    private(set) var names: [String] = []

    func read<Value>(_ value: Value, named name: String) -> Value {
        names.append(name)
        return value
    }
}

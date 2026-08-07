import Foundation
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct OrnamentUnlockFlowCoordinatorTests {
    @Test func holdCompletesAtInjectedBoundary() async {
        let flow = OrnamentUnlockFlowCoordinator(holdDuration: .milliseconds(20))
        var completed = false
        flow.present(selected: .hammock, reduceMotion: true)

        await withCheckedContinuation { continuation in
            flow.beginHold(.hammock, reduceMotion: false) {
                completed = true
                continuation.resume()
            }
        }

        #expect(completed)
        #expect(flow.holdProgress == 1)
        #expect(flow.phase == .holding(.hammock))
    }

    @Test func releasingEarlyCancelsWithoutCompletion() async {
        let flow = OrnamentUnlockFlowCoordinator(holdDuration: .milliseconds(40))
        var completed = false
        flow.present(selected: .chime, reduceMotion: true)

        flow.beginHold(.chime, reduceMotion: false) {
            completed = true
        }
        flow.cancelHold()
        try? await Task.sleep(for: .milliseconds(55))

        #expect(!completed)
        #expect(flow.phase == .browsing(.chime))
    }

    @Test func disappearingOverlayCancelsDelayedWork() async {
        let flow = OrnamentUnlockFlowCoordinator(holdDuration: .milliseconds(30))
        var completed = false
        flow.present(selected: .hammock, reduceMotion: true)
        flow.beginHold(.hammock, reduceMotion: false) {
            completed = true
        }

        flow.dispose()
        try? await Task.sleep(for: .milliseconds(45))

        #expect(!completed)
    }

    @Test func backgroundCancelsPreviewAndFinishesCommittedVisuals() {
        let flow = OrnamentUnlockFlowCoordinator()
        flow.present(selected: .statusObserver, reduceMotion: true)
        flow.beginPlacementPreview(.statusObserver)
        #expect(flow.prepareForBackground() == nil)
        #expect(flow.phase == .browsing(.statusObserver))

        flow.beginHold(.statusObserver, reduceMotion: true) {}
        #expect(flow.beginCommit(.statusObserver))
        flow.beginMaterializing(.statusObserver)
        #expect(flow.prepareForBackground() == .statusObserver)
        #expect(flow.phase == .success(.statusObserver))
    }

    @Test func commitGateRejectsDuplicateEntry() {
        let flow = OrnamentUnlockFlowCoordinator()
        flow.present(selected: .lantern, reduceMotion: true)
        flow.beginHold(.lantern, reduceMotion: true) {}

        #expect(flow.beginCommit(.lantern))
        #expect(!flow.beginCommit(.lantern))
    }

    @Test func confirmedTapCommitsDirectlyFromBrowsing() {
        let flow = OrnamentUnlockFlowCoordinator()
        flow.present(selected: .hammock, reduceMotion: true)

        #expect(flow.beginCommit(.hammock))
        #expect(flow.phase == .committing(.hammock))
    }

    @Test func activeHoldRemainsEnabledUntilRelease() {
        let flow = OrnamentUnlockFlowCoordinator()
        flow.present(selected: .hammock, reduceMotion: true)

        #expect(flow.canContinueHold(.hammock))
        flow.beginHold(.hammock, reduceMotion: false) {}
        #expect(flow.phase == .holding(.hammock))
        #expect(flow.isBusy)
        #expect(flow.canContinueHold(.hammock))
        #expect(!flow.canContinueHold(.chime))

        flow.cancelHold()
        #expect(flow.phase == .browsing(.hammock))
        #expect(flow.canContinueHold(.hammock))
    }

    @Test func successCannotBeOverwrittenByBrowsingOrDismissal() {
        let flow = OrnamentUnlockFlowCoordinator()
        flow.present(selected: .statusObserver, reduceMotion: true)
        flow.beginHold(.statusObserver, reduceMotion: true) {}
        #expect(flow.beginCommit(.statusObserver))
        flow.beginMaterializing(.statusObserver)
        flow.completeMaterialization(.statusObserver)

        #expect(flow.phase == .success(.statusObserver))
        #expect(flow.isBusy)
        flow.select(.lantern)
        flow.beginDismiss(reduceMotion: true) {
            Issue.record("Success must leave through the explicit forest return")
        }
        #expect(flow.phase == .success(.statusObserver))
    }

    @Test func appBundleContainsUnlockMotionAndEverySoundCue() {
        let manifest = Bundle.main.url(
            forResource: "ornament_motion_manifest",
            withExtension: "json",
            subdirectory: "OrnamentUnlock"
        ) ?? Bundle.main.url(forResource: "ornament_motion_manifest", withExtension: "json")
        #expect(manifest != nil)

        for name in OrnamentUnlockSoundService.allAssetNames {
            let url = Bundle.main.url(
                forResource: name,
                withExtension: "m4a",
                subdirectory: "Audio/OrnamentUnlock"
            ) ?? Bundle.main.url(forResource: name, withExtension: "m4a")
            #expect(url != nil, "Missing bundled ornament sound: \(name).m4a")
        }
    }

    @Test func bundledMotionManifestMatchesRuntimeTiming() throws {
        let url = try #require(
            Bundle.main.url(
                forResource: "ornament_motion_manifest",
                withExtension: "json",
                subdirectory: "OrnamentUnlock"
            ) ?? Bundle.main.url(forResource: "ornament_motion_manifest", withExtension: "json")
        )
        let manifest = try JSONDecoder().decode(
            OrnamentMotionManifest.self,
            from: Data(contentsOf: url)
        )

        #expect(manifest.durationMs == Int(OrnamentUnlockMotion.materializationMilliseconds))
        #expect(manifest.easingBezier == OrnamentUnlockMotion.easingBezier)
        #expect(manifest.stage("bo-invest")?.startMs == 0)
        #expect(manifest.stage("bo-invest")?.durationMs == Int(OrnamentUnlockMotion.flightMilliseconds))
        #expect(manifest.stage("foundation")?.startMs == Int(OrnamentUnlockMotion.flightMilliseconds))
        #expect(manifest.stage("foundation")?.durationMs == Int(OrnamentUnlockMotion.layerMilliseconds))
        #expect(manifest.stage("structure")?.startMs == Int(
            OrnamentUnlockMotion.flightMilliseconds + OrnamentUnlockMotion.layerMilliseconds
        ))
        #expect(manifest.stage("structure")?.durationMs == Int(OrnamentUnlockMotion.layerMilliseconds))
        #expect(manifest.stage("detail")?.startMs == Int(
            OrnamentUnlockMotion.flightMilliseconds + 2 * OrnamentUnlockMotion.layerMilliseconds
        ))
        #expect(manifest.stage("detail")?.durationMs == Int(OrnamentUnlockMotion.layerMilliseconds))
        #expect(manifest.stage("confirm")?.startMs == Int(
            OrnamentUnlockMotion.flightMilliseconds + 3 * OrnamentUnlockMotion.layerMilliseconds
        ))
        #expect(manifest.stage("confirm")?.durationMs == Int(OrnamentUnlockMotion.confirmationMilliseconds))
        #expect(manifest.stage("confirm").map { $0.startMs + $0.durationMs } == manifest.durationMs)
    }
}

private struct OrnamentMotionManifest: Decodable {
    struct Stage: Decodable {
        let id: String
        let startMs: Int
        let durationMs: Int
    }

    let durationMs: Int
    let easingBezier: [Double]
    let stages: [Stage]

    func stage(_ id: String) -> Stage? {
        stages.first { $0.id == id }
    }
}

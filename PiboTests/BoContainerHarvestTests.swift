import Foundation
import CoreGraphics
import PiboCore
import Testing
@testable import Pibo

/// Decision 048: one head container, reserved energy, explicit collection, and
/// spending only the collected balance.
@Suite(.serialized)
@MainActor
struct BoContainerHarvestTests {
    private func ledger() throws -> (BoLedgerStore, UserDefaults, String) {
        let suite = "BoContainerHarvestTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = BoLedgerStore(
            defaults: defaults,
            persistenceKey: "test.ledger",
            syncPersistenceKey: "test.sync",
            acceptedAt: Date(timeIntervalSince1970: 1_700_000_000),
            eligibilitySource: .temporaryCooperation,
            eligibilityEnabled: true
        )
        return (store, defaults, suite)
    }

    @Test func energyBeyondOneUnitStaysReservedUntilCollected() throws {
        let (store, defaults, suite) = try ledger()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.debugSet(progress: 1)                       // one full unit in the pool
        #expect(store.debugApplyWorkout(durationMinutes: 600) == 1)
        let perBo = PiboCoreBoEconomy.energyPerBo
        #expect(store.state.ripeCount <= 1)
        #expect(store.hasRipeBo)
        #expect(store.availableBo == 0, "a ripe bo on the head is not spendable")
        #expect(!store.spend(1))

        let reserveBefore = store.state.energyPool
        #expect(store.collect(eventID: "c-1"))
        #expect(store.availableBo == 1)
        #expect(!store.collect(eventID: "c-1"), "collection is idempotent per event")
        // Reserved energy immediately forms the next unit when it can.
        if reserveBefore >= perBo {
            #expect(store.hasRipeBo)
            #expect(store.state.energyPool == reserveBefore - perBo)
        }
        #expect(store.spend(1))
        #expect(store.availableBo == 0)
        #expect(store.lifetimeCollected == 1)
    }

    @Test func legacyRipeQueueIsPreservedAndDrainedOneAtATime() throws {
        let (store, defaults, suite) = try ledger()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.debugSet(balance: 0, ripe: 3)
        #expect(store.collect(eventID: "a"))
        #expect(store.state.ripeCount == 2)
        #expect(store.availableBo == 1)
        #expect(store.collect(eventID: "b"))
        #expect(store.collect(eventID: "c"))
        #expect(!store.collect(eventID: "d"))
        #expect(store.availableBo == 3)
    }

    @Test func harvestTimelineFollowsCoreThresholds() {
        var timeline = PiboBoHarvestTimeline()
        timeline.beginDrag()
        let light = timeline.drag(upward: 30, ripe: true)
        #expect(!light.armed && !light.shouldRelease)
        let ready = timeline.drag(upward: 50, ripe: true)
        #expect(ready.armed && !ready.shouldRelease)
        #expect(!timeline.drag(upward: 60, ripe: true).armed, "armed fires once per drag")
        #expect(timeline.drag(upward: 80, ripe: true).shouldRelease)

        var unripe = PiboBoHarvestTimeline()
        unripe.beginDrag()
        let pulled = unripe.drag(upward: 500, ripe: false)
        #expect(!pulled.shouldRelease)
        #expect(unripe.pull <= 0.26)
    }

    @Test func releasePresentationReceivesThenFinishes() {
        var timeline = PiboBoHarvestTimeline()
        timeline.beginDrag()
        _ = timeline.drag(upward: 80, ripe: true)
        timeline.beginRelease()
        var events: [PiboBoHarvestTimeline.Event] = []
        for _ in 0..<80 { events += timeline.advance(deltaTime: 1.0 / 60, reduceMotion: false) }
        #expect(events == [.received, .finished])
        #expect(!timeline.isReleasing)
        #expect(timeline.pull == 0)

        var reduced = PiboBoHarvestTimeline()
        reduced.beginRelease()
        let quick = reduced.advance(deltaTime: 0.1, reduceMotion: true)
            + reduced.advance(deltaTime: 0.1, reduceMotion: true)
        #expect(quick == [.received, .finished])
    }

    @Test func ripeMotionFillsMonotonicallyAndSleepStaysStill() {
        var last: CGFloat = -1
        for frame in 0...409 {
            let pose = PiboBoRipeMotion.pose(seconds: Double(frame) / 60, participation: 1, reduced: false)
            #expect(pose.fill >= last)
            last = pose.fill
        }
        let end = PiboBoRipeMotion.pose(seconds: 6.8, participation: 1, reduced: false)
        #expect(end.fill == 1 && end.glow == 0 && end.faceY == 0 && end.bodyScaleY == 1)
        let sleeping = PiboBoRipeMotion.pose(seconds: 3.0, participation: PiboBoRipeMotion.participation(stateID: "pibo-state-sleeping-hammock-a"), reduced: false)
        #expect(sleeping.faceY == 0 && sleeping.arm == 0 && sleeping.eye == 1)
        #expect(sleeping.glow > 0)
        let reduced = PiboBoRipeMotion.pose(seconds: 0, participation: 1, reduced: true)
        #expect(reduced.fill == 1 && reduced.glow == 0)
    }

    @Test func collectionPoseOverridesOnlyWhileRipeOrCollecting() {
        let semantic = PiboAnimationResourceID.tired
        #expect(HomeStageSurface.Input.presentedStateID(semantic: semantic, hasRipeBo: false, harvestActive: false) == semantic)
        #expect(HomeStageSurface.Input.presentedStateID(semantic: semantic, hasRipeBo: true, harvestActive: false) == PiboAnimationResourceID.stable)
        #expect(HomeStageSurface.Input.presentedStateID(semantic: semantic, hasRipeBo: false, harvestActive: true) == PiboAnimationResourceID.stable)
    }
}

struct PiboEnergeticMotionTests {
    @Test func stretchOnlyLivesInABeatAndTheCycleIsSeamless() {
        let start = PiboEnergeticMotion.pose(seconds: 0, reduced: false)
        let end = PiboEnergeticMotion.pose(seconds: PiboEnergeticMotion.cycleSeconds - 0.0001, reduced: false)
        #expect(abs(start.scaleY - end.scaleY) < 0.001)
        #expect(abs(start.lift - end.lift) < 0.001)
        var tallFrames = 0
        for frame in 0..<216 {
            if PiboEnergeticMotion.pose(seconds: Double(frame) / 60, reduced: false).scaleY > 1.03 { tallFrames += 1 }
        }
        #expect(tallFrames < 20, "stretch must be a push-off accent, not a held posture")
        let reduced = PiboEnergeticMotion.pose(seconds: 1.0, reduced: true)
        #expect(reduced.lift == 0 && reduced.hand == 0 && reduced.sprout == 0)
    }
}

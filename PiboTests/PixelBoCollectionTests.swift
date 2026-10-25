import CoreGraphics
import Foundation
import PiboCore
import Testing
@testable import Pibo

@MainActor
struct PixelBoCollectionTests {
    private let size = CGSize(width: 402, height: 874)

    @Test func collectionAfterAnAbsenceKeepsTheActorVisible() throws {
        let suite = "PixelBoHideSeek.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date().timeIntervalSince1970
        let enteredAt = now
        let ledger = BoLedgerStore(defaults: defaults)
        ledger.debugSet(balance: 0, ripe: 1)
        let memory = PiboCompanionStore(defaults: defaults, clock: { now })
        memory.markVisible(now: now - 4 * 3600)
        let companion = HomeCompanionController(store: memory, clock: { now })
        companion.environment = .init(appActive: { true }, state: { .stable })
        companion.enterHome()
        defer { companion.leaveHome() }
        let renderer = PixelStageRenderer()
        var look = PixelStageRenderer.Look()
        look.leafRipe = true
        _ = renderer.render(size: size, scale: 3, now: now * 1000, look: look)
        renderer.onCollectBo = {
            let success = ledger.collect()
            if success { companion.onBoCollected() }
            return success
        }
        renderer.leafPan(-120, ripe: true)
        renderer.leafPanEnd()
        for second in [1.0, 3, 30] {
            now = enteredAt + second
            companion.tick()
            look.leafRipe = ledger.hasRipeBo
            look.leafGrowth = ledger.growthProgress
            _ = renderer.render(size: size, scale: 3, now: now * 1000, look: look)
            #expect(renderer.actorPresent, "the whole Pibo must remain drawable after collection")
        }
        #expect(ledger.availableBo == 1)
    }

    @Test func pixelDayStillOwnsRealHideAndFindPresentation() {
        final class QuietBrain: PixelDayBrain {
            func next(previous: PiboDayActivity) -> PixelDayPlan? { nil }
            func slow() -> Bool { false }
        }
        let brain = QuietBrain()
        let renderer = PixelStageRenderer()
        renderer.brain = brain
        let look = PixelStageRenderer.Look()
        let now = Date().timeIntervalSince1970 * 1000
        _ = renderer.render(size: size, scale: 3, now: now, look: look)
        renderer.director.greet(.hide, find: -1, hideSpot: .tallGrass,
                                hideMs: Double(PiboCoreDayRules.hideSeconds()) * 1000)
        _ = renderer.render(size: size, scale: 3, now: now + 50, look: look)
        #expect(renderer.director.hiding)
        #expect(!renderer.actorPresent, "real hiding remains a pixel director behavior")
        renderer.director.found()
        for frame in 2...240 {
            _ = renderer.render(size: size, scale: 3, now: now + Double(frame * 50), look: look)
        }
        #expect(!renderer.director.hiding)
        #expect(renderer.actorPresent, "the pixel find sequence must bring Pibo back visibly")
    }

    @Test func oneContinuousPullCollectsExactlyOneAndPersistsIt() throws {
        let suite = "PixelBoCollectionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = BoLedgerStore(defaults: defaults)
        ledger.debugSet(balance: 0, ripe: 3)
        let renderer = PixelStageRenderer()
        var look = PixelStageRenderer.Look()
        look.leafRipe = ledger.hasRipeBo
        let now = Date().timeIntervalSince1970 * 1000
        _ = renderer.render(size: size, scale: 3, now: now, look: look)
        var collections = 0
        renderer.onCollectBo = {
            collections += 1
            return ledger.collect(eventID: "pull-\(collections)")
        }
        // SwiftUI sends many onChanged callbacks after crossing the release threshold.
        for distance in [120.0, 125, 130, 140] {
            renderer.leafPan(-distance, ripe: ledger.hasRipeBo)
            look.leafRipe = ledger.hasRipeBo
            _ = renderer.render(size: size, scale: 3, now: now + distance, look: look)
        }
        #expect(collections == 1)
        #expect(ledger.availableBo == 1)
        #expect(ledger.state.ripeCount == 2)
        renderer.leafPanEnd()
        let restored = BoLedgerStore(defaults: defaults)
        #expect(restored.availableBo == 1)
        #expect(restored.state.ripeCount == 2)
        renderer.leafPan(-120, ripe: true)
        renderer.leafPanEnd()
        #expect(ledger.availableBo == 2, "a new pull can collect the next preserved ripe unit")
    }

    @Test func failedCollectionKeepsTheLeafAndWaitsForAnotherGesture() {
        let renderer = PixelStageRenderer()
        var look = PixelStageRenderer.Look()
        look.leafRipe = true
        let now = Date().timeIntervalSince1970 * 1000
        _ = renderer.render(size: size, scale: 3, now: now, look: look)
        var attempts = 0
        renderer.onCollectBo = { attempts += 1; return false }
        renderer.leafPan(-120, ripe: true)
        renderer.leafPan(-130, ripe: true)
        #expect(attempts == 1, "one gesture must not repeatedly submit a failed collection")
        renderer.leafPanEnd()
        _ = renderer.render(size: size, scale: 3, now: now + 50, look: look)
        #expect(renderer.currentLook.leafRipe)
        #expect(renderer.actorPresent)
        #expect(renderer.currentHint == AppLocalization.text("暂时没有收好，请再试一次"))
        renderer.leafPan(-120, ripe: true)
        #expect(attempts == 2)
    }

    @Test func collectionReceiptKeepsPiboVisibleAtTheReleasePosition() {
        final class WalkingBrain: PixelDayBrain {
            func next(previous: PiboDayActivity) -> PixelDayPlan? {
                let plan = PixelDayPlan()
                plan.place = .mossNest
                return plan
            }
            func slow() -> Bool { false }
        }
        let brain = WalkingBrain()
        let renderer = PixelStageRenderer()
        renderer.brain = brain
        var look = PixelStageRenderer.Look()
        look.leafRipe = true
        let now = Date().timeIntervalSince1970 * 1000
        _ = renderer.render(size: size, scale: 3, now: now, look: look)
        let x = renderer.actor.x, y = renderer.actor.y
        renderer.onCollectBo = { true }
        renderer.leafPan(-120, ripe: true)
        renderer.leafPanEnd()
        look.leafRipe = false
        look.leafGrowth = 0
        for frame in 1...20 {
            _ = renderer.render(size: size, scale: 3, now: now + Double(frame * 50), look: look)
            #expect(renderer.actor.x == x && renderer.actor.y == y,
                    "Pibo must not walk away while the collection receipt is above its head")
            #expect(renderer.actorPresent)
        }
        #expect(!renderer.currentHint.isEmpty)
    }
}

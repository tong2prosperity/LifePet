import Foundation
import PiboCore
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct HomeDayLifecycleTests {
    private final class Fixture {
        let key = "HomeDayLifecycleTests.\(UUID())"
        let defaults: UserDefaults
        let growth: GrowthStore
        let days: PiboDayStore
        let director = PixelDayDirector()
        let home: HomeDayController
        var active = true
        init() {
            defaults = UserDefaults(suiteName: key)!
            growth = GrowthStore(defaults: defaults)
            days = PiboDayStore(defaults: defaults)
            home = HomeDayController(director: director)
            home.bind(.init(stateID: { "pibo-state-data-unknown" }, hour: { 12 }, weather: { .clear },
                            ownedDecor: { [] }, hammock: { false }, observer: { false },
                            growth: { self.growth }, days: { self.days }, dayCount: { 1 },
                            stepsToday: { 0 }, hasStepsData: { false }, sleepHours: { 0 },
                            mindfulMinutes: { 0 }, lastWorkout: { nil }, overlays: { .init() },
                            appActive: { self.active }, voiceBusy: { false }, decorLine: { _ in },
                            speak: { _ in }, boCollected: { 0 }, bodyBands: { [-1, -1] },
                            claimStoryLine: { false }, setStoryWaiting: { _ in }, lastMealAt: { -1 },
                            mealsToday: { [] }, openMeal: { _, _ in }))
            director.configure(pixelForestLayout(134, 291), .clearing)
        }
        func cleanup() { home.stop(); defaults.removePersistentDomain(forName: key) }
    }

    @Test func returnResumesTheScriptInsteadOfReplacingItsCompletionWithAGreeting() {
        let f = Fixture()
        defer { f.cleanup() }
        var completions = 0
        #expect(f.director.perform([pixelStoryAct(.beckon, 150), pixelStoryCall { completions += 1 }]))
        let now = Date().timeIntervalSince1970 * 1000
        _ = f.director.step(now, hold: false)
        f.home.start()
        f.home.stop()
        f.home.start()
        #expect(f.director.performing)
        for step in 1...8 { _ = f.director.step(now + Double(step) * 50, hold: false) }
        #expect(completions == 1)
    }

    @Test func startingOrStoppingAnInactiveForestDoesNotRewriteLastSeen() {
        let f = Fixture()
        defer { f.cleanup() }
        let seen = Date().timeIntervalSince1970 * 1000 - 3_600_000
        f.days.noteSeen(seen, flush: true)
        let before = f.defaults.string(forKey: PiboDayStore.defaultsKey)
        f.active = false
        f.home.start()
        f.home.stop()
        #expect(f.defaults.string(forKey: PiboDayStore.defaultsKey) == before)
        #expect(f.days.awayMinutes(seen + 3_600_000) == 60)
    }
}

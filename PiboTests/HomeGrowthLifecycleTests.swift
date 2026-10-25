import Foundation
import Testing
import PiboCore
@testable import Pibo

@Suite(.serialized)
@MainActor
struct HomeGrowthLifecycleTests {
    @Test func missingActivityStaysUnknownWhileMeasuredZeroRemainsReal() {
        let record = HealthDayRecord(date: .now, sleepTotal: 3600)
        let absent = GrowthActivityFacts(record: record, reliable: true)
        #expect(absent.steps == nil)
        #expect(absent.activeMinutes == nil)
        let cues = PiboCoreGrowth.bodyCues(
            sleepHours: 1, baselineSleepHours: nil, steps: absent.steps,
            baselineSteps: nil, activeMinutes: absent.activeMinutes, secondsSinceWorkout: nil)
        #expect(cues.stepsBand == -1)
        #expect(cues.activityBand == -1)
        record.stepsRecorded = true
        record.exerciseRecorded = true
        let zero = GrowthActivityFacts(record: record, reliable: true)
        #expect(zero.steps == 0)
        #expect(zero.activeMinutes == 0)
        record.stepsRecorded = nil
        record.exerciseRecorded = nil
        record.steps = 120
        record.exerciseMinutes = 18
        #expect(GrowthActivityFacts(record: record, reliable: true).activeMinutes == 18)
        #expect(GrowthActivityFacts(record: record, reliable: true).steps == 120)
        #expect(GrowthActivityFacts(record: record, reliable: false).steps == nil)
    }

    private final class Fixture {
        let defaults: UserDefaults
        let key = "HomeGrowthLifecycleTests.\(UUID())"
        let growth: GrowthStore
        var home = HomeGrowthController()
        var active = true
        var overlay = false
        var companion = false
        let speech = HomeSpeechPresentationController()
        let coordinator = GrowthCoordinator()
        let decor: DecorStore
        let ledger: BoLedgerStore
        let polaroids: PolaroidStore
        let now = Date()

        init() {
            defaults = UserDefaults(suiteName: key)!
            growth = GrowthStore(defaults: defaults)
            decor = DecorStore(defaults: defaults)
            ledger = BoLedgerStore(defaults: defaults)
            polaroids = PolaroidStore(defaults: defaults)
            bind()
            growth.push(GrowthFeedbackEvent(kind: .level, level: 2))
        }

        func bind() {
            home.bind(.init(growth: { self.growth }, coordinator: { self.coordinator },
                            decor: { self.decor }, ledger: { self.ledger }, speech: { self.speech },
                            companionBusy: { self.companion }, dayCount: { 1 },
                            polaroids: { self.polaroids }, appActive: { self.active },
                            overlayOpen: { self.overlay || self.home.levelUpVisible },
                            awayDiary: { nil }, lastWorkoutEndedAt: { nil }, lastWorkoutKind: { nil }))
        }

        func cleanup() { home.stop(); defaults.removePersistentDomain(forName: key) }
    }

    @Test(arguments: [0, 1, 2])
    func delayedLevelWaitsForForegroundAndAFreeForest(boundary: Int) throws {
        let f = Fixture()
        defer { f.cleanup() }
        f.home.tick(now: f.now)
        let id = try #require(f.growth.peek()?.id)
        f.active = boundary != 0
        f.overlay = boundary == 1
        f.companion = boundary == 2
        f.home.tick(now: f.now.addingTimeInterval(2))
        #expect(!f.home.levelUpVisible)
        #expect(f.growth.peek()?.id == id)
        f.active = true; f.overlay = false; f.companion = false
        f.home.tick(now: f.now.addingTimeInterval(3))
        #expect(f.home.levelUpVisible)
        #expect(f.home.levelUpLevel == 2)
        #expect(f.growth.peek() == nil)
        f.home.closeLevelUp()
        f.home.tick(now: f.now.addingTimeInterval(4))
        #expect(!f.home.levelUpVisible, "the reveal is consumed only once")
    }

    @Test func restartingTheStoppedHomeTimerResumesItsPendingCard() async throws {
        let f = Fixture()
        defer { f.cleanup() }
        f.home.tick(now: f.now)
        f.home.stop()
        f.home.start()
        try await Task.sleep(for: .milliseconds(2500))
        #expect(f.home.levelUpVisible)
        #expect(f.growth.peek() == nil)
    }

    @Test func stoppingOrRecreatingHomeCannotLoseAnUnseenLevel() throws {
        let f = Fixture()
        defer { f.cleanup() }
        f.home.tick(now: f.now)
        f.home.stop()
        let restored = GrowthStore(defaults: f.defaults)
        #expect(restored.peek()?.kind == .level, "waiting cards remain in persistent feedback")
        f.home = HomeGrowthController()
        f.bind()
        f.home.tick(now: f.now.addingTimeInterval(3))
        f.home.tick(now: f.now.addingTimeInterval(5))
        #expect(f.home.levelUpVisible)
        #expect(f.growth.peek() == nil)
    }
}

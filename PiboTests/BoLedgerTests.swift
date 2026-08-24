import Foundation
import PiboCore
import SwiftData
import Testing
@testable import Pibo

/// App-owned ledger guarantees around Core scoring: consent boundary,
/// idempotency, pending queues, lifetime floors and persistence.
@Suite(.serialized)
@MainActor
struct BoLedgerTests {
    private func makeLedger(
        startedOn: Date,
        hasConsent: Bool = true,
        acceptedAt: Date? = nil,
        feedback: BoProgressFeedbackStore? = nil
    ) throws -> (BoLedgerStore, UserDefaults, String) {
        let suite = "BoLedgerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let consentDate = hasConsent
            ? (acceptedAt ?? day(-1, from: startedOn))
            : nil
        let store = BoLedgerStore(
            defaults: defaults,
            persistenceKey: "test.ledger",
            startedOn: startedOn,
            acceptedAt: consentDate,
            progressFeedback: feedback
        )
        return (store, defaults, suite)
    }

    private func goodDay(steps: Int = 12_000, sleepHours: Double = 8) -> PiboCoreBoDailyMetrics {
        PiboCoreBoAdapter.metrics(
            sleepTotal: sleepHours * 3_600,
            sleepDeep: 1.5 * 3_600,
            sleepREM: 1.6 * 3_600,
            awakeSeconds: 20 * 60,
            awakeSegmentCount: 2,
            steps: steps,
            exerciseMinutes: 45,
            hrv: 42,
            restingHR: 58
        )
    }

    private func modestDay() -> PiboCoreBoDailyMetrics {
        PiboCoreBoAdapter.metrics(
            sleepTotal: 5.5 * 3_600,
            sleepDeep: 0.6 * 3_600,
            sleepREM: 0.7 * 3_600,
            awakeSeconds: 35 * 60,
            awakeSegmentCount: 4,
            steps: 3_000,
            exerciseMinutes: 0,
            hrv: 0,
            restingHR: 0
        )
    }

    private func day(_ offsetDays: Int, from anchor: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: offsetDays, to: anchor) ?? anchor
    }

    @Test func growthStageComesFromCoreLedgerState() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let (ledger, defaults, suite) = try makeLedger(startedOn: today)
        defer { defaults.removePersistentDomain(forName: suite) }

        ledger.debugSet(ripe: 0, progress: 0)
        #expect(ledger.growthStage == .dormant)
        ledger.debugSet(ripe: 0, progress: 0.25)
        #expect(ledger.growthStage == .sprouting)
        ledger.debugSet(ripe: 0, progress: 0.5)
        #expect(ledger.growthStage == .forming)
        ledger.debugSet(ripe: 1, progress: 0)
        #expect(ledger.growthStage == .ripe)
    }

    @Test func noConsentPreservesAssetsButMintsNothing() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let (ledger, defaults, suite) = try makeLedger(startedOn: today, hasConsent: false)
        defer { defaults.removePersistentDomain(forName: suite) }

        ledger.debugSet(balance: 3, ripe: 2)
        let before = ledger.state
        ledger.recompute(days: [(day: today, metrics: goodDay())])

        #expect(ledger.state == before)
        #expect(ledger.balance == 3)
        #expect(ledger.state.ripeCount == 2)
    }

    @Test func recomputingTheSameDayTwiceGrantsOnce() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let (ledger, defaults, suite) = try makeLedger(startedOn: today)
        defer { defaults.removePersistentDomain(forName: suite) }

        ledger.recompute(days: [(day: today, metrics: modestDay())])
        let after = ledger.state
        ledger.recompute(days: [(day: today, metrics: modestDay())])

        #expect(ledger.state == after)
    }

    @Test func aDayThatGrowsLaterGrantsOnlyTheDifference() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let (ledger, defaults, suite) = try makeLedger(startedOn: today)
        defer { defaults.removePersistentDomain(forName: suite) }

        let partialMetrics = goodDay(steps: 3_000, sleepHours: 5)
        let fullMetrics = goodDay(steps: 14_000, sleepHours: 5)
        ledger.recompute(days: [(day: today, metrics: partialMetrics)])
        let firstResult = PiboCoreBoEconomy.applyEnergy(
            energyPool: 0,
            grantedEnergy: PiboCoreBoEconomy.scoreDay(partialMetrics).energy
        )
        #expect(abs(ledger.state.energyPool - firstResult.newEnergyPool) < 0.001)

        ledger.recompute(days: [(day: today, metrics: fullMetrics)])
        let fullResult = PiboCoreBoEconomy.applyEnergy(
            energyPool: 0,
            grantedEnergy: PiboCoreBoEconomy.scoreDay(fullMetrics).energy
        )
        #expect(abs(ledger.state.energyPool - fullResult.newEnergyPool) < 0.001)
        #expect(ledger.state.ripeCount == fullResult.mintedCount)
    }

    @Test func matureBoDoesNotFreezeLaterAccumulation() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let (ledger, defaults, suite) = try makeLedger(startedOn: today)
        defer { defaults.removePersistentDomain(forName: suite) }
        let tomorrow = day(1, from: today)
        let dailyEnergy = PiboCoreBoEconomy.scoreDay(goodDay()).energy

        ledger.recompute(
            days: [(day: today, metrics: goodDay()), (day: tomorrow, metrics: goodDay())],
            now: day(2, from: today)
        )
        let expected = PiboCoreBoEconomy.applyEnergy(
            energyPool: 0,
            grantedEnergy: dailyEnergy * 2
        )

        #expect(ledger.state.ripeCount == expected.mintedCount)
        #expect(ledger.state.ripeCount >= 2)
        #expect(abs(ledger.state.energyPool - expected.newEnergyPool) < 0.001)
        #expect(ledger.state.lifetimeMinted == ledger.state.ripeCount)
        #expect(ledger.state.grantedEnergyByDay.count == 2)
    }

    @Test func collectionEventIsIdempotentAndDrainsOnePendingItem() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let (ledger, defaults, suite) = try makeLedger(startedOn: today)
        defer { defaults.removePersistentDomain(forName: suite) }
        ledger.debugSet(ripe: 2)

        #expect(ledger.pluck(eventID: "collection-01", at: today))
        let afterFirst = ledger.state
        #expect(!ledger.pluck(eventID: "collection-01", at: today))
        #expect(ledger.state == afterFirst)
        #expect(ledger.state.ripeCount == 1)
        #expect(ledger.balance == 1)
        #expect(ledger.lifetimeCollected == 1)
        #expect(ledger.state.firstBoCollectedAt == today)
    }

    @Test func onlyWholeDaysAfterConsentAreEligible() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let acceptedAt = today.addingTimeInterval(12 * 3_600)
        let (ledger, defaults, suite) = try makeLedger(
            startedOn: today,
            acceptedAt: acceptedAt
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        let tomorrow = day(1, from: today)

        ledger.recompute(
            days: [(day: today, metrics: goodDay()), (day: tomorrow, metrics: modestDay())],
            now: day(2, from: today)
        )

        #expect(ledger.state.grantedEnergyByDay[BoLedgerStore.dayKey(today)] == nil)
        #expect(ledger.state.grantedEnergyByDay[BoLedgerStore.dayKey(tomorrow)] != nil)
    }

    @Test func acceptingAfterLedgerCreationEnablesFutureAccumulation() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let (ledger, defaults, suite) = try makeLedger(startedOn: today, hasConsent: false)
        defer { defaults.removePersistentDomain(forName: suite) }

        ledger.setAcceptedAtIfNeeded(day(-1, from: today))
        ledger.recompute(days: [(day: today, metrics: modestDay())])

        #expect(ledger.state.acceptedAt != nil)
        #expect(ledger.state.energyPool > 0 || ledger.hasRipeBo)
    }

    @Test func changingEligibilitySourceReplacesBoundaryWithoutRemovingAssets() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let suite = "BoLedgerEligibilitySource.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cooperationAt = day(-4, from: today)
        let legacyCompletedAt = day(-2, from: today)
        let original = BoLedgerStore(
            defaults: defaults,
            persistenceKey: "test.ledger",
            acceptedAt: cooperationAt,
            eligibilitySource: .temporaryCooperation
        )
        original.debugSet(balance: 3, ripe: 2, progress: 0.4)

        let migrated = BoLedgerStore(
            defaults: defaults,
            persistenceKey: "test.ledger",
            acceptedAt: legacyCompletedAt,
            eligibilitySource: .legacyOnboarding
        )

        #expect(migrated.state.acceptedAt == legacyCompletedAt)
        #expect(migrated.state.eligibilitySource == .legacyOnboarding)
        #expect(migrated.balance == 3)
        #expect(migrated.state.ripeCount == 2)
        #expect(migrated.growthProgress > 0)
    }

    @Test func syntheticHistoryNeverAdvancesTheLedger() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let acceptedAt = day(-2, from: today)
        let suite = "BoLedgerProvenance.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(
            for: HealthDayRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let history = HealthHistoryStore(
            context: container.mainContext,
            provenanceDefaults: defaults,
            syntheticDaysKey: "test.synthetic-days"
        )
        history.upsert(day: today, origin: .synthetic) { record in
            record.steps = 14_000
            record.sleepTotal = 8 * 3_600
            record.sleepDeep = 1.5 * 3_600
            record.sleepREM = 1.6 * 3_600
            record.exerciseMinutes = 45
        }
        let ledger = BoLedgerStore(
            defaults: defaults,
            persistenceKey: "test.ledger",
            acceptedAt: acceptedAt
        )

        ledger.recompute(history: history, now: today.addingTimeInterval(12 * 3_600))
        #expect(ledger.state.energyPool == 0)
        #expect(ledger.lifetimeMinted == 0)

        // Core 0.7.1 has no stand input yet. A stand/goal-only row must not
        // accidentally receive its non-zero zero-MVPA floor.
        history.ingest([HealthDayValues(
            date: today,
            standMinutes: 90,
            moveGoal: 500,
            standGoal: 12
        )])
        ledger.recompute(history: history, now: today.addingTimeInterval(12 * 3_600))
        #expect(ledger.state.energyPool == 0)

        history.ingest([HealthDayValues(
            date: today,
            steps: 14_000,
            exerciseMinutes: 45,
            sleepTotal: 8 * 3_600,
            sleepDeep: 1.5 * 3_600,
            sleepREM: 1.6 * 3_600
        )])
        ledger.recompute(history: history, now: today.addingTimeInterval(12 * 3_600))
        #expect(ledger.state.energyPool > 0 || ledger.hasRipeBo)
    }

    @Test func spendingChangesInventoryButNeverLifetimeHistory() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let (ledger, defaults, suite) = try makeLedger(startedOn: today)
        defer { defaults.removePersistentDomain(forName: suite) }
        ledger.debugSet(balance: 3)
        let lifetime = ledger.lifetimeCollected

        #expect(!ledger.spend(8))
        #expect(ledger.balance == 3)
        #expect(ledger.spend(3))
        #expect(ledger.balance == 0)
        #expect(ledger.state.spentTotal == 3)
        #expect(ledger.lifetimeCollected == lifetime)
    }

    @Test func investmentUsesRipeBoWithoutAPluckInventoryStep() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let (ledger, defaults, suite) = try makeLedger(startedOn: today)
        defer { defaults.removePersistentDomain(forName: suite) }
        ledger.debugSet(balance: 1, ripe: 2)

        #expect(ledger.availableBo == 3)
        #expect(ledger.spend(2))
        #expect(ledger.state.ripeCount == 0)
        #expect(ledger.balance == 1)
        #expect(ledger.availableBo == 1)
        #expect(ledger.state.spentTotal == 2)
    }

    @Test func walkDoodleBonusEnergyIsIdempotentAndUsesTheSharedPool() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let feedbackSuite = "BoLedgerBonusFeedback.\(UUID().uuidString)"
        let feedbackDefaults = try #require(UserDefaults(suiteName: feedbackSuite))
        defer { feedbackDefaults.removePersistentDomain(forName: feedbackSuite) }
        let feedback = BoProgressFeedbackStore(defaults: feedbackDefaults)
        let (ledger, defaults, suite) = try makeLedger(
            startedOn: today,
            feedback: feedback
        )
        defer { defaults.removePersistentDomain(forName: suite) }

        let eventID = "walk-doodle:1:20000:12000"
        #expect(ledger.grantBonusEnergy(eventID: eventID, grantedEnergy: 12))
        let afterFirst = ledger.state
        #expect(ledger.hasProcessedBonusEnergy(eventID: eventID))
        #expect(feedback.pending != nil)
        #expect(!ledger.grantBonusEnergy(eventID: eventID, grantedEnergy: 12))
        #expect(ledger.state == afterFirst)
    }

    @Test func legacySnapshotPreservesAssetsAndBuildsLifetimeFloors() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let suite = "BoLedgerLegacy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = BoLedgerSnapshot(
            startedOn: today,
            scoringVersion: PiboCoreBoEconomy.scoringVersion
        )
        legacy.ripeCount = 2
        legacy.balance = 3
        legacy.spentTotal = 4
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any]
        )
        object.removeValue(forKey: "lifetimeMinted")
        object.removeValue(forKey: "lifetimeCollected")
        object.removeValue(forKey: "acceptedAt")
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: "test.ledger")

        let acceptedAt = day(-1, from: today)
        let restored = BoLedgerStore(
            defaults: defaults,
            persistenceKey: "test.ledger",
            acceptedAt: acceptedAt
        )

        #expect(restored.state.ripeCount == 2)
        #expect(restored.balance == 3)
        #expect(restored.state.spentTotal == 4)
        #expect(restored.lifetimeCollected == 7)
        #expect(restored.lifetimeMinted == 9)
        #expect(restored.state.acceptedAt == acceptedAt)
    }

    @Test func restoredSnapshotPreservesLedgerInvariants() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let suite = "BoLedgerInvariant.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var snapshot = BoLedgerSnapshot(
            startedOn: today,
            acceptedAt: day(-1, from: today),
            scoringVersion: PiboCoreBoEconomy.scoringVersion
        )
        snapshot.energyPool = -40
        snapshot.ripeCount = 2
        snapshot.balance = 1
        snapshot.lifetimeCollected = 8
        snapshot.lifetimeMinted = 3
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "test.ledger")

        let restored = BoLedgerStore(defaults: defaults, persistenceKey: "test.ledger")

        #expect(restored.state.energyPool == 0)
        #expect(restored.lifetimeCollected == 8)
        #expect(restored.lifetimeMinted == 10)
    }

    @Test func restoreFiltersInvalidBookmarksAndRecoversOversizedPool() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let suite = "BoLedgerDamaged.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var snapshot = BoLedgerSnapshot(
            startedOn: today,
            acceptedAt: day(-1, from: today),
            scoringVersion: PiboCoreBoEconomy.scoringVersion
        )
        let perBo = PiboCoreBoEconomy.energyPerBo
        snapshot.energyPool = perBo * 2.4
        snapshot.grantedEnergyByDay = [
            "negative": -10,
            "valid": 12
        ]
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "test.ledger")

        let restored = BoLedgerStore(defaults: defaults, persistenceKey: "test.ledger")
        #expect(restored.state.ripeCount == 2)
        #expect(restored.state.energyPool >= 0)
        #expect(restored.state.energyPool < perBo)
        #expect(restored.state.grantedEnergyByDay == ["valid": 12])
    }

    @Test func stateSurvivesRelaunch() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let (ledger, defaults, suite) = try makeLedger(startedOn: today)
        defer { defaults.removePersistentDomain(forName: suite) }
        ledger.debugSet(balance: 5, ripe: 2, progress: 0.4)
        let before = ledger.state

        let restored = BoLedgerStore(defaults: defaults, persistenceKey: "test.ledger")
        #expect(restored.state == before)
    }

    @Test func legacyCalendarDayBookmarkMigratesAcrossTimeZonesWithoutDoubleGranting() throws {
        var originalCalendar = Calendar(identifier: .gregorian)
        originalCalendar.timeZone = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        let today = try #require(originalCalendar.date(
            from: DateComponents(year: 2026, month: 8, day: 4)
        ))
        let acceptedAt = day(-2, from: today)
        let suite = "BoLedgerDayKeyMigration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let metrics = modestDay()
        let granted = PiboCoreBoEconomy.scoreDay(metrics).energy
        var snapshot = BoLedgerSnapshot(
            startedOn: Calendar.current.startOfDay(for: acceptedAt),
            acceptedAt: acceptedAt,
            scoringVersion: PiboCoreBoEconomy.scoringVersion
        )
        snapshot.energyPool = granted
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = originalCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let legacyKey = formatter.string(from: today)
        #expect(legacyKey != formatterWithCurrentTimeZone().string(from: today))
        snapshot.grantedEnergyByDay[legacyKey] = granted
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "test.ledger")

        let ledger = BoLedgerStore(defaults: defaults, persistenceKey: "test.ledger")
        ledger.recompute(days: [(day: today, metrics: metrics)], now: today)

        #expect(abs(ledger.state.energyPool - granted) < 0.001)
        #expect(ledger.state.grantedEnergyByDay[legacyKey] == nil)
        #expect(ledger.state.grantedEnergyByDay[BoLedgerStore.dayKey(today)] == granted)
        #expect(ledger.state.firstEligibleAt == snapshot.firstEligibleAt)
    }

    private func formatterWithCurrentTimeZone() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    @Test func recomputeFeedsProgressFeedback() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let feedbackSuite = "BoLedgerFeedback.\(UUID().uuidString)"
        let feedbackDefaults = try #require(UserDefaults(suiteName: feedbackSuite))
        defer { feedbackDefaults.removePersistentDomain(forName: feedbackSuite) }
        let feedback = BoProgressFeedbackStore(defaults: feedbackDefaults)
        let (ledger, defaults, suite) = try makeLedger(startedOn: today, feedback: feedback)
        defer { defaults.removePersistentDomain(forName: suite) }

        ledger.recompute(days: [(day: today, metrics: modestDay())])
        #expect(feedback.pending != nil || ledger.hasRipeBo)
    }

    #if DEBUG
    @Test func debugWorkoutUsesCoreCarryAndMinting() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let (ledger, defaults, suite) = try makeLedger(startedOn: today)
        defer { defaults.removePersistentDomain(forName: suite) }
        let metrics = PiboCoreBoAdapter.metrics(
            sleepTotal: 0,
            sleepDeep: 0,
            sleepREM: 0,
            awakeSeconds: 0,
            awakeSegmentCount: nil,
            steps: 0,
            exerciseMinutes: 24,
            hrv: 0,
            restingHR: 0
        )
        let expected = PiboCoreBoEconomy.applyEnergy(
            energyPool: 0,
            grantedEnergy: PiboCoreBoEconomy.scoreDay(metrics).energy
        )

        ledger.debugApplyWorkout(durationMinutes: 24)
        #expect(abs(ledger.state.energyPool - expected.newEnergyPool) < 0.001)
        #expect(ledger.state.ripeCount == expected.mintedCount)
    }
    #endif
}

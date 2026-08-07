import Foundation
import PiboCore
import SwiftData
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct OnboardingStateStoreTests {
    private func makeStore() throws -> (OnboardingStateStore, UserDefaults, String) {
        let suite = "OnboardingStateStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = OnboardingStateStore(defaults: defaults, persistenceKey: "test.onboarding")
        store.configureTemporaryCooperation(
            enabled: true,
            boLifetimeMinted: 0,
            boLifetimeCollected: 0
        )
        return (
            store,
            defaults,
            suite
        )
    }

    @Test func checkpointAndCompactPathSurviveRelaunch() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.begin(at: .encounter)
        store.skipStory()
        #expect(store.snapshot.checkpoint == .healthSetup)
        #expect(store.snapshot.usesCompactSetup)
        #expect(store.snapshot.compactIntroductionCompleted == false)

        let restored = OnboardingStateStore(
            defaults: defaults,
            persistenceKey: "test.onboarding"
        )
        #expect(restored.snapshot.firstRunStatus == .inProgress)
        #expect(restored.snapshot.checkpoint == .healthSetup)
        #expect(restored.snapshot.compactIntroductionCompleted == false)

        restored.completeCompactIntroduction()
        let restoredAgain = OnboardingStateStore(
            defaults: defaults,
            persistenceKey: "test.onboarding"
        )
        #expect(restoredAgain.snapshot.compactIntroductionCompleted == true)
    }

    @Test func storyRecoveryNeverReopensCompletedFirstRun() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.completeFirstRun()
        #expect(store.storyRecoveryCheckpoint == .encounter)
        store.respond()
        store.move(to: .identity)

        #expect(store.snapshot.firstRunStatus == .completed)
        #expect(!store.shouldPresentFirstRun)
        #expect(store.needsStoryRecovery)
        #expect(store.storyRecoveryCheckpoint == .identity)

        store.move(to: .partnership)
        #expect(store.storyRecoveryCheckpoint == .partnership)
    }

    @Test func compactSetupDoesNotOverwriteDeferredStoryCheckpoint() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.begin(at: .encounter)
        store.respond()
        store.move(to: .identity)
        store.skipStory()
        store.completeFirstRun()

        #expect(store.snapshot.checkpoint == .finishing)
        #expect(store.snapshot.storyCheckpoint == .identity)
        #expect(store.storyRecoveryCheckpoint == .identity)

        let restored = OnboardingStateStore(
            defaults: defaults,
            persistenceKey: "test.onboarding"
        )
        #expect(restored.storyRecoveryCheckpoint == .identity)
    }

    @Test func storyConsentIsIndependentFromPlatformRequests() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let acceptedAt = Date(timeIntervalSince1970: 1_800_000_000)

        store.respond(at: acceptedAt.addingTimeInterval(-1))
        let returned = store.acceptTemporaryCooperation(at: acceptedAt)

        #expect(returned == acceptedAt)
        #expect(store.acceptedAt == acceptedAt)
        #expect(store.snapshot.consentVersion == OnboardingNarrativeSnapshot.currentConsentVersion)
        #expect(store.snapshot.healthRequestCompletedAt == nil)
        #expect(store.snapshot.notificationRequestCompletedAt == nil)
    }

    @Test func legacyCompletedUserEntersHomeWithStoryUnanswered() throws {
        let suite = "OnboardingLegacy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PiboPersistenceKeys.Defaults.onboardingDone)

        let store = OnboardingStateStore(
            defaults: defaults,
            persistenceKey: "test.onboarding"
        )

        #expect(store.snapshot.firstRunStatus == .completed)
        #expect(store.snapshot.connection == .unresponded)
        #expect(store.completionTimeBasis == .legacyMigrationFallback)
        #expect(!store.shouldPresentFirstRun)
        #expect(store.needsStoryRecovery)
    }

    @Test func pausedStoryIgnoresBoAndResumesFromANewBaseline() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let acceptedAt = Date(timeIntervalSince1970: 1_800_000_000)
        store.respond(at: acceptedAt.addingTimeInterval(-1))
        store.acceptTemporaryCooperation(
            at: acceptedAt,
            boLifetimeMinted: 5,
            boLifetimeCollected: 2
        )
        store.markHealthRequestCompleted(readiness: .init(
            hasSleep: false,
            hasSteps: true,
            hasExercise: false
        ))
        #expect(store.eventProjection().event02 == .completed)

        store.configureTemporaryCooperation(
            enabled: false,
            boLifetimeMinted: 5,
            boLifetimeCollected: 2,
            at: acceptedAt.addingTimeInterval(100)
        )
        store.observeBoProgress(lifetimeMinted: 6, lifetimeCollected: 3)
        #expect(store.eventProjection().event03 == .locked)

        store.configureTemporaryCooperation(
            enabled: true,
            boLifetimeMinted: 6,
            boLifetimeCollected: 3,
            at: acceptedAt.addingTimeInterval(200)
        )
        store.observeBoProgress(lifetimeMinted: 6, lifetimeCollected: 3)
        #expect(store.eventProjection().event03 == .locked)

        store.observeBoProgress(lifetimeMinted: 7, lifetimeCollected: 3)
        #expect(store.eventProjection().event03 == .available)
        store.observeBoProgress(lifetimeMinted: 7, lifetimeCollected: 4)
        #expect(store.eventProjection().event03 == .completed)
    }

    @Test func healthObservedBeforeAcceptanceCannotCompleteEvent02() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.markHealthRequestCompleted(readiness: .init(
            hasSleep: true,
            hasSteps: true,
            hasExercise: true
        ))
        #expect(!store.hasObservedHealthSource)
        store.respond()
        store.acceptTemporaryCooperation()
        #expect(store.eventProjection().event02 != .completed)
    }

    @Test func legacyOnboardingCompletionCanStartBoEligibility() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)

        store.completeFirstRun(at: completedAt)
        let ledger = BoLedgerStore(
            defaults: defaults,
            persistenceKey: "test.legacy-onboarding-ledger",
            acceptedAt: store.snapshot.completedAt
        )

        #expect(!PiboReleaseScope.temporaryCooperationOnboarding)
        #expect(ledger.state.acceptedAt == completedAt)
        #expect(ledger.state.firstEligibleAt == Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: completedAt)
        ))
    }

    @Test func unsupportedOrMismatchedConsentSnapshotFailsClosed() throws {
        let suite = "OnboardingMalformed.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var snapshot = OnboardingNarrativeSnapshot(
            flowVersion: OnboardingNarrativeSnapshot.currentFlowVersion + 1,
            firstRunStatus: .completed,
            checkpoint: .finishing,
            completedAt: .now,
            connection: .accepted,
            respondedAt: .now,
            acceptedAt: .now,
            consentVersion: OnboardingNarrativeSnapshot.currentConsentVersion
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "test.onboarding")

        var restored = OnboardingStateStore(
            defaults: defaults,
            persistenceKey: "test.onboarding"
        )
        #expect(restored.snapshot.firstRunStatus == .completed)
        #expect(restored.snapshot.connection == .unresponded)
        #expect(restored.acceptedAt == nil)

        snapshot.flowVersion = OnboardingNarrativeSnapshot.currentFlowVersion
        snapshot.consentVersion = "obsolete-consent"
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "test.onboarding")
        restored = OnboardingStateStore(defaults: defaults, persistenceKey: "test.onboarding")
        #expect(restored.snapshot.connection == .responded)
        #expect(restored.acceptedAt == nil)
    }

    @Test func coreProjectionAdvancesOnlyFromDurableFacts() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var projection = store.eventProjection()
        #expect(projection.event01 == .available)
        #expect(projection.event02 == .locked)
        #expect(projection.event03 == .locked)

        store.respond()
        projection = store.eventProjection()
        #expect(projection.event01 == .completed)
        #expect(projection.speechStage == .event01Completed)

        store.acceptTemporaryCooperation()
        store.observeBoProgress(lifetimeMinted: 1, lifetimeCollected: 0)
        projection = store.eventProjection()
        #expect(projection.event02 != .completed)
        #expect(projection.event03 == .locked)
    }

    @Test func onlyVerifiedHealthHistoryAdvancesEvent02() throws {
        let (store, defaults, suite) = try makeStore()
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
        let today = Calendar.current.startOfDay(for: .now)
        store.respond()
        store.acceptTemporaryCooperation()

        history.upsert(day: today, origin: .synthetic) { $0.steps = 12_000 }
        store.observeHealth(in: history)
        #expect(!store.hasObservedHealthSource)

        history.ingest([HealthDayValues(date: today, standMinutes: 90)])
        store.observeHealth(in: history)
        #expect(store.snapshot.observedHealthSources == [.stand])
        #expect(store.eventProjection().event02 == .completed)
    }

    @Test func syntheticWorkoutsStayIsolatedUntilRealBackfillReplacesThem() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(
            for: HealthDayRecord.self, WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let history = HealthHistoryStore(
            context: container.mainContext,
            provenanceDefaults: defaults,
            syntheticDaysKey: "test.synthetic-days",
            syntheticWorkoutIDsKey: "test.synthetic-workouts"
        )
        let today = Calendar.current.startOfDay(for: .now)
        let start = today.addingTimeInterval(8 * 3_600)
        let syntheticID = UUID()
        store.respond()
        store.acceptTemporaryCooperation()

        history.ingestWorkouts([
            WorkoutValues(
                id: syntheticID,
                kind: .walk,
                start: start,
                end: start.addingTimeInterval(1_800),
                duration: 1_800,
                energyKcal: 120,
                distanceMeters: 2_000
            )
        ], origin: .synthetic)
        store.observeHealth(in: history)
        #expect(!store.hasObservedHealthSource)
        #expect(history.verifiedHealthRecords(from: today, to: today).isEmpty)

        let realID = UUID()
        history.ingestWorkouts([
            WorkoutValues(
                id: realID,
                kind: .run,
                start: start,
                end: start.addingTimeInterval(2_400),
                duration: 2_400,
                energyKcal: 280,
                distanceMeters: 5_000
            )
        ])
        store.observeHealth(in: history)

        #expect(history.workouts(on: today).map(\.id) == [realID])
        #expect(store.snapshot.observedHealthSources == [.workout])
    }
}

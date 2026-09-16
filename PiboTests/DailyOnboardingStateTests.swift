import Foundation
import Testing
@testable import Pibo

@Suite(.serialized)
@MainActor
struct DailyOnboardingStateTests {
    private let key = "test.daily.onboarding"

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "DailyOnboardingStateTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @Test func newUserWalksWelcomeOverviewHealthAndStepSurvivesRelaunch() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingStateStore(defaults: defaults, persistenceKey: key)
        #expect(store.shouldPresentFirstRun)
        #expect(store.dailySetupStep == .welcome)

        store.moveDailySetup(to: .overview)
        #expect(store.snapshot.firstRunStatus == .inProgress)
        #expect(OnboardingStateStore(defaults: defaults, persistenceKey: key).dailySetupStep == .overview)

        store.moveDailySetup(to: .welcome)
        #expect(OnboardingStateStore(defaults: defaults, persistenceKey: key).dailySetupStep == .welcome)

        store.moveDailySetup(to: .overview)
        store.moveDailySetup(to: .health)
        let restored = OnboardingStateStore(defaults: defaults, persistenceKey: key)
        #expect(restored.dailySetupStep == .health)
        #expect(restored.shouldPresentFirstRun)
    }

    @Test func snapshotsWithoutTheFieldResumeByLegacyCheckpoint() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        var atEncounter = OnboardingNarrativeSnapshot()
        atEncounter.firstRunStatus = .inProgress
        defaults.set(try JSONEncoder().encode(atEncounter), forKey: key)
        #expect(OnboardingStateStore(defaults: defaults, persistenceKey: key).dailySetupStep == .welcome)

        var atHealth = OnboardingNarrativeSnapshot()
        atHealth.firstRunStatus = .inProgress
        atHealth.checkpoint = .healthSetup
        defaults.set(try JSONEncoder().encode(atHealth), forKey: key)
        let resumed = OnboardingStateStore(defaults: defaults, persistenceKey: key)
        #expect(resumed.dailySetupStep == .health)
        #expect(resumed.dailyHomeGuide == .none)
    }

    @Test func legacyJSONWithoutDailyKeysStillDecodes() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        // A pre-049 snapshot encoded by an older build (no daily keys at all).
        let legacy = Data(#"""
        {"flowVersion":3,"firstRunStatus":"completed","checkpoint":5,
         "usesCompactSetup":false,"completedAt":700000000,
         "completionTimeBasis":"recorded","connection":"unresponded",
         "observedHealthSources":[]}
        """#.utf8)
        defaults.set(legacy, forKey: key)
        let store = OnboardingStateStore(defaults: defaults, persistenceKey: key)
        #expect(!store.shouldPresentFirstRun)
        #expect(store.dailyHomeGuide == .none)
        #expect(store.snapshot.completedAt == Date(timeIntervalSinceReferenceDate: 700_000_000))
    }

    @Test func completedUsersNeverReplayAndStepMovesAreIgnored() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PiboPersistenceKeys.Defaults.onboardingDone)
        let store = OnboardingStateStore(defaults: defaults, persistenceKey: key)
        #expect(!store.shouldPresentFirstRun)
        store.moveDailySetup(to: .overview)
        #expect(store.snapshot.firstRunStatus == .completed)
        #expect(store.snapshot.dailySetupStep == nil)
        #expect(store.dailyHomeGuide == .none)
    }

    @Test func dailyCompletionIsIdempotentAndWritesNoStoryConsent() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingStateStore(defaults: defaults, persistenceKey: key)
        let first = Date(timeIntervalSince1970: 1_780_000_000)

        #expect(store.completeDailyFirstRun(at: first))
        #expect(!store.shouldPresentFirstRun)
        #expect(store.snapshot.completedAt == first)
        #expect(store.completionTimeBasis == .recorded)
        #expect(store.dailyHomeGuide == .pat)
        #expect(store.snapshot.connection == .unresponded)
        #expect(store.acceptedAt == nil)
        #expect(store.snapshot.consentVersion == nil)

        store.dismissDailyHomeGuide()
        #expect(!store.completeDailyFirstRun(at: first.addingTimeInterval(3_600)))
        #expect(store.snapshot.completedAt == first)
        // A repeated completion must not resurrect the dismissed guide.
        #expect(store.dailyHomeGuide == .none)

        let restored = OnboardingStateStore(defaults: defaults, persistenceKey: key)
        #expect(restored.snapshot.completedAt == first)
        #expect(restored.acceptedAt == nil)
    }

    @Test func homeGuideProgressPersistsSeparately() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingStateStore(defaults: defaults, persistenceKey: key)
        store.completeDailyFirstRun()

        store.acknowledgeDailyPat()
        #expect(OnboardingStateStore(defaults: defaults, persistenceKey: key).dailyHomeGuide == .growth)
        // Acknowledging again (a later pat) does not change anything.
        store.acknowledgeDailyPat()
        #expect(store.dailyHomeGuide == .growth)

        store.dismissDailyHomeGuide()
        let restored = OnboardingStateStore(defaults: defaults, persistenceKey: key)
        #expect(restored.dailyHomeGuide == .none)
        #expect(!restored.shouldPresentFirstRun)
    }

    @Test func skippingThePatGuideEndsTheGuide() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingStateStore(defaults: defaults, persistenceKey: key)
        store.completeDailyFirstRun()
        store.dismissDailyHomeGuide()
        store.acknowledgeDailyPat()
        #expect(store.dailyHomeGuide == .none)
    }

    @Test func unknownRawValuesFallBackInsteadOfFailingDecode() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var snapshot = OnboardingNarrativeSnapshot()
        snapshot.firstRunStatus = .inProgress
        snapshot.checkpoint = .healthSetup
        snapshot.dailySetupStep = "future-step"
        snapshot.dailyHomeGuide = "future-guide"
        defaults.set(try JSONEncoder().encode(snapshot), forKey: key)

        let store = OnboardingStateStore(defaults: defaults, persistenceKey: key)
        #expect(store.snapshot.firstRunStatus == .inProgress)
        #expect(store.snapshot.dailySetupStep == nil)
        #expect(store.dailySetupStep == .health)
        #expect(store.dailyHomeGuide == .none)
    }

    @Test func resetReturnsToWelcome() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingStateStore(defaults: defaults, persistenceKey: key)
        store.moveDailySetup(to: .health)
        store.completeDailyFirstRun()
        store.reset()
        #expect(store.shouldPresentFirstRun)
        #expect(store.dailySetupStep == .welcome)
        #expect(store.dailyHomeGuide == .none)
    }

    @Test func ephemeralPreviewStoreNeverTouchesRealDefaults() throws {
        let realKey = PiboPersistenceKeys.Defaults.onboardingNarrativeState
        let before = UserDefaults.standard.data(forKey: realKey)
        let doneBefore = UserDefaults.standard.object(forKey: PiboPersistenceKeys.Defaults.onboardingDone)

        let preview = OnboardingStateStore.ephemeralPreview()
        #expect(preview.dailySetupStep == .welcome)
        preview.moveDailySetup(to: .overview)
        preview.moveDailySetup(to: .health)
        #expect(preview.dailySetupStep == .health)
        preview.completeDailyFirstRun()
        preview.reset()

        #expect(UserDefaults.standard.data(forKey: realKey) == before)
        #expect(
            (UserDefaults.standard.object(forKey: PiboPersistenceKeys.Defaults.onboardingDone) as? Bool)
                == (doneBefore as? Bool)
        )
    }

    @Test func homeGuideHealthMessageFollowsRealState() {
        #expect(DailyHomeGuideHealthMessage.resolve(hasRealHealthData: true, authState: .denied)
            == DailyOnboardingCopy.dataReady)
        #expect(DailyHomeGuideHealthMessage.resolve(hasRealHealthData: false, authState: .unavailable)
            == DailyOnboardingCopy.dataUnavailable)
        #expect(DailyHomeGuideHealthMessage.resolve(hasRealHealthData: false, authState: .requesting)
            == DailyOnboardingCopy.dataRequesting)
        #expect(DailyHomeGuideHealthMessage.resolve(hasRealHealthData: false, authState: .granted)
            == DailyOnboardingCopy.dataWaiting)
        #expect(DailyHomeGuideHealthMessage.resolve(hasRealHealthData: false, authState: .unknown)
            == DailyOnboardingCopy.dataNotConnected)
    }

    @Test func overviewDoesNotAdvertiseHiddenWalkDoodle() {
        let copy = DailyOnboardingCopy.overviewSections.map(\.body).joined()
            + DailyOnboardingCopy.tools
        #expect(!PiboReleaseScope.walkDoodle)
        #expect(!copy.contains("散步涂鸦"))
    }
}

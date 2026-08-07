import Foundation
import Observation
import PiboCore

enum FirstRunCheckpoint: Int, Codable, CaseIterable, Sendable {
    case encounter
    case identity
    case partnership
    case healthSetup
    case notificationSetup
    case finishing
}

enum FirstRunStatus: String, Codable, Sendable {
    case notStarted
    case inProgress
    case completed
}

enum StoryConnectionStatus: String, Codable, Sendable {
    case unresponded
    case responded
    case accepted
    case ended
}

enum ObservedHealthSource: String, Codable, Hashable, Sendable {
    case sleep
    case steps
    case stand
    case activeEnergy
    case workout
}

enum OnboardingCompletionTimeBasis: String, Codable, Sendable {
    /// Written at the moment this version of the App completes Onboarding.
    case recorded
    /// Older builds persisted only a Boolean, so upgrade time is the earliest
    /// conservative boundary that can be recovered without inventing history.
    case legacyMigrationFallback
}

struct OnboardingNarrativeSnapshot: Codable, Equatable, Sendable {
    static let currentFlowVersion = 3
    static let currentConsentVersion = "temporary-cooperation-v1"

    var flowVersion = currentFlowVersion
    var firstRunStatus: FirstRunStatus = .notStarted
    var checkpoint: FirstRunCheckpoint = .encounter
    /// Story progress is independent from permission/setup progress. Keeping it
    /// separate prevents a deferred identity scene from being overwritten by
    /// the compact path's `.healthSetup` checkpoint.
    var storyCheckpoint: FirstRunCheckpoint?
    var usesCompactSetup = false
    var compactIntroductionCompleted: Bool?
    var completedAt: Date?
    var completionTimeBasis: OnboardingCompletionTimeBasis?

    var connection: StoryConnectionStatus = .unresponded
    var respondedAt: Date?
    var acceptedAt: Date?
    var consentVersion: String?

    var healthRequestCompletedAt: Date?
    var observedHealthSources: Set<ObservedHealthSource> = []
    var notificationRequestCompletedAt: Date?

    /// Runtime release-state checkpoint. It makes disabling the story a real
    /// pause: a later re-enable starts observing new facts from that moment.
    var temporaryCooperationEnabledLastRun: Bool?
    var storyHealthObservationNotBefore: Date?
    var storyBoBaselineMinted: Int?
    var storyBoBaselineCollected: Int?
    var storyFirstBoMinted: Bool?
    var storyFirstBoCollected: Bool?
}

/// One persisted owner for first-run checkpoints, story consent and permission
/// facts. These axes intentionally remain independent: platform authorization
/// never implies that the user accepted Pibo's temporary cooperation.
@MainActor
@Observable
final class OnboardingStateStore {
    private(set) var snapshot: OnboardingNarrativeSnapshot

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistenceKey: String

    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = PiboPersistenceKeys.Defaults.onboardingNarrativeState
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey

        if let data = defaults.data(forKey: persistenceKey),
           let decoded = try? JSONDecoder().decode(OnboardingNarrativeSnapshot.self, from: data) {
            snapshot = Self.normalized(decoded)
            persist()
        } else if defaults.bool(forKey: PiboPersistenceKeys.Defaults.onboardingDone) {
            // Existing users keep entering Home. The retired story never counts
            // as consent to the new temporary cooperation.
            snapshot = OnboardingNarrativeSnapshot(
                firstRunStatus: .completed,
                checkpoint: .finishing,
                completedAt: Date(),
                completionTimeBasis: .legacyMigrationFallback,
                connection: .unresponded
            )
            persist()
        } else {
            snapshot = OnboardingNarrativeSnapshot()
            persist()
        }
    }

    var shouldPresentFirstRun: Bool {
        snapshot.firstRunStatus != .completed
    }

    var acceptedAt: Date? {
        snapshot.connection == .accepted ? snapshot.acceptedAt : nil
    }

    var hasObservedHealthSource: Bool {
        !snapshot.observedHealthSources.isEmpty
    }

    var completionTimeBasis: OnboardingCompletionTimeBasis? {
        snapshot.completionTimeBasis
    }

    /// Records release-scope transitions without deriving story progress from
    /// general health or `bo` history accumulated while the story was paused.
    func configureTemporaryCooperation(
        enabled: Bool,
        boLifetimeMinted: Int,
        boLifetimeCollected: Int,
        at date: Date = .now
    ) {
        let previous = snapshot.temporaryCooperationEnabledLastRun
        if enabled, previous != true {
            snapshot.storyBoBaselineMinted = max(0, boLifetimeMinted)
            snapshot.storyBoBaselineCollected = max(0, boLifetimeCollected)
            if snapshot.connection == .accepted, !event02Completed {
                snapshot.storyHealthObservationNotBefore = Self.firstFullDay(after: date)
            }
        } else if enabled {
            if snapshot.storyBoBaselineMinted == nil {
                snapshot.storyBoBaselineMinted = max(0, boLifetimeMinted)
            }
            if snapshot.storyBoBaselineCollected == nil {
                snapshot.storyBoBaselineCollected = max(0, boLifetimeCollected)
            }
        }
        snapshot.temporaryCooperationEnabledLastRun = enabled
        persist()
    }

    var needsStoryRecovery: Bool {
        snapshot.firstRunStatus == .completed
            && snapshot.connection != .accepted
            && snapshot.connection != .ended
    }

    var recoveryMessageKey: String {
        switch snapshot.connection {
        case .unresponded:
            "onboarding.recovery.unresponded"
        case .responded:
            "onboarding.recovery.responded"
        case .accepted, .ended:
            ""
        }
    }

    var recoveryActionKey: String {
        snapshot.connection == .unresponded
            ? "onboarding.recovery.respond"
            : "onboarding.recovery.continue"
    }

    var storyRecoveryCheckpoint: FirstRunCheckpoint {
        switch snapshot.connection {
        case .unresponded:
            .encounter
        case .responded where snapshot.storyCheckpoint == .identity
            || (snapshot.storyCheckpoint == nil && snapshot.checkpoint == .identity):
            .identity
        case .responded:
            .partnership
        case .accepted, .ended:
            .finishing
        }
    }

    func begin(at checkpoint: FirstRunCheckpoint? = nil) {
        snapshot.firstRunStatus = .inProgress
        if let checkpoint {
            snapshot.checkpoint = checkpoint
            recordStoryCheckpoint(checkpoint)
        }
        persist()
    }

    func move(to checkpoint: FirstRunCheckpoint) {
        if snapshot.firstRunStatus != .completed {
            snapshot.firstRunStatus = .inProgress
        }
        snapshot.checkpoint = checkpoint
        recordStoryCheckpoint(checkpoint)
        persist()
        Analytics.track(
            .onboardingCheckpoint,
            screen: "onboarding",
            ["checkpoint": .string(String(describing: checkpoint))]
        )
    }

    func respond(at date: Date = .now) {
        guard snapshot.connection == .unresponded else { return }
        snapshot.connection = .responded
        snapshot.respondedAt = date
        persist()
        Analytics.track(.storyConnectionResponded, screen: "onboarding")
        Analytics.track(
            .storyEventAdvanced,
            screen: "onboarding",
            ["event": .string("01"), "state": .string("completed")]
        )
    }

    @discardableResult
    func acceptTemporaryCooperation(
        at date: Date = .now,
        boLifetimeMinted: Int? = nil,
        boLifetimeCollected: Int? = nil
    ) -> Date {
        if snapshot.connection == .accepted, let acceptedAt = snapshot.acceptedAt {
            return acceptedAt
        }
        let event02WasCompleted = event02Completed
        if snapshot.respondedAt == nil { snapshot.respondedAt = date }
        snapshot.connection = .accepted
        snapshot.acceptedAt = date
        snapshot.consentVersion = OnboardingNarrativeSnapshot.currentConsentVersion
        snapshot.observedHealthSources.removeAll()
        snapshot.storyHealthObservationNotBefore = date
        snapshot.storyBoBaselineMinted = max(0, boLifetimeMinted ?? snapshot.storyBoBaselineMinted ?? 0)
        snapshot.storyBoBaselineCollected = max(
            0,
            boLifetimeCollected ?? snapshot.storyBoBaselineCollected ?? 0
        )
        snapshot.storyFirstBoMinted = false
        snapshot.storyFirstBoCollected = false
        persist()
        Analytics.track(.storyConnectionAccepted, screen: "onboarding")
        trackEvent02IfNeeded(wasCompleted: event02WasCompleted)
        return date
    }

    func skipStory() {
        snapshot.usesCompactSetup = true
        snapshot.compactIntroductionCompleted = false
        move(to: .healthSetup)
        Analytics.track(.onboardingSkipped, screen: "onboarding")
    }

    func completeCompactIntroduction() {
        snapshot.compactIntroductionCompleted = true
        persist()
    }

    func markHealthRequestCompleted(
        readiness: HealthDataService.OnboardingReadiness,
        at date: Date = .now
    ) {
        let event02WasCompleted = event02Completed
        snapshot.healthRequestCompletedAt = date
        if snapshot.temporaryCooperationEnabledLastRun == true,
           snapshot.connection == .accepted {
            if readiness.hasSleep { snapshot.observedHealthSources.insert(.sleep) }
            if readiness.hasSteps { snapshot.observedHealthSources.insert(.steps) }
            if readiness.hasExercise { snapshot.observedHealthSources.insert(.workout) }
        }
        persist()
        trackEvent02IfNeeded(wasCompleted: event02WasCompleted)
    }

    func observeHealth(in history: HealthHistoryStore, now: Date = .now) {
        guard snapshot.temporaryCooperationEnabledLastRun == true,
              snapshot.connection == .accepted,
              let acceptedAt = snapshot.acceptedAt,
              let rollingStart = Calendar.current.date(byAdding: .day, value: -30, to: now)
        else { return }
        let start = max(
            rollingStart,
            snapshot.storyHealthObservationNotBefore ?? acceptedAt
        )
        var sources = snapshot.observedHealthSources
        let event02WasCompleted = event02Completed
        for record in history.verifiedHealthRecords(from: start, to: now) {
            if record.sleepTotal > 0 { sources.insert(.sleep) }
            if record.steps > 0 { sources.insert(.steps) }
            if record.standMinutes > 0 { sources.insert(.stand) }
            if record.activeEnergy > 0 { sources.insert(.activeEnergy) }
            if record.workoutCount > 0 || record.workoutMinutes > 0 { sources.insert(.workout) }
        }
        guard sources != snapshot.observedHealthSources else { return }
        snapshot.observedHealthSources = sources
        persist()
        trackEvent02IfNeeded(wasCompleted: event02WasCompleted)
    }

    func markNotificationRequestCompleted(at date: Date = .now) {
        snapshot.notificationRequestCompletedAt = date
        persist()
    }

    func completeFirstRun(at date: Date = .now) {
        snapshot.firstRunStatus = .completed
        snapshot.checkpoint = .finishing
        snapshot.completedAt = date
        snapshot.completionTimeBasis = .recorded
        persist()
        defaults.set(true, forKey: PiboPersistenceKeys.Defaults.onboardingDone)
        Analytics.track(.onboardingCompleted, screen: "onboarding")
    }

    func eventProjection() -> PiboCoreStoryEventProjection {
        PiboCoreStory.deriveEvents(from: PiboCoreStoryFacts(
            connection: coreConnection,
            hasObservedHealthSource: hasObservedHealthSource,
            firstBoMinted: snapshot.storyFirstBoMinted == true,
            firstBoCollected: snapshot.storyFirstBoCollected == true
        ))
    }

    /// General `bo` inventory remains active while the story is paused. These
    /// explicit observations ensure only new changes while the mechanism is on
    /// can advance event 03.
    func observeBoProgress(lifetimeMinted: Int, lifetimeCollected: Int) {
        guard snapshot.temporaryCooperationEnabledLastRun == true else { return }
        let minted = max(0, lifetimeMinted)
        let collected = max(0, lifetimeCollected)
        guard snapshot.connection == .accepted, event02Completed else {
            snapshot.storyBoBaselineMinted = max(snapshot.storyBoBaselineMinted ?? 0, minted)
            snapshot.storyBoBaselineCollected = max(snapshot.storyBoBaselineCollected ?? 0, collected)
            persist()
            return
        }

        var changed = false
        if snapshot.storyFirstBoMinted != true,
           minted > (snapshot.storyBoBaselineMinted ?? minted) {
            snapshot.storyFirstBoMinted = true
            changed = true
            Analytics.track(
                .storyEventAdvanced,
                screen: "home",
                ["event": .string("03"), "state": .string("in_progress")]
            )
        }
        if snapshot.storyFirstBoCollected != true,
           collected > (snapshot.storyBoBaselineCollected ?? collected) {
            snapshot.storyFirstBoCollected = true
            changed = true
            Analytics.track(
                .storyEventAdvanced,
                screen: "home",
                ["event": .string("03"), "state": .string("completed")]
            )
        }
        if changed { persist() }
    }

    func reset() {
        snapshot = OnboardingNarrativeSnapshot()
        defaults.removeObject(forKey: persistenceKey)
        defaults.set(false, forKey: PiboPersistenceKeys.Defaults.onboardingDone)
        persist()
    }

    private var coreConnection: PiboCoreStoryConnectionState {
        switch snapshot.connection {
        case .unresponded: .unresponded
        case .responded: .responded
        case .accepted: .accepted
        case .ended: .ended
        }
    }

    private var event02Completed: Bool {
        snapshot.connection == .accepted && !snapshot.observedHealthSources.isEmpty
    }

    private func trackEvent02IfNeeded(wasCompleted: Bool) {
        guard snapshot.temporaryCooperationEnabledLastRun == true,
              !wasCompleted,
              event02Completed
        else { return }
        Analytics.track(
            .storyEventAdvanced,
            screen: "health",
            ["event": .string("02"), "state": .string("completed")]
        )
    }

    private func recordStoryCheckpoint(_ checkpoint: FirstRunCheckpoint) {
        switch checkpoint {
        case .encounter, .identity, .partnership:
            snapshot.storyCheckpoint = checkpoint
        case .healthSetup, .notificationSetup, .finishing:
            break
        }
    }

    /// Persisted story consent gates durable progression, so malformed or
    /// unsupported snapshots must never be interpreted optimistically.
    private static func normalized(
        _ value: OnboardingNarrativeSnapshot
    ) -> OnboardingNarrativeSnapshot {
        var result = value
        let supportedFlow = (1...OnboardingNarrativeSnapshot.currentFlowVersion)
            .contains(value.flowVersion)
        result.flowVersion = OnboardingNarrativeSnapshot.currentFlowVersion
        result.completedAt = validTimestamp(value.completedAt)
        result.completionTimeBasis = result.completedAt == nil
            ? nil
            : (value.completionTimeBasis ?? .recorded)
        result.respondedAt = validTimestamp(value.respondedAt)
        result.acceptedAt = validTimestamp(value.acceptedAt)
        result.healthRequestCompletedAt = validTimestamp(value.healthRequestCompletedAt)
        result.notificationRequestCompletedAt = validTimestamp(value.notificationRequestCompletedAt)
        result.storyHealthObservationNotBefore = validTimestamp(value.storyHealthObservationNotBefore)
        result.storyBoBaselineMinted = value.storyBoBaselineMinted.map { max(0, $0) }
        result.storyBoBaselineCollected = value.storyBoBaselineCollected.map { max(0, $0) }
        result.storyFirstBoMinted = value.storyFirstBoMinted == true
        result.storyFirstBoCollected = value.storyFirstBoCollected == true

        if !supportedFlow {
            result.connection = .unresponded
            result.respondedAt = nil
            result.acceptedAt = nil
            result.consentVersion = nil
        } else if result.connection == .accepted,
                  (result.acceptedAt == nil
                    || result.consentVersion != OnboardingNarrativeSnapshot.currentConsentVersion) {
            result.connection = .responded
            result.acceptedAt = nil
            result.consentVersion = nil
        } else if result.connection == .unresponded {
            result.respondedAt = nil
            result.acceptedAt = nil
            result.consentVersion = nil
        }
        if result.connection != .accepted {
            result.observedHealthSources.removeAll()
            result.storyHealthObservationNotBefore = nil
            result.storyFirstBoMinted = false
            result.storyFirstBoCollected = false
        }
        return result
    }

    private static func validTimestamp(_ value: Date?) -> Date? {
        guard let value,
              value.timeIntervalSince1970.isFinite,
              value.timeIntervalSince1970 > 0
        else { return nil }
        return value
    }

    private static func firstFullDay(after date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? date
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: persistenceKey)
    }
}

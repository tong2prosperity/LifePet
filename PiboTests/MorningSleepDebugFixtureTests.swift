import Foundation
import Testing
import UserNotifications
@testable import Pibo

@MainActor
private final class RecordingNotificationCenter: MorningSleepNotificationScheduling {
    var authorizationStatus: UNAuthorizationStatus = .authorized
    private(set) var pending: [UNNotificationRequest] = []
    private(set) var removedDelivered: [String] = []

    func morningAuthorizationStatus() async -> UNAuthorizationStatus { authorizationStatus }
    func morningPendingIdentifiers() async -> [String] { pending.map(\.identifier) }
    func morningDeliveredIdentifiers() async -> [String] { [] }
    func morningAdd(_ request: UNNotificationRequest) async throws {
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }
    func morningRemovePending(_ identifiers: [String]) {
        pending.removeAll { identifiers.contains($0.identifier) }
    }
    func morningRemoveDelivered(_ identifiers: [String]) {
        removedDelivered.append(contentsOf: identifiers)
    }
}

/// DEV sleep notification isolation and the real open/seen rules.
@MainActor
@Suite(.serialized)
struct MorningSleepDebugFixtureTests {
    private func makeCoordinator() -> (MorningSleepCoordinator, RecordingNotificationCenter, UserDefaults) {
        let suite = "pibo.tests.morningsleep.fixture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        StressNotifier.shared.sleepSummaryPushEnabled = true
        let notifications = RecordingNotificationCenter()
        return (MorningSleepCoordinator(defaults: defaults, notifications: notifications), notifications, defaults)
    }

    private func realNight(end: Date = .now) -> MorningSleepSummary {
        MorningSleepSummary(
            wakeDay: Calendar.current.startOfDay(for: end),
            generatedAt: end,
            start: end.addingTimeInterval(-7 * 3_600),
            end: end,
            total: 7 * 3_600,
            core: 7 * 3_600, deep: 0, rem: 0, awake: 0,
            segments: [],
            hasDetailedStages: true,
            hasInBedSignal: true,
            hasTerminalAwakeSignal: true,
            awakeningCount: nil,
            continuity: nil,
            baselineDelta: nil,
            overnightHRV: nil,
            sleepingWristTemperature: nil,
            sleepingWristTemperatureDelta: nil,
            respiratoryRate: nil,
            oxygenSaturation: nil,
            sleepHeartRateAverage: nil,
            sleepHeartRateMin: nil,
            sleepLatency: nil,
            nightSignalsScoped: true
        )
    }

    #if DEBUG
    @Test func devNotificationPersistsOnlyTheIsolatedFixture() async throws {
        let (coordinator, notifications, defaults) = makeCoordinator()
        coordinator.setAppActive(false)
        coordinator.debugLocalHourOverride = 8
        await coordinator.receive(realNight(end: .now.addingTimeInterval(-3_600)))
        let realLatest = try #require(coordinator.latestSummary)
        let archiveBefore = defaults.data(forKey: "pibo.sleep.morning.summaries.v2")

        let scheduled = await coordinator.debugScheduleFixtureNotification()
        #expect(scheduled)
        #expect(notifications.pending.contains {
            $0.identifier == MorningSleepCoordinator.debugNotificationIdentifier
                && $0.content.categoryIdentifier == AppNotificationCategory.morningSleepMock
        })
        #expect(defaults.data(forKey: MorningSleepCoordinator.debugFixtureKey) != nil)
        // The real archive and latest night are untouched.
        #expect(defaults.data(forKey: "pibo.sleep.morning.summaries.v2") == archiveBefore)
        #expect(coordinator.latestSummary == realLatest)
    }

    @Test func coldOpenFromTheDevNotificationShowsTheLabelledFixture() async throws {
        let suite = "pibo.tests.morningsleep.fixture.cold.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        StressNotifier.shared.sleepSummaryPushEnabled = true
        let first = MorningSleepCoordinator(defaults: defaults, notifications: RecordingNotificationCenter())
        #expect(await first.debugScheduleFixtureNotification())

        // A fresh process (cold launch) handles the tap.
        let relaunched = MorningSleepCoordinator(defaults: defaults, notifications: RecordingNotificationCenter())
        relaunched.configureCapabilities(sleepReview: { false }, wakeNotification: { false })
        relaunched.setAppActive(true)
        relaunched.handleNotificationOpen(wakeDayKey: nil, isMock: true)
        let presentation = try #require(relaunched.consumablePresentation())
        #expect(presentation.isDebugFixture)
        #expect(relaunched.latestSummary == nil)

        relaunched.markPresented(presentation)
        #expect(defaults.data(forKey: "pibo.sleep.morning.lastPresented.v2") == nil)
        #expect(relaunched.pendingPresentation == nil)
    }

    @Test func launchArgumentFixtureNeverEntersTheRealArchive() {
        let (coordinator, _, defaults) = makeCoordinator()
        coordinator.debugPresentFixture()
        #expect(coordinator.pendingPresentation?.isDebugFixture == true)
        #expect(coordinator.latestSummary == nil)
        #expect(defaults.data(forKey: "pibo.sleep.morning.summaries.v2") == nil)
    }
    #endif

    @Test func mockRouteWithoutAStoredFixtureShowsNothing() {
        let (coordinator, _, _) = makeCoordinator()
        coordinator.setAppActive(true)
        coordinator.handleNotificationOpen(wakeDayKey: nil, isMock: true)
        #expect(coordinator.pendingPresentation == nil)
    }

    @Test func explicitTapReopensASeenCardButPassiveLaunchDoesNot() async throws {
        let (coordinator, _, _) = makeCoordinator()
        coordinator.debugLocalHourOverride = 9
        coordinator.setAppActive(true)
        let night = realNight(end: .now.addingTimeInterval(-60))
        await coordinator.receive(night)
        let first = try #require(coordinator.consumablePresentation())
        coordinator.markPresented(first)

        coordinator.presentLatestIfEligible()
        #expect(coordinator.pendingPresentation == nil)

        coordinator.handleNotificationOpen(wakeDayKey: night.wakeDayKey)
        #expect(coordinator.pendingPresentation?.summary.wakeDayKey == night.wakeDayKey)
        #expect(coordinator.pendingPresentation?.isDebugFixture == false)
    }

    @Test func energyFeedbackDoesNotMarkTheCardSeen() async throws {
        let (coordinator, _, _) = makeCoordinator()
        coordinator.debugLocalHourOverride = 9
        coordinator.setAppActive(true)
        let night = realNight(end: .now.addingTimeInterval(-60))
        await coordinator.receive(night)
        let candidate = try #require(coordinator.energyFeedbackCandidate())
        coordinator.markEnergyPresented(candidate)
        #expect(coordinator.consumablePresentation()?.summary.wakeDayKey == night.wakeDayKey)
    }
}

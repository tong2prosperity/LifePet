import Foundation
import Testing
import UserNotifications
@testable import Pibo

/// Records what the coordinator asked the system to do, so the delivery rules
/// can be asserted without a live notification center.
@MainActor
private final class FakeNotificationCenter: MorningSleepNotificationScheduling {
    var authorizationStatus: UNAuthorizationStatus = .authorized
    private(set) var pending: [UNNotificationRequest] = []
    var delivered: [String] = []
    private(set) var removedDelivered: [String] = []

    var pendingFireDelays: [TimeInterval] {
        pending.compactMap {
            ($0.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval
        }
    }

    func morningAuthorizationStatus() async -> UNAuthorizationStatus { authorizationStatus }

    func morningPendingIdentifiers() async -> [String] { pending.map(\.identifier) }

    func morningDeliveredIdentifiers() async -> [String] { delivered }

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

/// Serialized: every case drives the app-wide `StressNotifier.shared` push gate,
/// so running them concurrently would let one case's setup race another's.
@MainActor
@Suite(.serialized)
struct MorningSleepCoordinatorTests {
    private func makeCoordinator(
        notifications: FakeNotificationCenter
    ) -> (MorningSleepCoordinator, UserDefaults) {
        let suite = "pibo.tests.morningsleep.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        StressNotifier.shared.sleepSummaryPushEnabled = true
        let coordinator = MorningSleepCoordinator(defaults: defaults, notifications: notifications)
        return (coordinator, defaults)
    }

    private func nightSummary(
        end: Date,
        total: TimeInterval = 7 * 3_600,
        hasInBedSignal: Bool = true,
        hasTerminalAwakeSignal: Bool = true
    ) -> MorningSleepSummary {
        MorningSleepSummary(
            wakeDay: Calendar.current.startOfDay(for: end),
            generatedAt: end,
            start: end.addingTimeInterval(-total),
            end: end,
            total: total,
            core: total,
            deep: 0,
            rem: 0,
            awake: 0,
            segments: [],
            hasDetailedStages: true,
            hasInBedSignal: hasInBedSignal,
            hasTerminalAwakeSignal: hasTerminalAwakeSignal,
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
            sleepLatency: nil
        )
    }

    /// Local wall-clock time today at `hour`, so assertions do not depend on
    /// when the suite happens to run.
    private func todayAt(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(
            bySettingHour: hour, minute: minute, second: 0, of: .now
        ) ?? .now
    }

    @Test func aMidNightSyncIsNeverPushedDuringTheQuietBand() async throws {
        let notifications = FakeNotificationCenter()
        let (coordinator, _) = makeCoordinator(notifications: notifications)
        coordinator.setAppActive(false)
        coordinator.debugLocalHourOverride = 2.5

        // 02:30, the watch has written 2.5h of sleep ending in a brief awakening.
        await coordinator.receive(nightSummary(end: .now, total: 2.5 * 3_600))

        #expect(coordinator.pendingPresentation == nil)
        // Exactly one request, and it is parked for the morning rather than fired.
        #expect(notifications.pending.count == 1)
        let delay = try #require(notifications.pendingFireDelays.first)
        #expect(delay > 60 * 60)
    }

    @Test func aMoreCompleteNightReplacesTheStillPendingRequest() async {
        let notifications = FakeNotificationCenter()
        let (coordinator, _) = makeCoordinator(notifications: notifications)
        coordinator.setAppActive(false)
        coordinator.debugLocalHourOverride = 3

        await coordinator.receive(nightSummary(end: .now, total: 2.5 * 3_600))
        #expect(notifications.pending.count == 1)

        // The rest of the night syncs before the deferred request has fired.
        await coordinator.receive(nightSummary(end: .now, total: 7 * 3_600))
        #expect(notifications.pending.count == 1)
        let latest = coordinator.latestSummary
        #expect(
            abs((latest?.total ?? -1) - 7 * 3_600) < 1,
            "latest total \(latest?.total ?? -1) wakeDay \(latest?.wakeDayKey ?? "-")"
        )
    }

    @Test func aFinishedNightOutsideTheQuietBandReachesTheUserImmediately() async {
        let notifications = FakeNotificationCenter()
        let (coordinator, _) = makeCoordinator(notifications: notifications)
        coordinator.setAppActive(true)
        coordinator.debugLocalHourOverride = 8

        await coordinator.receive(nightSummary(end: .now))

        // The app is open, so the card is handed over directly instead of pushed.
        #expect(coordinator.pendingPresentation != nil)
        #expect(notifications.pending.isEmpty)
    }

    @Test func aDaySleeperIsServedAtTheirOwnWakeUp() async {
        let notifications = FakeNotificationCenter()
        let (coordinator, _) = makeCoordinator(notifications: notifications)
        coordinator.setAppActive(true)
        coordinator.debugLocalHourOverride = 16

        await coordinator.receive(nightSummary(end: .now))
        #expect(coordinator.pendingPresentation != nil)
    }

    @Test func aCardShownWhileTheWatchWasStillSyncingIsUpgradedOnce() async throws {
        let notifications = FakeNotificationCenter()
        let (coordinator, _) = makeCoordinator(notifications: notifications)
        coordinator.setAppActive(true)
        coordinator.debugLocalHourOverride = 8

        // The user opens the app moments after waking: the awake marker plus
        // their presence is enough to show a card, but the watch may still be
        // syncing, so this one does not count as settled.
        let partial = nightSummary(end: .now, total: 4 * 3_600)
        await coordinator.receive(partial)
        let first = try #require(coordinator.consumablePresentation())
        #expect(first.isSettled == false)
        coordinator.markPresented(first)
        #expect(coordinator.pendingPresentation == nil)

        // Same night, same numbers → no second card.
        await coordinator.receive(partial)
        #expect(coordinator.pendingPresentation == nil)

        // The rest of the night lands and has since settled → one upgrade.
        let complete = nightSummary(
            end: .now.addingTimeInterval(-40 * 60),
            total: 7 * 3_600,
            hasTerminalAwakeSignal: false
        )
        await coordinator.receive(complete)
        let upgraded = try #require(coordinator.consumablePresentation())
        #expect(upgraded.isSettled)
        coordinator.markPresented(upgraded)

        // That upgrade was settled, so the wake-day is now closed for good.
        await coordinator.receive(nightSummary(
            end: .now.addingTimeInterval(-40 * 60),
            total: 9 * 3_600,
            hasTerminalAwakeSignal: false
        ))
        #expect(coordinator.pendingPresentation == nil)
    }

    @Test func aQueuedCardIsWithheldWhenTheClockDriftsIntoTheQuietBand() async {
        let notifications = FakeNotificationCenter()
        let (coordinator, _) = makeCoordinator(notifications: notifications)
        coordinator.setAppActive(true)
        coordinator.debugLocalHourOverride = 8

        await coordinator.receive(nightSummary(end: .now))
        #expect(coordinator.consumablePresentation() != nil)

        coordinator.debugLocalHourOverride = 2
        // Withheld, not discarded — it comes back once the quiet band ends.
        #expect(coordinator.consumablePresentation() == nil)
        #expect(coordinator.pendingPresentation != nil)
    }

    @Test func aNotificationTappedAfterMidnightResolvesToItsOwnNight() async {
        let notifications = FakeNotificationCenter()
        let (coordinator, _) = makeCoordinator(notifications: notifications)
        coordinator.setAppActive(false)
        coordinator.debugLocalHourOverride = 8

        let calendar = Calendar.current
        let yesterdayMorning = calendar.date(byAdding: .day, value: -1, to: todayAt(7)) ?? .now
        let yesterday = nightSummary(end: yesterdayMorning)
        await coordinator.receive(yesterday)

        // Tonight's session lands and replaces `latestSummary`.
        let tonight = nightSummary(end: todayAt(1), total: 2 * 3_600)
        await coordinator.receive(tonight)
        #expect(coordinator.latestSummary?.wakeDayKey == tonight.wakeDayKey)

        // Tapping yesterday's notification still resolves to yesterday's night,
        // flagged as a catch-up so the card shows its date. The tap is stamped
        // just after midnight — the moment the catch-up window exists for —
        // rather than left on the wall clock: yesterday's wake-day starts at
        // yesterday 00:00, so the 36h window closes at noon today and an
        // afternoon test run would watch the coordinator correctly refuse it.
        coordinator.setAppActive(true)
        coordinator.handleNotificationOpen(
            wakeDayKey: yesterday.wakeDayKey,
            now: todayAt(1)
        )
        #expect(coordinator.pendingPresentation?.summary.wakeDayKey == yesterday.wakeDayKey)
        #expect(coordinator.pendingPresentation?.isCatchUp == true)
    }

    @Test func aNightThatAgedOutIsNotRevived() async {
        let notifications = FakeNotificationCenter()
        let (coordinator, _) = makeCoordinator(notifications: notifications)
        coordinator.setAppActive(false)
        coordinator.debugLocalHourOverride = 8

        let stale = nightSummary(end: .now.addingTimeInterval(-4 * 24 * 3_600))
        await coordinator.receive(stale)
        #expect(notifications.pending.isEmpty)

        coordinator.setAppActive(true)
        coordinator.handleNotificationOpen(wakeDayKey: stale.wakeDayKey)
        #expect(coordinator.pendingPresentation == nil)
    }

    @Test func onlyAFinishedNightFeedsThePersonalBaseline() async {
        let notifications = FakeNotificationCenter()
        let (coordinator, defaults) = makeCoordinator(notifications: notifications)
        coordinator.setAppActive(false)
        coordinator.debugLocalHourOverride = 8

        // Still settling: no terminal awake marker and no quiet time yet.
        await coordinator.receive(nightSummary(
            end: .now,
            total: 3 * 3_600,
            hasTerminalAwakeSignal: false
        ))
        #expect(defaults.data(forKey: "pibo.sleep.morning.baseline.v1") == nil)

        await coordinator.receive(nightSummary(
            end: .now.addingTimeInterval(-40 * 60),
            total: 7 * 3_600,
            hasTerminalAwakeSignal: false
        ))
        #expect(defaults.data(forKey: "pibo.sleep.morning.baseline.v1") != nil)
    }

    @Test func lockedHammockStillArchivesRawSleepWithoutUIOrNotification() async {
        let notifications = FakeNotificationCenter()
        let (coordinator, defaults) = makeCoordinator(notifications: notifications)
        coordinator.configureCapabilities(sleepReview: { false }, wakeNotification: { false })
        coordinator.setAppActive(false)
        coordinator.debugLocalHourOverride = 8

        let summary = nightSummary(end: .now.addingTimeInterval(-40 * 60))
        await coordinator.receive(summary)

        #expect(coordinator.latestSummary?.wakeDayKey == summary.wakeDayKey)
        #expect(coordinator.pendingPresentation == nil)
        #expect(coordinator.latestReviewPresentation() == nil)
        #expect(notifications.pending.isEmpty)
        #expect(defaults.data(forKey: "pibo.sleep.morning.summaries.v2") != nil)
    }

    @Test func lockingHammockRemovesNotificationsScheduledByOlderBuilds() async {
        let notifications = FakeNotificationCenter()
        let (coordinator, _) = makeCoordinator(notifications: notifications)
        try? await notifications.morningAdd(UNNotificationRequest(
            identifier: "pibo.sleep.legacy-pending",
            content: UNMutableNotificationContent(),
            trigger: nil
        ))
        try? await notifications.morningAdd(UNNotificationRequest(
            identifier: "unrelated.notification",
            content: UNMutableNotificationContent(),
            trigger: nil
        ))
        notifications.delivered = ["pibo.sleep.legacy-delivered", "unrelated.delivered"]

        coordinator.configureCapabilities(sleepReview: { false }, wakeNotification: { false })
        for _ in 0..<5 { await Task.yield() }

        #expect(notifications.pending.map(\.identifier) == ["unrelated.notification"])
        #expect(notifications.removedDelivered.contains("pibo.sleep.legacy-delivered"))
        #expect(!notifications.removedDelivered.contains("unrelated.delivered"))
    }

    @Test func deniedNotificationsDoNotBlockUnlockedInAppReview() async {
        let notifications = FakeNotificationCenter()
        notifications.authorizationStatus = .denied
        let (coordinator, _) = makeCoordinator(notifications: notifications)
        coordinator.configureCapabilities(sleepReview: { true }, wakeNotification: { true })
        coordinator.setAppActive(true)
        coordinator.debugLocalHourOverride = 8

        await coordinator.receive(nightSummary(end: .now))

        #expect(coordinator.consumablePresentation() != nil)
        #expect(coordinator.latestReviewPresentation() != nil)
        #expect(notifications.pending.isEmpty)
    }
}

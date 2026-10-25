import Foundation
import Testing
import UserNotifications
@testable import Pibo

@MainActor
struct NotificationBoundaryParityTests {
    private func temporaryDefaults() throws -> (UserDefaults, String) {
        let name = "NotificationBoundaryParityTests.\(UUID())"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func hrvFreshInstallIsOptInAndExistingChoicesSurvive() throws {
        let (defaults, key) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: key) }
        #expect(!StressChangeAlertStore.initialPushEnabled(in: defaults))
        defaults.set(true, forKey: "pibo.stress.push.enabled.v1")
        #expect(StressChangeAlertStore.initialPushEnabled(in: defaults))
        defaults.set(false, forKey: "pibo.stress.push.enabled.v1")
        #expect(!StressChangeAlertStore.initialPushEnabled(in: defaults))
    }

    @Test func hrvOnlySuccessfulDailyDeliveryAdvancesTheCorePolicy() throws {
        let (defaults, key) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: key) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12))!
        let store = StressChangeAlertStore(defaults: defaults, calendar: calendar, now: now)
        #expect(store.kind(for: .excellent, now: now) == nil)
        #expect(store.kind(for: .normal, now: now) == nil)
        #expect(store.kind(for: .notice, now: now) == .elevated)
        #expect(store.kind(for: .overload, now: now) == .elevated, "failure consumes no delivery checkpoint")
        store.recordDelivered(.elevated, at: now)
        let later = now.addingTimeInterval(3600)
        #expect(store.kind(for: .overload, now: later) == nil, "a higher tier cannot duplicate today's lower reminder")
        #expect(store.kind(for: .normal, now: now.addingTimeInterval(10)) == nil)
        #expect(store.kind(for: .normal, now: later) == .recovered)
        store.recordDelivered(.recovered, at: later)
        #expect(store.kind(for: .normal, now: later.addingTimeInterval(3600)) == nil)
        #expect(store.kind(for: .excellent, now: later.addingTimeInterval(3600)) == nil)
        let nextDay = now.addingTimeInterval(86400)
        #expect(store.kind(for: .normal, now: nextDay) == nil)
        #expect(store.kind(for: .notice, now: nextDay) == .elevated)
        #expect(store.kind(for: .notice, now: nextDay.addingTimeInterval(12 * 3600)) == nil)
        #expect(StressAlertKind.elevated.body(for: .notice) == StressAlertKind.elevated.body(for: .overload))
    }

    @Test func hrvUpgradeDoesNotRepeatAnAlreadyDeliveredLowerReminder() throws {
        let (defaults, key) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: key) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let at = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12))!
        defaults.set(at, forKey: "pibo.stress.push.lastAt.v1")
        defaults.set(StressLevel.notice.rawValue, forKey: "pibo.stress.push.lastLevel.v1")
        let store = StressChangeAlertStore(defaults: defaults, calendar: calendar, now: at)
        #expect(store.kind(for: .overload, now: at.addingTimeInterval(3600)) == nil)
        #expect(store.kind(for: .normal, now: at.addingTimeInterval(3600)) == .recovered)
    }

    private final class AppState { var background = true }

    private final class Center: BoMaturityNotificationCenter {
        var status: UNAuthorizationStatus = .authorized
        var requests: [UNNotificationRequest] = []
        var statusReads = 0
        var beforeStatusReturn: (() -> Void)?
        var afterAdd: (() -> Void)?
        func authorizationStatus() async -> UNAuthorizationStatus {
            statusReads += 1
            beforeStatusReturn?()
            return status
        }
        func add(_ request: UNNotificationRequest) async throws { requests.append(request); afterAdd?() }
        func withdraw() { requests.removeAll() }
    }

    @Test func firstBoAndForegroundMaturityNeverRequestOrPublishNotifications() async throws {
        let (defaults, key) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: key) }
        let center = Center()
        let appState = AppState()
        let notifier = BoMaturityNotifier(center: center, defaults: defaults, isBackground: { appState.background })
        notifier.reconcile(ripe: true, cycle: 1)
        await notifier.waitForPending()
        appState.background = false
        notifier.reconcile(ripe: true, cycle: 2)
        await notifier.waitForPending()
        #expect(center.statusReads == 0)
        #expect(center.requests.isEmpty)
        appState.background = true
        notifier.reconcile(ripe: true, cycle: 2)
        await notifier.waitForPending()
        #expect(center.requests.isEmpty, "a maturity seen in the forest cannot notify later")
    }

    @Test func laterBackgroundMaturityUsesOnlyAnExistingPermissionAndDeduplicates() async throws {
        let (defaults, key) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: key) }
        let center = Center()
        center.status = .notDetermined
        let notifier = BoMaturityNotifier(center: center, defaults: defaults, isBackground: { true })
        notifier.reconcile(ripe: true, cycle: 2)
        await notifier.waitForPending()
        #expect(center.requests.isEmpty)
        center.status = .authorized
        notifier.reconcile(ripe: true, cycle: 3)
        await notifier.waitForPending()
        #expect(center.requests.count == 1)
        notifier.reconcile(ripe: true, cycle: 3)
        await notifier.waitForPending()
        let restarted = BoMaturityNotifier(center: center, defaults: defaults, isBackground: { true })
        restarted.reconcile(ripe: true, cycle: 3)
        await restarted.waitForPending()
        #expect(center.requests.count == 1)
    }

    @Test func collectionOrForegroundingInvalidatesAnInFlightBoReminder() async throws {
        let (defaults, key) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: key) }
        let center = Center()
        let appState = AppState()
        let notifier = BoMaturityNotifier(center: center, defaults: defaults, isBackground: { appState.background })
        center.beforeStatusReturn = { notifier.collected(nextRipe: false, nextCycle: 3) }
        notifier.reconcile(ripe: true, cycle: 2)
        await notifier.waitForPending()
        #expect(center.requests.isEmpty)
        center.beforeStatusReturn = nil
        center.afterAdd = { appState.background = false }
        notifier.reconcile(ripe: true, cycle: 4)
        await notifier.waitForPending()
        #expect(center.requests.isEmpty)
    }
}

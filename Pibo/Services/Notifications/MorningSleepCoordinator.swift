import Foundation
import Observation
import UserNotifications
import os

/// Persists the latest calculated night across background process death,
/// deduplicates its local notification, and vends one item-driven presentation
/// to the home screen on the first foreground open after that session.
@MainActor
@Observable
final class MorningSleepCoordinator {
    private(set) var latestSummary: MorningSleepSummary?
    var pendingPresentation: MorningSleepSummary?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notificationCenter: UNUserNotificationCenter
    @ObservationIgnored private var appIsActive = false
    @ObservationIgnored private var mockPresentationWakeDayKey: String?

    private static let summaryKey = "pibo.sleep.morning.latest.v1"
    private static let baselineKey = "pibo.sleep.morning.baseline.v1"
    private static let lastPresentedKey = "pibo.sleep.morning.lastPresented.v1"
    private static let lastScheduledKey = "pibo.sleep.morning.lastScheduled.v1"

    private struct BaselineEntry: Codable {
        let wakeDay: Date
        let total: TimeInterval
    }

    init(
        defaults: UserDefaults? = nil,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        let resolvedDefaults = defaults
            ?? UserDefaults(suiteName: PiboWidgetConstants.appGroupID)
            ?? .standard
        self.defaults = resolvedDefaults
        self.notificationCenter = notificationCenter
        self.latestSummary = Self.decode(
            MorningSleepSummary.self,
            forKey: Self.summaryKey,
            defaults: resolvedDefaults
        )
    }

    func setAppActive(_ active: Bool) {
        appIsActive = active
    }

    /// Called inside the HealthKit observer's bounded background work. The
    /// summary is persisted before notification scheduling so a cold launch
    /// from the notification can always reconstruct the card.
    func receive(_ input: MorningSleepSummary) async {
        var summary = input
        summary.baselineDelta = baselineDeltaAndRecord(summary)
        latestSummary = summary
        encode(summary, forKey: Self.summaryKey)

        guard isCurrentAndUnpresented(summary), summary.isMorningEligible else { return }
        if appIsActive {
            cancelNotification(for: summary)
            pendingPresentation = summary
        } else {
            await scheduleNotification(for: summary)
        }
    }

    /// Foreground fallback for force-quit, delayed Watch sync, denied system
    /// notifications, or a notification the user cleared without opening.
    func presentLatestIfEligible() {
        guard appIsActive,
              let summary = latestSummary,
              isCurrentAndUnpresented(summary),
              summary.isMorningEligible
        else { return }
        cancelNotification(for: summary)
        pendingPresentation = summary
    }

    func handleNotificationOpen(wakeDayKey: String?, isMock: Bool = false) {
        guard let summary = latestSummary,
              wakeDayKey == nil || summary.wakeDayKey == wakeDayKey
        else { return }

        if isMock {
            mockPresentationWakeDayKey = summary.wakeDayKey
            pendingPresentation = summary
            return
        }

        guard isCurrentAndUnpresented(summary) else { return }
        pendingPresentation = summary
    }

    /// Called only after SwiftUI confirms that the sheet content appeared.
    /// This is the once-per-wake-day consumption point.
    func markPresented(_ summary: MorningSleepSummary) {
        if mockPresentationWakeDayKey == summary.wakeDayKey {
            // Rehearsing the DEBUG flow must not consume the real morning card.
            mockPresentationWakeDayKey = nil
        } else {
            defaults.set(summary.wakeDayKey, forKey: Self.lastPresentedKey)
        }
        cancelNotification(for: summary)
        if pendingPresentation?.id == summary.id {
            pendingPresentation = nil
        }
        LPLog.app.notice(
            "Morning sleep card presented wakeDay=\(summary.wakeDayKey, privacy: .public)"
        )
    }

    #if DEBUG
    func debugPresentFixture() {
        let summary = MorningSleepSummary.debugFixture()
        latestSummary = summary
        mockPresentationWakeDayKey = summary.wakeDayKey
        pendingPresentation = summary
    }

    /// Schedules a real local notification containing the fixture. Its mock
    /// category is allowed to show as a foreground banner; only tapping that
    /// banner routes the fixture into the normal home-sheet presentation.
    func debugScheduleFixtureNotification(delay: TimeInterval = 3) async -> Bool {
        guard await debugNotificationAuthorizationAvailable() else {
            LPLog.app.error("Morning sleep mock notification unavailable: not authorized")
            return false
        }

        let summary = MorningSleepSummary.debugFixture()
        latestSummary = summary
        pendingPresentation = nil
        mockPresentationWakeDayKey = nil

        let identifier = "pibo.sleep.mock"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = MorningSleepCopy.notificationTitle
        content.body = MorningSleepCopy.notificationBody
        content.sound = .default
        content.categoryIdentifier = AppNotificationCategory.morningSleepMock
        content.threadIdentifier = "pibo.sleep.mock"
        content.userInfo = [
            AppNotificationCategory.wakeDayUserInfoKey: summary.wakeDayKey,
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, delay),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            LPLog.app.notice("Morning sleep mock notification scheduled")
            return true
        } catch {
            LPLog.app.error(
                "Morning sleep mock notification failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func debugNotificationAuthorizationAvailable() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .ephemeral:
            return true
        case .notDetermined, .provisional:
            do {
                // Stress alerts start with quiet provisional permission. The
                // explicit DEV rehearsal upgrades that permission when iOS
                // allows it, so the tester can tap a visible banner directly.
                return try await notificationCenter.requestAuthorization(
                    options: [.alert, .sound]
                )
            } catch {
                LPLog.app.error(
                    "Morning sleep mock notification authorization failed: \(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
    #endif

    private func isCurrentAndUnpresented(_ summary: MorningSleepSummary) -> Bool {
        Calendar.current.isDateInToday(summary.wakeDay)
            && defaults.string(forKey: Self.lastPresentedKey) != summary.wakeDayKey
    }

    private func scheduleNotification(for summary: MorningSleepSummary) async {
        guard StressNotifier.shared.sleepSummaryPushEnabled else {
            LPLog.app.debug("Morning sleep notification skipped: disabled by user")
            return
        }
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral
        else {
            LPLog.app.debug("Morning sleep notification skipped: not authorized")
            return
        }

        let pending = await notificationCenter.pendingNotificationRequests()
        let alreadyPending = pending.contains { $0.identifier == summary.notificationIdentifier }
        let lastScheduled = defaults.string(forKey: Self.lastScheduledKey)
        // A request that is still pending may be replaced as the Watch sends a
        // more complete batch. Once it has fired or been cleared, never enqueue
        // another notification for the same wake-day.
        if lastScheduled == summary.wakeDayKey && !alreadyPending { return }
        if alreadyPending {
            notificationCenter.removePendingNotificationRequests(
                withIdentifiers: [summary.notificationIdentifier]
            )
        }

        let content = UNMutableNotificationContent()
        content.title = MorningSleepCopy.notificationTitle
        content.body = MorningSleepCopy.notificationBody
        content.sound = .default
        content.categoryIdentifier = AppNotificationCategory.morningSleep
        content.threadIdentifier = "pibo.sleep"
        content.userInfo = [
            AppNotificationCategory.wakeDayUserInfoKey: summary.wakeDayKey,
        ]

        // A terminal awake stage is strong evidence that the session is final.
        // Otherwise give HealthKit 15 minutes to finish its staged batch; a
        // later observer update replaces this still-pending request.
        let readyAt = summary.hasTerminalAwakeSignal
            ? Date()
            : summary.end.addingTimeInterval(15 * 60)
        let delay = readyAt.timeIntervalSinceNow
        let trigger: UNNotificationTrigger? = delay > 1
            ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            : nil
        let request = UNNotificationRequest(
            identifier: summary.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            defaults.set(summary.wakeDayKey, forKey: Self.lastScheduledKey)
            LPLog.app.notice(
                "Morning sleep notification scheduled wakeDay=\(summary.wakeDayKey, privacy: .public) delay=\(Int(max(0, delay)), privacy: .public)s"
            )
        } catch {
            LPLog.app.error(
                "Morning sleep notification failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func cancelNotification(for summary: MorningSleepSummary) {
        let identifiers = [summary.notificationIdentifier]
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func baselineDeltaAndRecord(_ summary: MorningSleepSummary) -> TimeInterval? {
        var entries = Self.decode(
            [BaselineEntry].self,
            forKey: Self.baselineKey,
            defaults: defaults
        ) ?? []
        let prior = entries
            .filter { $0.wakeDay < summary.wakeDay && $0.total > 0 }
            .suffix(28)
            .map(\.total)
        let baseline = prior.count >= 5 ? Self.median(Array(prior)) : nil

        entries.removeAll { Calendar.current.isDate($0.wakeDay, inSameDayAs: summary.wakeDay) }
        entries.append(BaselineEntry(wakeDay: summary.wakeDay, total: summary.total))
        entries.sort { $0.wakeDay < $1.wakeDay }
        if entries.count > 35 { entries.removeFirst(entries.count - 35) }
        encode(entries, forKey: Self.baselineKey)

        return baseline.map { summary.total - $0 }
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        forKey key: String,
        defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

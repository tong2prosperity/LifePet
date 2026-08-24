import Foundation
import Observation
import UserNotifications
import os

/// One resolved morning card, ready to hand to the home screen.
struct MorningSleepPresentation: Equatable, Identifiable, Sendable {
    let summary: MorningSleepSummary
    /// The night settled on quiet time alone. A card promoted only because the
    /// user happened to be holding the phone stays upgradeable exactly once —
    /// the wearable may still have minutes left to sync.
    let isSettled: Bool
    /// The wake-day is no longer today, so the card reads as a dated
    /// retrospective ("补看") rather than "last night".
    let isCatchUp: Bool

    var id: String { summary.wakeDayKey }
}

/// The notification surface the coordinator needs. Abstracted so the delivery
/// rules (quiet band, settle time, one-shot upgrade) can be unit-tested without
/// a live `UNUserNotificationCenter`.
@MainActor
protocol MorningSleepNotificationScheduling: AnyObject {
    func morningAuthorizationStatus() async -> UNAuthorizationStatus
    func morningPendingIdentifiers() async -> [String]
    func morningDeliveredIdentifiers() async -> [String]
    func morningAdd(_ request: UNNotificationRequest) async throws
    func morningRemovePending(_ identifiers: [String])
    func morningRemoveDelivered(_ identifiers: [String])
}

extension UNUserNotificationCenter: MorningSleepNotificationScheduling {
    func morningAuthorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }

    func morningPendingIdentifiers() async -> [String] {
        await pendingNotificationRequests().map(\.identifier)
    }

    func morningDeliveredIdentifiers() async -> [String] {
        await deliveredNotifications().map { $0.request.identifier }
    }

    func morningAdd(_ request: UNNotificationRequest) async throws {
        try await add(request)
    }

    func morningRemovePending(_ identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func morningRemoveDelivered(_ identifiers: [String]) {
        removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

/// Persists recent nights across background process death, decides *when* a
/// sleep summary may reach the user, and vends one item-driven presentation to
/// the home screen.
///
/// Two rules do the heavy lifting, both owned by `pibo-core`:
/// - **Readiness** — a freshly synced batch is never proof that the night is
///   over. Only quiet time (or the user demonstrably holding the phone) is.
/// - **Delivery** — a finished night that lands inside the local quiet band is
///   deferred to the morning rather than pushed at 3am. The deferred request
///   stays pending, so any more complete summary simply replaces it.
@MainActor
@Observable
final class MorningSleepCoordinator {
    private(set) var latestSummary: MorningSleepSummary?
    var pendingPresentation: MorningSleepPresentation?

    /// Re-run the HealthKit sleep fetch. Set by the app so a session that is
    /// still settling gets a second look without waiting for another observer
    /// wake-up (which may never come once the last sample has landed).
    @ObservationIgnored var onRecheckNeeded: (() async -> Void)?
    /// Feature presentation and wake notifications are unlocked by the
    /// hammock. Acquisition and archiving stay unconditional; these closures
    /// gate only the two user-facing delivery surfaces.
    @ObservationIgnored private var allowsSleepReview: () -> Bool = { true }
    @ObservationIgnored private var allowsWakeNotification: () -> Bool = { true }

    #if DEBUG
    /// Pretend it is this local hour when applying the quiet-band rule, so the
    /// "data arrived at 3am" path can be rehearsed without moving the clock.
    /// Observed so the DEV settings row reflects the current choice.
    var debugLocalHourOverride: Double?
    #endif

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notifications: any MorningSleepNotificationScheduling
    @ObservationIgnored private var appIsActive = false
    @ObservationIgnored private var mockPresentationWakeDayKey: String?
    @ObservationIgnored private var recheckTask: Task<Void, Never>?
    /// Recent nights, oldest first. Keeping more than the newest one is what
    /// makes a notification tapped after midnight resolve to its own night
    /// instead of the session that has since replaced it.
    @ObservationIgnored private var archive: [MorningSleepSummary] = []

    private static let archiveKey = "pibo.sleep.morning.summaries.v2"
    private static let legacySummaryKey = "pibo.sleep.morning.latest.v1"
    private static let baselineKey = "pibo.sleep.morning.baseline.v1"
    private static let lastPresentedKey = "pibo.sleep.morning.lastPresented.v2"
    private static let lastEnergyPresentedKey = "pibo.sleep.morning.lastEnergyPresented.v1"
    private static let lastScheduledKey = "pibo.sleep.morning.lastScheduled.v2"
    private static let legacyLastPresentedKey = "pibo.sleep.morning.lastPresented.v1"
    private static let legacyLastScheduledKey = "pibo.sleep.morning.lastScheduled.v1"

    /// How many nights stay reachable. The catch-up window is 36h, so three
    /// entries always cover it even with a nap in between.
    private static let archiveLimit = 3
    /// Upper bound on how long a foreground re-check may sleep. A quiet-band
    /// deferral from just after midnight is the longest realistic wait.
    private static let maxRecheckDelay: TimeInterval = 8 * 60 * 60

    private struct BaselineEntry: Codable {
        let wakeDay: Date
        let total: TimeInterval
    }

    /// What the user has already been shown or pushed for a wake-day. `wasFinal`
    /// is what lets a provisional night be upgraded exactly once.
    private struct DeliveryRecord: Codable, Equatable {
        let wakeDayKey: String
        let totalSeconds: TimeInterval
        let wasFinal: Bool
    }

    init(
        defaults: UserDefaults? = nil,
        notifications: (any MorningSleepNotificationScheduling)? = nil
    ) {
        let resolvedDefaults = defaults
            ?? UserDefaults(suiteName: PiboWidgetConstants.appGroupID)
            ?? .standard
        self.defaults = resolvedDefaults
        self.notifications = notifications ?? UNUserNotificationCenter.current()
        self.archive = Self.loadArchive(from: resolvedDefaults)
        self.latestSummary = archive.last
        migrateLegacyDeliveryRecordsIfNeeded()
    }

    func setAppActive(_ active: Bool) {
        appIsActive = active
        if !active {
            recheckTask?.cancel()
            recheckTask = nil
        }
    }

    func configureCapabilities(
        sleepReview: @escaping () -> Bool,
        wakeNotification: @escaping () -> Bool
    ) {
        allowsSleepReview = sleepReview
        allowsWakeNotification = wakeNotification
        if !allowsSleepReview() {
            pendingPresentation = nil
        }
        if !allowsWakeNotification() {
            Task { [weak self] in
                await self?.cancelLockedWakeNotifications()
            }
        }
    }

    /// Called inside the HealthKit observer's bounded background work. The
    /// summary is archived before any scheduling so a cold launch from the
    /// notification can always reconstruct the card.
    func receive(_ input: MorningSleepSummary) async {
        let now = Date()
        var summary = input
        summary.baselineDelta = baselineDelta(for: summary)

        let readiness = summary.readiness(now: now, userIsInteracting: appIsActive)
        // "Settled" ignores the app-is-open shortcut: the user being awake says
        // nothing about whether the watch has finished syncing. Consumption and
        // the baseline both key off this stricter notion.
        let isSettled = summary.readiness(now: now, userIsInteracting: false) == .final
        // Only a finished night belongs in the personal baseline. A mid-night
        // fragment or an afternoon nap would otherwise skew the 28-day median
        // that the card's "比平时多睡/少睡" line is measured against.
        if isSettled {
            recordBaseline(summary)
        }
        store(summary)

        guard readiness != .notEligible,
              summary.isWithinCatchupWindow(now: now),
              !isBlockedByPriorPresentation(summary, isSettled: isSettled)
        else { return }

        if readiness == .final, appIsActive, allowsSleepReview(), delivery(at: now) == .deliverNow {
            cancelNotification(for: summary)
            pendingPresentation = MorningSleepPresentation(
                summary: summary,
                isSettled: isSettled,
                isCatchUp: summary.isCatchUp(now: now)
            )
            return
        }

        // A still-settling session is scheduled anyway: the request stays
        // pending and any more complete summary replaces it, which is what
        // makes a partial overnight sync self-heal by morning.
        let deliverAt = deliveryDate(for: summary, notBefore: now)
        await scheduleNotification(for: summary, isSettled: isSettled, at: deliverAt)
        if appIsActive {
            scheduleRecheck(at: deliverAt)
        }
    }

    /// Foreground fallback for force-quit, delayed Watch sync, denied system
    /// notifications, or a notification the user cleared without opening.
    func presentLatestIfEligible(now: Date = .now) {
        guard allowsSleepReview(), appIsActive, let summary = latestSummary else { return }
        let isSettled = summary.readiness(now: now, userIsInteracting: false) == .final
        guard summary.readiness(now: now, userIsInteracting: true) == .final,
              summary.isWithinCatchupWindow(now: now),
              !isBlockedByPriorPresentation(summary, isSettled: isSettled),
              delivery(at: now) == .deliverNow
        else { return }
        cancelNotification(for: summary)
        pendingPresentation = MorningSleepPresentation(
            summary: summary,
            isSettled: isSettled,
            isCatchUp: summary.isCatchUp(now: now)
        )
    }

    /// Re-validate the queued card at the moment it would actually appear. A
    /// card queued late in the evening must not surface as "last night" after
    /// midnight, and must not consume the wrong wake-day when it does.
    func consumablePresentation(now: Date = .now) -> MorningSleepPresentation? {
        guard allowsSleepReview() else {
            pendingPresentation = nil
            return nil
        }
        guard let pending = pendingPresentation else { return nil }
        let summary = pending.summary

        if mockPresentationWakeDayKey == summary.wakeDayKey {
            return pending
        }

        guard summary.isWithinCatchupWindow(now: now),
              !isBlockedByPriorPresentation(summary, isSettled: pending.isSettled)
        else {
            pendingPresentation = nil
            return nil
        }
        // Still queued, but the clock has drifted into the quiet band — hold it
        // rather than dropping it.
        guard delivery(at: now) == .deliverNow else { return nil }

        return MorningSleepPresentation(
            summary: summary,
            isSettled: pending.isSettled,
            isCatchUp: summary.isCatchUp(now: now)
        )
    }

    func handleNotificationOpen(wakeDayKey: String?, isMock: Bool = false, now: Date = .now) {
        guard allowsSleepReview() else { return }
        let match: MorningSleepSummary?
        if let wakeDayKey {
            match = archive.first { $0.wakeDayKey == wakeDayKey }
        } else {
            match = latestSummary
        }
        guard let summary = match else {
            LPLog.app.error(
                "Morning sleep notification opened with no archived night wakeDay=\(wakeDayKey ?? "-", privacy: .public)"
            )
            return
        }

        if isMock {
            mockPresentationWakeDayKey = summary.wakeDayKey
            pendingPresentation = MorningSleepPresentation(
                summary: summary,
                isSettled: true,
                isCatchUp: summary.isCatchUp(now: now)
            )
            return
        }

        // An explicit tap is a direct request, so the quiet band does not apply
        // — but a night that has aged out or was already consumed still doesn't
        // reopen.
        let isSettled = summary.readiness(now: now, userIsInteracting: false) == .final
        guard summary.isWithinCatchupWindow(now: now),
              !isBlockedByPriorPresentation(summary, isSettled: isSettled)
        else { return }
        pendingPresentation = MorningSleepPresentation(
            summary: summary,
            isSettled: isSettled,
            isCatchUp: summary.isCatchUp(now: now)
        )
    }

    /// Called only after SwiftUI confirms that the sheet content appeared.
    /// This is the once-per-wake-day consumption point; a card built from a
    /// still-provisional night stays upgradeable exactly once.
    func markPresented(_ presentation: MorningSleepPresentation) {
        let summary = presentation.summary
        if mockPresentationWakeDayKey == summary.wakeDayKey {
            // Rehearsing the DEBUG flow must not consume the real morning card.
            mockPresentationWakeDayKey = nil
        } else {
            encode(
                DeliveryRecord(
                    wakeDayKey: summary.wakeDayKey,
                    totalSeconds: summary.total,
                    wasFinal: presentation.isSettled
                ),
                forKey: Self.lastPresentedKey
            )
        }
        cancelNotification(for: summary)
        recheckTask?.cancel()
        recheckTask = nil
        if pendingPresentation?.id == presentation.id {
            pendingPresentation = nil
        }
        LPLog.app.notice(
            "Morning sleep card presented wakeDay=\(summary.wakeDayKey, privacy: .public) settled=\(presentation.isSettled, privacy: .public)"
        )
    }

    /// Direct hammock access is intentionally repeatable and independent of
    /// the once-per-wake-day notification/presentation bookkeeping.
    func latestReviewPresentation(now: Date = .now) -> MorningSleepPresentation? {
        guard allowsSleepReview(), let summary = latestSummary else { return nil }
        return MorningSleepPresentation(
            summary: summary,
            isSettled: summary.readiness(now: now, userIsInteracting: false) == .final,
            isCatchUp: summary.isCatchUp(now: now)
        )
    }

    /// The health-to-Pibo causal scene is independent of the hammock's
    /// detailed sleep review. It exposes one factual duration, never gated
    /// analysis, and is consumed at most once per local wake-day.
    func energyFeedbackCandidate(now: Date = .now) -> MorningSleepSummary? {
        guard let summary = latestSummary,
              Calendar.current.isDate(summary.wakeDay, inSameDayAs: now),
              defaults.string(forKey: Self.lastEnergyPresentedKey) != summary.wakeDayKey
        else { return nil }
        return summary
    }

    func markEnergyPresented(_ summary: MorningSleepSummary) {
        defaults.set(summary.wakeDayKey, forKey: Self.lastEnergyPresentedKey)
        LPLog.bo.notice(
            "sleep energy feedback presented wakeDay=\(summary.wakeDayKey, privacy: .public)"
        )
    }

    #if DEBUG
    func debugPresentFixture() {
        guard allowsSleepReview() else { return }
        let summary = MorningSleepSummary.debugFixture()
        store(summary)
        mockPresentationWakeDayKey = summary.wakeDayKey
        pendingPresentation = MorningSleepPresentation(
            summary: summary,
            isSettled: true,
            isCatchUp: false
        )
    }

    /// Schedules a real local notification containing the fixture. Its mock
    /// category is allowed to show as a foreground banner; only tapping that
    /// banner routes the fixture into the normal home-sheet presentation.
    func debugScheduleFixtureNotification(delay: TimeInterval = 3) async -> Bool {
        guard allowsSleepReview(), allowsWakeNotification() else { return false }
        guard await debugNotificationAuthorizationAvailable() else {
            LPLog.app.error("Morning sleep mock notification unavailable: not authorized")
            return false
        }

        let summary = MorningSleepSummary.debugFixture()
        store(summary)
        pendingPresentation = nil
        mockPresentationWakeDayKey = nil

        let identifier = "pibo.sleep.mock"
        notifications.morningRemovePending([identifier])
        notifications.morningRemoveDelivered([identifier])

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
            try await notifications.morningAdd(request)
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
        switch await notifications.morningAuthorizationStatus() {
        case .authorized, .ephemeral:
            return true
        case .notDetermined, .provisional:
            do {
                // Stress alerts start with quiet provisional permission. The
                // explicit DEV rehearsal upgrades that permission when iOS
                // allows it, so the tester can tap a visible banner directly.
                return try await UNUserNotificationCenter.current().requestAuthorization(
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

    // MARK: - Delivery timing

    /// The local wall-clock hour used for the quiet-band rule.
    private func localHour(at date: Date) -> Double {
        #if DEBUG
        if let debugLocalHourOverride { return debugLocalHourOverride }
        #endif
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
    }

    private func delivery(at date: Date) -> PiboCoreSleepAdapter.Delivery {
        PiboCoreSleepAdapter.morningDelivery(readiness: .final, localHour: localHour(at: date))
    }

    /// Earliest moment this night may reach the user: after it has settled, and
    /// outside the quiet band.
    private func deliveryDate(for summary: MorningSleepSummary, notBefore now: Date) -> Date {
        let earliest = max(now, summary.settledAt)
        guard delivery(at: earliest) == .deferToMorning else { return earliest }
        return nextDeferredMorning(onOrAfter: earliest)
    }

    /// The next occurrence of Core's deferred hour at or after `date`.
    private func nextDeferredMorning(onOrAfter date: Date) -> Date {
        let hour = PiboCoreSleepAdapter.morningDeferredHour
        let calendar = Calendar.current
        let target = calendar.date(
            bySettingHour: Int(hour),
            minute: Int((hour - hour.rounded(.down)) * 60),
            second: 0,
            of: date
        )
        guard let target else { return date.addingTimeInterval(60 * 60) }
        if target >= date { return target }
        return calendar.date(byAdding: .day, value: 1, to: target) ?? target
    }

    /// Give a still-settling night a second look while the app stays open —
    /// once the last sample has landed, no further observer wake-up arrives.
    private func scheduleRecheck(at date: Date) {
        let delay = date.timeIntervalSinceNow
        guard delay > 0, delay <= Self.maxRecheckDelay, onRecheckNeeded != nil else { return }
        recheckTask?.cancel()
        recheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay + 1))
            guard !Task.isCancelled else { return }
            await self?.onRecheckNeeded?()
        }
    }

    // MARK: - Notification

    private func scheduleNotification(
        for summary: MorningSleepSummary,
        isSettled: Bool,
        at fireDate: Date
    ) async {
        guard allowsWakeNotification() else {
            LPLog.app.debug("Morning sleep notification skipped: hammock not unlocked")
            return
        }
        guard StressNotifier.shared.sleepSummaryPushEnabled else {
            LPLog.app.debug("Morning sleep notification skipped: disabled by user")
            return
        }
        switch await notifications.morningAuthorizationStatus() {
        case .authorized, .provisional, .ephemeral: break
        default:
            LPLog.app.debug("Morning sleep notification skipped: not authorized")
            return
        }

        let identifier = summary.notificationIdentifier
        let alreadyPending = await notifications.morningPendingIdentifiers().contains(identifier)
        // A request that is still pending may be replaced as the Watch sends a
        // more complete batch. Once it has fired, only a genuine upgrade (a
        // provisional night that filled in) may enqueue another one.
        if let last = decode(DeliveryRecord.self, forKey: Self.lastScheduledKey),
           last.wakeDayKey == summary.wakeDayKey,
           !alreadyPending,
           !PiboCoreSleepAdapter.morningSummarySupersedes(
               previousTotalSeconds: last.totalSeconds,
               previousWasFinal: last.wasFinal,
               nextTotalSeconds: summary.total,
               nextIsFinal: isSettled
           ) {
            return
        }
        if alreadyPending {
            notifications.morningRemovePending([identifier])
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

        let delay = fireDate.timeIntervalSinceNow
        let trigger: UNNotificationTrigger? = delay > 1
            ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            : nil
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notifications.morningAdd(request)
            encode(
                DeliveryRecord(
                    wakeDayKey: summary.wakeDayKey,
                    totalSeconds: summary.total,
                    wasFinal: isSettled
                ),
                forKey: Self.lastScheduledKey
            )
            LPLog.app.notice(
                "Morning sleep notification scheduled wakeDay=\(summary.wakeDayKey, privacy: .public) settled=\(isSettled, privacy: .public) delay=\(Int(max(0, delay)), privacy: .public)s"
            )
        } catch {
            LPLog.app.error(
                "Morning sleep notification failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func cancelNotification(for summary: MorningSleepSummary) {
        let identifiers = [summary.notificationIdentifier]
        notifications.morningRemovePending(identifiers)
        notifications.morningRemoveDelivered(identifiers)
    }

    /// Upgrade/reset migration: a notification scheduled by an older build must
    /// not survive after the hammock capability becomes locked. Raw summaries
    /// remain archived; only user-facing notification surfaces are removed.
    private func cancelLockedWakeNotifications() async {
        guard !allowsWakeNotification() else { return }
        let pending = await notifications.morningPendingIdentifiers()
        let delivered = await notifications.morningDeliveredIdentifiers()
        let identifiers = Set(pending + delivered).filter { $0.hasPrefix("pibo.sleep.") }
        guard !identifiers.isEmpty else { return }
        let values = Array(identifiers)
        notifications.morningRemovePending(values)
        notifications.morningRemoveDelivered(values)
    }

    // MARK: - Consumption bookkeeping

    private func isBlockedByPriorPresentation(
        _ summary: MorningSleepSummary,
        isSettled: Bool
    ) -> Bool {
        guard let last = decode(DeliveryRecord.self, forKey: Self.lastPresentedKey),
              last.wakeDayKey == summary.wakeDayKey
        else { return false }
        return !PiboCoreSleepAdapter.morningSummarySupersedes(
            previousTotalSeconds: last.totalSeconds,
            previousWasFinal: last.wasFinal,
            nextTotalSeconds: summary.total,
            nextIsFinal: isSettled
        )
    }

    /// Adopt the pre-v2 bare-string markers once. They are recorded as final so
    /// a night the user already saw can never re-present after the upgrade.
    private func migrateLegacyDeliveryRecordsIfNeeded() {
        for (legacyKey, key) in [
            (Self.legacyLastPresentedKey, Self.lastPresentedKey),
            (Self.legacyLastScheduledKey, Self.lastScheduledKey),
        ] {
            guard defaults.data(forKey: key) == nil,
                  let wakeDayKey = defaults.string(forKey: legacyKey)
            else { continue }
            encode(
                DeliveryRecord(wakeDayKey: wakeDayKey, totalSeconds: 0, wasFinal: true),
                forKey: key
            )
        }
    }

    // MARK: - Archive

    private func store(_ summary: MorningSleepSummary) {
        archive.removeAll { $0.wakeDayKey == summary.wakeDayKey }
        archive.append(summary)
        archive.sort { $0.wakeDay < $1.wakeDay }
        if archive.count > Self.archiveLimit {
            archive.removeFirst(archive.count - Self.archiveLimit)
        }
        latestSummary = archive.last
        encode(archive, forKey: Self.archiveKey)
    }

    private static func loadArchive(from defaults: UserDefaults) -> [MorningSleepSummary] {
        if let stored = decode([MorningSleepSummary].self, forKey: archiveKey, defaults: defaults) {
            return stored.sorted { $0.wakeDay < $1.wakeDay }
        }
        // One-time adoption of the pre-v2 single-summary key.
        if let legacy = decode(
            MorningSleepSummary.self,
            forKey: legacySummaryKey,
            defaults: defaults
        ) {
            return [legacy]
        }
        return []
    }

    // MARK: - Baseline

    /// Read-only comparison against the personal median. Kept separate from
    /// recording so a provisional night can still show a delta without being
    /// folded into the baseline it is measured against.
    private func baselineDelta(for summary: MorningSleepSummary) -> TimeInterval? {
        let entries = decode([BaselineEntry].self, forKey: Self.baselineKey) ?? []
        let prior = entries
            .filter { $0.wakeDay < summary.wakeDay && $0.total > 0 }
            .suffix(28)
            .map(\.total)
        guard prior.count >= 5, let baseline = Self.median(Array(prior)) else { return nil }
        return summary.total - baseline
    }

    private func recordBaseline(_ summary: MorningSleepSummary) {
        var entries = decode([BaselineEntry].self, forKey: Self.baselineKey) ?? []
        entries.removeAll { Calendar.current.isDate($0.wakeDay, inSameDayAs: summary.wakeDay) }
        entries.append(BaselineEntry(wakeDay: summary.wakeDay, total: summary.total))
        entries.sort { $0.wakeDay < $1.wakeDay }
        if entries.count > 35 { entries.removeFirst(entries.count - 35) }
        encode(entries, forKey: Self.baselineKey)
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

    // MARK: - Persistence helpers

    private func encode(_ value: some Encodable, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        Self.decode(type, forKey: key, defaults: defaults)
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

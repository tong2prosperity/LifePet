import Foundation
import Observation
import UserNotifications
import os

/// Sends one immediate local notification when a newly synced HealthKit
/// workout completes. HealthKit's UUID is the durable deduplication key, so a
/// background observer wake and a later foreground reconcile cannot notify
/// twice for the same workout.
@MainActor
@Observable
final class WorkoutCompletionNotifier {
    static let shared = WorkoutCompletionNotifier()

    var pushEnabled: Bool {
        didSet {
            UserDefaults.standard.set(pushEnabled, forKey: Self.enabledKey)
        }
    }

    private(set) var authorized = false

    @ObservationIgnored private let notificationCenter: UNUserNotificationCenter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var inFlightIDs: Set<UUID> = []

    private static let enabledKey = "pibo.workout.push.enabled.v1"
    private static let deliveredIDsKey = "pibo.workout.push.deliveredIDs.v1"
    private static let retainedIDLimit = 64

    private init(
        notificationCenter: UNUserNotificationCenter = .current(),
        defaults: UserDefaults? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults
            ?? UserDefaults(suiteName: PiboWidgetConstants.appGroupID)
            ?? .standard
        self.pushEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Quietly covers existing users without forcing a permission prompt. An
    /// explicit settings toggle upgrades to full alert + sound authorization.
    func start() async {
        let settings = await notificationCenter.notificationSettings()
        if settings.authorizationStatus == .notDetermined, pushEnabled {
            await requestAuthorization(provisional: true)
        } else {
            authorized = Self.isAuthorized(settings.authorizationStatus)
        }
    }

    func requestAuthorization(provisional: Bool = false) async {
        var options: UNAuthorizationOptions = [.alert, .sound]
        if provisional { options.insert(.provisional) }
        do {
            authorized = try await notificationCenter.requestAuthorization(options: options)
        } catch {
            authorized = false
            LPLog.workout.error(
                "workout notification auth failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    @discardableResult
    func maybeNotify(workout: PendingWorkout, piboState: PiboActivityState) async -> Bool {
        guard pushEnabled,
              !deliveredIDs.contains(workout.id),
              inFlightIDs.insert(workout.id).inserted
        else { return false }
        defer { inFlightIDs.remove(workout.id) }

        let settings = await notificationCenter.notificationSettings()
        authorized = Self.isAuthorized(settings.authorizationStatus)
        guard authorized else { return false }

        let content = UNMutableNotificationContent()
        content.title = AppLocalization.format("%@完成 · Pibo %@", workout.label, piboState.displayName)
        content.body = notificationBody(for: workout, state: piboState)
        content.sound = .default
        content.categoryIdentifier = AppNotificationCategory.workoutCompleted
        content.threadIdentifier = "pibo.workout"
        content.userInfo = [AppNotificationCategory.workoutIDUserInfoKey: workout.id.uuidString]

        let request = UNNotificationRequest(
            identifier: "pibo.workout.\(workout.id.uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await notificationCenter.add(request)
            rememberDelivered(workout.id)
            LPLog.workout.notice(
                "workout notification delivered id=\(workout.id.uuidString, privacy: .public) state=\(piboState.rawValue, privacy: .public)"
            )
            return true
        } catch {
            LPLog.workout.error(
                "workout notification failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func notificationBody(for workout: PendingWorkout, state: PiboActivityState) -> String {
        let activity = AppLocalization.format("%d 分钟%@", workout.durationMin, workout.label)
        switch state {
        case .deepSleep:
            return AppLocalization.format("你完成了%@。Pibo 还缩在梦里，头上的花却悄悄亮了一点。", activity)
        case .waking:
            return AppLocalization.format("%@？Pibo 刚醒就收到了……花好像精神了。", activity)
        case .active:
            return AppLocalization.format("%@？花都支棱起来了……还、还不错。", activity)
        case .irritated:
            return AppLocalization.format("%@已记住。Pibo 本来有点烦，花现在精神了一些。", activity)
        case .idle:
            return AppLocalization.format("Pibo 发呆时收到了你的%@……花醒过来一点。", activity)
        case .disturbed:
            return AppLocalization.format("先别戳了……不过这次%@，花记住了。", activity)
        }
    }

    private var deliveredIDs: Set<UUID> {
        Set((defaults.stringArray(forKey: Self.deliveredIDsKey) ?? []).compactMap {
            UUID(uuidString: $0)
        })
    }

    private func rememberDelivered(_ id: UUID) {
        var ids = defaults.stringArray(forKey: Self.deliveredIDsKey) ?? []
        ids.removeAll { $0 == id.uuidString }
        ids.append(id.uuidString)
        defaults.set(Array(ids.suffix(Self.retainedIDLimit)), forKey: Self.deliveredIDsKey)
    }

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined, .denied: return false
        @unknown default: return false
        }
    }
}

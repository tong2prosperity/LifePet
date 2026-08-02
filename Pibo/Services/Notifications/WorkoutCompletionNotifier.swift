import Foundation
import Observation
import UserNotifications
import os

/// Small testable FIFO used for the shared achievement notification slot.
/// Each submitted operation waits for the previous write to finish, so call
/// order—not completion timing—decides which request is left delivered.
@MainActor
final class AchievementNotificationPublicationQueue {
    private var tail: Task<Bool, Never>?

    func submit(
        _ operation: @escaping @MainActor () async -> Bool
    ) -> Task<Bool, Never> {
        let predecessor = tail
        let publication = Task { @MainActor in
            if let predecessor {
                _ = await predecessor.value
            }
            return await operation()
        }
        tail = publication
        return publication
    }
}

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
    /// Serializes writes to the one replaceable achievement request. A steps
    /// observer and a workout observer can overlap while awaiting notification
    /// authorization; without a publication tail, the older async add could
    /// finish last and overwrite the newer product decision.
    @ObservationIgnored private let achievementPublicationQueue =
        AchievementNotificationPublicationQueue()

    private static let enabledKey = "pibo.workout.push.enabled.v1"
    private static let deliveredIDsKey = "pibo.workout.push.deliveredIDs.v1"
    private static let retainedIDLimit = 64
    private static let achievementRequestID = "pibo.animation.achievement.latest"
    private static let firstBoRipeRequestID = "pibo.bo.first-ripe"

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
        guard !Task.isCancelled else { return false }
        authorized = Self.isAuthorized(settings.authorizationStatus)
        guard authorized else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Pibo"
        if PiboCoreAnimationAdapter.achievementContentID(kind: .pigu, modal: false)
            == "animation.workout.notification" {
            content.body = AppLocalization.format("你刚完成了「%@」。我注意到了。", workout.label)
        }
        content.sound = .default
        content.categoryIdentifier = AppNotificationCategory.workoutCompleted
        content.threadIdentifier = "pibo.animation.achievement"
        content.userInfo = [
            AppNotificationCategory.workoutIDUserInfoKey: workout.id.uuidString,
            AppNotificationCategory.achievementKindUserInfoKey: "pigu",
        ]

        let request = UNNotificationRequest(
            identifier: Self.achievementRequestID,
            content: content,
            trigger: nil
        )
        if await enqueueAchievementRequest(request) {
            rememberDelivered(workout.id)
            LPLog.workout.notice(
                "workout notification delivered id=\(workout.id.uuidString, privacy: .public) state=\(piboState.rawValue, privacy: .public)"
            )
            return true
        }
        return false
    }

    @discardableResult
    func notifyStepsAchievement() async -> Bool {
        guard pushEnabled else { return false }
        let settings = await notificationCenter.notificationSettings()
        guard !Task.isCancelled else { return false }
        authorized = Self.isAuthorized(settings.authorizationStatus)
        guard authorized else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Pibo"
        if PiboCoreAnimationAdapter.achievementContentID(kind: .muscle, modal: false)
            == "animation.steps_10000.notification" {
            content.body = AppLocalization.text("今天走到 10,000 步了。我注意到了。")
        }
        content.sound = .default
        content.categoryIdentifier = AppNotificationCategory.achievement
        content.threadIdentifier = "pibo.animation.achievement"
        content.userInfo = [AppNotificationCategory.achievementKindUserInfoKey: "muscle"]
        guard !Task.isCancelled else { return false }
        return await enqueueAchievementRequest(UNNotificationRequest(
            identifier: Self.achievementRequestID,
            content: content,
            trigger: nil
        ))
    }

    /// 首枚 `bo` 长熟时的一次性提醒。
    ///
    /// 只发这一次。规则是「熟了就能拔、拔不拔随你，但不拔就不长新的」—— 用户得先
    /// 知道有这条规则，之后就不该再被催。**是否只发一次由调用方的一次性标志位把守**，
    /// 这里不做去重，因为这个通知没有可替换的「最新一条」语义。
    @discardableResult
    func notifyFirstBoRipened() async -> Bool {
        guard pushEnabled else { return false }
        let settings = await notificationCenter.notificationSettings()
        guard !Task.isCancelled else { return false }
        authorized = Self.isAuthorized(settings.authorizationStatus)
        guard authorized else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Pibo"
        content.body = AppLocalization.text("头上那株长好了。要收就收，不收它就停在那儿，不会再长新的。")
        content.sound = .default
        content.threadIdentifier = "pibo.bo.ripe"
        do {
            try await notificationCenter.add(UNNotificationRequest(
                identifier: Self.firstBoRipeRequestID,
                content: content,
                trigger: nil
            ))
            LPLog.bo.notice("first-ripe notification delivered")
            return true
        } catch {
            LPLog.bo.error("first-ripe notification failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Queueing, rather than merely cancelling the previous caller, is what
    /// guarantees that the most recently observed achievement owns the final
    /// delivered notification. Cancellation cannot reliably stop an
    /// `UNUserNotificationCenter.add` that is already in flight.
    private func enqueueAchievementRequest(_ request: UNNotificationRequest) async -> Bool {
        let publication = achievementPublicationQueue.submit { @MainActor [notificationCenter] in
            notificationCenter.removeDeliveredNotifications(
                withIdentifiers: [Self.achievementRequestID]
            )
            do {
                try await notificationCenter.add(request)
                return true
            } catch {
                LPLog.workout.error(
                    "achievement notification failed: \(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        }
        return await publication.value
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

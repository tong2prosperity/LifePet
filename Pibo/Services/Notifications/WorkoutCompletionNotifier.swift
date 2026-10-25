import Foundation
import Observation
import UserNotifications
import UIKit
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

@MainActor
protocol WorkoutNotificationScheduling: AnyObject {
    func workoutAuthorizationStatus() async -> UNAuthorizationStatus
    func workoutRequestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func workoutAdd(_ request: UNNotificationRequest) async throws
    func workoutWithdraw(_ identifier: String)
}

extension UNUserNotificationCenter: WorkoutNotificationScheduling {
    func workoutAuthorizationStatus() async -> UNAuthorizationStatus { await notificationSettings().authorizationStatus }
    func workoutRequestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await requestAuthorization(options: options)
    }
    func workoutAdd(_ request: UNNotificationRequest) async throws { try await add(request) }
    func workoutWithdraw(_ identifier: String) {
        removePendingNotificationRequests(withIdentifiers: [identifier])
        removeDeliveredNotifications(withIdentifiers: [identifier])
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
            preferenceDefaults.set(pushEnabled, forKey: Self.enabledKey)
            if !pushEnabled { invalidatePendingReminder() }
        }
    }

    private(set) var authorized = false

    @ObservationIgnored private let notificationCenter: any WorkoutNotificationScheduling
    @ObservationIgnored private let preferenceDefaults: UserDefaults
    @ObservationIgnored private let isBackground: @MainActor () -> Bool
    @ObservationIgnored private var publicationGeneration = 0
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

    init(
        notificationCenter: any WorkoutNotificationScheduling = UNUserNotificationCenter.current(),
        defaults: UserDefaults? = nil,
        preferenceDefaults: UserDefaults = .standard,
        isBackground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .background }
    ) {
        self.notificationCenter = notificationCenter
        self.preferenceDefaults = preferenceDefaults
        self.isBackground = isBackground
        self.defaults = defaults
            ?? UserDefaults(suiteName: PiboWidgetConstants.appGroupID)
            ?? .standard
        self.pushEnabled = preferenceDefaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Restores the current authorization state only. Launch never requests
    /// notification permission (decision 049); the Home guide and the explicit
    /// settings toggle request full alert + sound authorization.
    func start() async {
        authorized = Self.isAuthorized(await notificationCenter.workoutAuthorizationStatus())
    }

    func requestAuthorization(provisional: Bool = false) async {
        var options: UNAuthorizationOptions = [.alert, .sound]
        if provisional { options.insert(.provisional) }
        do {
            authorized = try await notificationCenter.workoutRequestAuthorization(options: options)
        } catch {
            authorized = false
            LPLog.workout.error(
                "workout notification auth failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    @discardableResult
    func maybeNotify(workout: PendingWorkout, piboState: PiboActivityState) async -> Bool {
        guard isBackground(),
              pushEnabled,
              !deliveredIDs.contains(workout.id),
              inFlightIDs.insert(workout.id).inserted
        else { return false }
        defer { inFlightIDs.remove(workout.id) }

        let generation = publicationGeneration
        let status = await notificationCenter.workoutAuthorizationStatus()
        guard !Task.isCancelled, canPublish(generation) else { return false }
        authorized = Self.isAuthorized(status)
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
        guard canPublish(generation) else { return false }
        if await enqueueAchievementRequest(request, generation: generation) {
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
        guard isBackground(), pushEnabled else { return false }
        let generation = publicationGeneration
        let status = await notificationCenter.workoutAuthorizationStatus()
        guard !Task.isCancelled, canPublish(generation) else { return false }
        authorized = Self.isAuthorized(status)
        guard authorized else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Pibo"
        if PiboCoreAnimationAdapter.achievementContentID(kind: .muscle, modal: false)
            == "animation.steps_8000.notification" {
            content.body = AppLocalization.text("今天走到 8,000 步了。我注意到了。")
        }
        content.sound = .default
        content.categoryIdentifier = AppNotificationCategory.achievement
        content.threadIdentifier = "pibo.animation.achievement"
        content.userInfo = [AppNotificationCategory.achievementKindUserInfoKey: "muscle"]
        guard !Task.isCancelled else { return false }
        guard canPublish(generation) else { return false }
        return await enqueueAchievementRequest(UNNotificationRequest(
            identifier: Self.achievementRequestID,
            content: content,
            trigger: nil
        ), generation: generation)
    }

    /// Queueing, rather than merely cancelling the previous caller, is what
    /// guarantees that the most recently observed achievement owns the final
    /// delivered notification. Cancellation cannot reliably stop an
    /// `UNUserNotificationCenter.add` that is already in flight.
    private func enqueueAchievementRequest(_ request: UNNotificationRequest, generation: Int) async -> Bool {
        let publication = achievementPublicationQueue.submit { @MainActor [self] in
            guard canPublish(generation) else { return false }
            notificationCenter.workoutWithdraw(Self.achievementRequestID)
            do {
                try await notificationCenter.workoutAdd(request)
                guard canPublish(generation) else {
                    notificationCenter.workoutWithdraw(Self.achievementRequestID)
                    return false
                }
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

    /// Called after a foreground return and when the user disables reminders.
    /// Invalidating the generation also cancels work waiting in the FIFO.
    func invalidatePendingReminder() {
        publicationGeneration += 1
        notificationCenter.workoutWithdraw(Self.achievementRequestID)
    }

    private func canPublish(_ generation: Int) -> Bool {
        generation == publicationGeneration && pushEnabled && isBackground()
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

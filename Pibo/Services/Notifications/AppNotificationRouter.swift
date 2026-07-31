import Foundation
import UserNotifications

nonisolated enum AppNotificationCategory {
    static let morningSleep = "pibo.notification.morning-sleep"
    static let morningSleepMock = "pibo.notification.morning-sleep.mock"
    static let workoutCompleted = "pibo.notification.workout-completed"
    static let achievement = "pibo.notification.animation-achievement"
    /// Stress readings + the every-reading diagnostic. Tapping opens the history
    /// surface focused on the 压力卡 — the screen the notification is about.
    static let stress = "pibo.notification.stress"
    static let wakeDayUserInfoKey = "piboWakeDay"
    static let workoutIDUserInfoKey = "piboWorkoutID"
    static let achievementKindUserInfoKey = "piboAnimationAchievementKind"
}

/// The app has exactly one `UNUserNotificationCenterDelegate`. Stress and sleep
/// notifications share it so one feature can never silently replace the
/// other's foreground presentation or response routing.
@MainActor
final class AppNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationRouter()

    var onMorningSleepOpened: ((String?, Bool) -> Void)?
    /// Fired when a stress notification is tapped.
    var onStressOpened: (() -> Void)?
    var onAchievementOpened: (() -> Void)?

    private override init() {
        super.init()
    }

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    // Both delegate methods stay on the main actor. They look isolation-free —
    // they only read the notification and call back into `@MainActor` state —
    // but the isolation that matters is the one they *finish* on: the `async`
    // form is bridged to ObjC as a completion handler, and UIKit runs
    // main-thread-only work (`_updateSnapshotAndStateRestoration…`) inside it.
    // Marked `nonisolated`, the continuation lands on the cooperative pool and
    // that completion fires off-main, tripping a UIKit assertion → SIGABRT on
    // the notification tap. Hopping to `MainActor` *inside* the body doesn't
    // help: execution hops straight back out before the completion runs.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.content.categoryIdentifier == AppNotificationCategory.morningSleep {
            // When already foregrounded, the coordinator presents the native
            // morning sheet. Avoid showing a duplicate banner above it.
            return []
        }
        // The DEBUG sleep mock intentionally uses a separate category so the
        // complete banner-tap-card path can be rehearsed without backgrounding.
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let category = response.notification.request.content.categoryIdentifier
        if category == AppNotificationCategory.stress {
            onStressOpened?()
            return
        }
        if category == AppNotificationCategory.workoutCompleted
            || category == AppNotificationCategory.achievement {
            onAchievementOpened?()
            return
        }
        guard category == AppNotificationCategory.morningSleep
                || category == AppNotificationCategory.morningSleepMock
        else { return }
        let wakeDay = response.notification.request.content
            .userInfo[AppNotificationCategory.wakeDayUserInfoKey] as? String
        onMorningSleepOpened?(
            wakeDay,
            category == AppNotificationCategory.morningSleepMock
        )
    }
}

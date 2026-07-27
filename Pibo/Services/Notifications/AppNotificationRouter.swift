import Foundation
import UserNotifications

nonisolated enum AppNotificationCategory {
    static let morningSleep = "pibo.notification.morning-sleep"
    static let morningSleepMock = "pibo.notification.morning-sleep.mock"
    static let workoutCompleted = "pibo.notification.workout-completed"
    /// Stress readings + the every-reading diagnostic. Tapping opens the history
    /// surface focused on the 压力卡 — the screen the notification is about.
    static let stress = "pibo.notification.stress"
    static let wakeDayUserInfoKey = "piboWakeDay"
    static let workoutIDUserInfoKey = "piboWorkoutID"
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

    private override init() {
        super.init()
    }

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let category = response.notification.request.content.categoryIdentifier
        if category == AppNotificationCategory.stress {
            await MainActor.run { [weak self] in self?.onStressOpened?() }
            return
        }
        guard category == AppNotificationCategory.morningSleep
                || category == AppNotificationCategory.morningSleepMock
        else { return }
        let wakeDay = response.notification.request.content
            .userInfo[AppNotificationCategory.wakeDayUserInfoKey] as? String
        await MainActor.run { [weak self] in
            self?.onMorningSleepOpened?(
                wakeDay,
                category == AppNotificationCategory.morningSleepMock
            )
        }
    }
}

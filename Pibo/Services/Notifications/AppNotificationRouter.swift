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

/// A sendable value parsed from the immutable notification payload before the
/// delegate hops to the main queue. Keeping UIKit objects out of that hop makes
/// the executor boundary explicit and gives the routing contract a test seam.
nonisolated enum AppNotificationRoute: Equatable, Sendable {
    case stress
    case achievement
    case morningSleep(wakeDayKey: String?, isMock: Bool)
    case none

    init(category: String, wakeDayKey: String?) {
        switch category {
        case AppNotificationCategory.stress:
            self = .stress
        case AppNotificationCategory.workoutCompleted,
             AppNotificationCategory.achievement:
            self = .achievement
        case AppNotificationCategory.morningSleep:
            self = .morningSleep(wakeDayKey: wakeDayKey, isMock: false)
        case AppNotificationCategory.morningSleepMock:
            self = .morningSleep(wakeDayKey: wakeDayKey, isMock: true)
        default:
            self = .none
        }
    }
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

    // Use the protocol's native completion-handler requirements rather than the
    // Swift async overlays. The async-to-ObjC thunk completes on a cooperative
    // executor even when the async body is MainActor-isolated; UIKit then runs
    // state restoration off-main and aborts when a notification is tapped.
    // Calling the original completion block *inside* DispatchQueue.main keeps
    // both our state mutation and UIKit's synchronous completion work on main.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let category = notification.request.content.categoryIdentifier
        let options: UNNotificationPresentationOptions
        if category == AppNotificationCategory.morningSleep {
            // When already foregrounded, the coordinator presents the native
            // morning sheet. Avoid showing a duplicate banner above it.
            options = []
        } else {
            // The DEBUG sleep mock intentionally uses a separate category so the
            // complete banner-tap-card path can be rehearsed without backgrounding.
            options = [.banner, .sound]
        }
        DispatchQueue.main.async {
            completionHandler(options)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let route = AppNotificationRoute(
            category: content.categoryIdentifier,
            wakeDayKey: content.userInfo[AppNotificationCategory.wakeDayUserInfoKey] as? String
        )
        dispatch(route, completionHandler: completionHandler)
    }

    /// Kept internal so the regression suite can invoke the exact queue hop
    /// without manufacturing private `UNNotificationResponse` instances.
    nonisolated func dispatch(
        _ route: AppNotificationRoute,
        completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.open(route)
            completionHandler()
        }
    }

    private func open(_ route: AppNotificationRoute) {
        switch route {
        case .stress:
            onStressOpened?()
        case .achievement:
            onAchievementOpened?()
        case let .morningSleep(wakeDayKey, isMock):
            onMorningSleepOpened?(wakeDayKey, isMock)
        case .none:
            break
        }
    }
}

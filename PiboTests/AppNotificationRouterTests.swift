import Dispatch
import Foundation
import Testing
import UserNotifications
@testable import Pibo

@MainActor
@Suite(.serialized)
struct AppNotificationRouterTests {
    @Test func foregroundArrivalNeverDuplicatesForestAchievementOrMorningFeedback() {
        for category in [AppNotificationCategory.workoutCompleted, AppNotificationCategory.achievement,
                         AppNotificationCategory.morningSleep] {
            #expect(AppNotificationRouter.foregroundOptions(category: category, identifier: "test").isEmpty)
        }
        #expect(AppNotificationRouter.foregroundOptions(
            category: AppNotificationCategory.stress, identifier: "test", stressPushEnabled: false).isEmpty)
        for identifier in ["pibo.bo.maturity", "pibo.bo.first-ripe"] {
            #expect(AppNotificationRouter.foregroundOptions(category: "", identifier: identifier).isEmpty)
        }
        for category in [AppNotificationCategory.stress, AppNotificationCategory.morningSleepMock, "test"] {
            #expect(AppNotificationRouter.foregroundOptions(category: category, identifier: "test") == [.banner, .sound])
        }
    }

    @Test func categoriesResolveToTheirDestinations() {
        #expect(AppNotificationRoute(
            category: AppNotificationCategory.stress,
            wakeDayKey: nil
        ) == .stress(dayTimestamp: nil))
        #expect(AppNotificationRoute(
            category: AppNotificationCategory.stress,
            wakeDayKey: nil,
            stressDay: 1700000000.0
        ) == .stress(dayTimestamp: 1700000000.0))
        #expect(AppNotificationRoute(
            category: AppNotificationCategory.workoutCompleted,
            wakeDayKey: nil
        ) == .achievement)
        #expect(AppNotificationRoute(
            category: AppNotificationCategory.achievement,
            wakeDayKey: nil
        ) == .achievement)
        #expect(AppNotificationRoute(
            category: AppNotificationCategory.morningSleep,
            wakeDayKey: "2026-08-03"
        ) == .morningSleep(wakeDayKey: "2026-08-03", isMock: false))
        #expect(AppNotificationRoute(
            category: AppNotificationCategory.morningSleepMock,
            wakeDayKey: "2026-08-03"
        ) == .morningSleep(wakeDayKey: "2026-08-03", isMock: true))
        #expect(AppNotificationRoute(category: "unknown", wakeDayKey: nil) == .none)
    }

    @Test func responseRouteAndSystemCompletionReturnToMainThread() async {
        let router = AppNotificationRouter.shared
        var routeRanOnMain = false
        router.onStressOpened = { _ in
            routeRanOnMain = Thread.isMainThread
        }
        defer { router.onStressOpened = nil }

        let threads = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let delegateArrivedOnMain = Thread.isMainThread
                router.dispatch(.stress(dayTimestamp: nil)) {
                    continuation.resume(returning: (
                        delegateArrivedOnMain,
                        Thread.isMainThread
                    ))
                }
            }
        }

        #expect(threads.0 == false)
        #expect(routeRanOnMain)
        #expect(threads.1)
    }
}

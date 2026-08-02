import Dispatch
import Foundation
import Testing
@testable import Pibo

@MainActor
@Suite(.serialized)
struct AppNotificationRouterTests {
    @Test func categoriesResolveToTheirDestinations() {
        #expect(AppNotificationRoute(
            category: AppNotificationCategory.stress,
            wakeDayKey: nil
        ) == .stress)
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
        router.onStressOpened = {
            routeRanOnMain = Thread.isMainThread
        }
        defer { router.onStressOpened = nil }

        let threads = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let delegateArrivedOnMain = Thread.isMainThread
                router.dispatch(.stress) {
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

import Foundation
import Testing
import UserNotifications
@testable import Pibo

@MainActor
struct StressNotificationLifecycleTests {
    private final class Center: StressNotificationScheduling {
        var requests: [UNNotificationRequest] = []
        var beforeStatusReturn: (() -> Void)?
        var afterAdd: (() -> Void)?
        func stressSettings() async -> StressNotificationSettings {
            beforeStatusReturn?()
            return .init(status: .authorized, alertsEnabled: true)
        }
        func stressRequestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
        func stressAdd(_ request: UNNotificationRequest) async throws { requests.append(request); afterAdd?() }
        func stressWithdraw(_ identifier: String) { requests.removeAll { $0.identifier == identifier } }
    }

    @Test(arguments: [false, true])
    func disableInvalidatesBothAuthorizationAndSystemPublicationWaits(duringAdd: Bool) async throws {
        let key = "StressNotificationLifecycleTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        defaults.set(true, forKey: "pibo.stress.push.enabled.v1")
        let noon = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12)))
        let center = Center()
        let notifier = StressNotifier(notifications: center, preferences: defaults, deliveryDefaults: defaults,
                                      clock: { noon })
        if duringAdd { center.afterAdd = { notifier.pushEnabled = false } }
        else { center.beforeStatusReturn = { notifier.pushEnabled = false } }
        #expect(await notifier.maybeNotify(level: .notice, rmssd: 30) == false)
        #expect(center.requests.isEmpty)
        center.beforeStatusReturn = nil; center.afterAdd = nil
        notifier.pushEnabled = true
        #expect(await notifier.maybeNotify(level: .notice, rmssd: 30))
        #expect(await notifier.maybeNotify(level: .overload, rmssd: 20) == false)
        #expect(center.requests.count == 1, "an aborted add must not consume the daily reminder")
    }
}

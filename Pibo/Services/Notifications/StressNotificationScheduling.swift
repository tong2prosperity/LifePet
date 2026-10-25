import UserNotifications

struct StressNotificationSettings {
    var status: UNAuthorizationStatus
    var alertsEnabled: Bool
}

@MainActor
protocol StressNotificationScheduling: AnyObject {
    func stressSettings() async -> StressNotificationSettings
    func stressRequestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func stressAdd(_ request: UNNotificationRequest) async throws
    func stressWithdraw(_ identifier: String)
}

@MainActor
final class SystemStressNotificationCenter: StressNotificationScheduling {
    private let center = UNUserNotificationCenter.current()
    func stressSettings() async -> StressNotificationSettings {
        let settings = await center.notificationSettings()
        return .init(status: settings.authorizationStatus, alertsEnabled: settings.alertSetting == .enabled)
    }
    func stressRequestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }
    func stressAdd(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func stressWithdraw(_ identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

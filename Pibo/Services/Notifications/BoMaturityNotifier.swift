import Foundation
import UserNotifications
import UIKit
import os

@MainActor
protocol BoMaturityNotificationCenter {
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func withdraw()
}

@MainActor
private final class SystemBoMaturityNotificationCenter: BoMaturityNotificationCenter {
    private let center = UNUserNotificationCenter.current()
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func withdraw() {
        let ids = [BoMaturityNotifier.requestID, "pibo.bo.first-ripe"]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}

/// Decisions 048/049/055: existing permission only, no first-bo banner, and no
/// banner over the foreground forest. Collection invalidates in-flight delivery.
@MainActor
final class BoMaturityNotifier {
    static let shared = BoMaturityNotifier()
    static let requestID = "pibo.bo.maturity"
    private static let deliveredKey = "pibo.bo.maturity.delivered.v1"
    private let center: any BoMaturityNotificationCenter
    private let defaults: UserDefaults
    private let isBackground: @MainActor () -> Bool
    private var latest = ""
    private var generation = 0
    private var publication: Task<Void, Never>?

    init(center: (any BoMaturityNotificationCenter)? = nil,
         defaults: UserDefaults = .standard,
         isBackground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .background }) {
        self.center = center ?? SystemBoMaturityNotificationCenter()
        self.defaults = defaults
        self.isBackground = isBackground
    }

    func reconcile(ripe: Bool, cycle: Int) {
        let key = ripe ? String(cycle) : ""
        if !ripe || cycle <= 1 || !isBackground() {
            generation += 1
            latest = key
            if ripe { defaults.set(key, forKey: Self.deliveredKey) }
            center.withdraw()
            return
        }
        guard key != latest else { return }
        latest = key
        generation += 1
        let expected = generation
        publication = Task { await publish(key: key, generation: expected) }
    }

    func collected(nextRipe: Bool, nextCycle: Int) {
        generation += 1
        latest = nextRipe ? String(nextCycle) : ""
        defaults.set(latest, forKey: Self.deliveredKey)
        center.withdraw()
    }

    func waitForPending() async { await publication?.value }

    private func publish(key: String, generation: Int) async {
        guard defaults.string(forKey: Self.deliveredKey) != key else { return }
        let authorization = await center.authorizationStatus()
        guard generation == self.generation, isBackground() else { return }
        switch authorization {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }
        let content = UNMutableNotificationContent()
        content.title = AppLocalization.text("bo 已经充满了")
        content.body = AppLocalization.text("能量还在 Pibo 头顶。回来轻轻向上拉，把它收进 bo 余额。")
        content.sound = .default
        content.threadIdentifier = "pibo.bo.ripe"
        do {
            try await center.add(UNNotificationRequest(identifier: Self.requestID, content: content, trigger: nil))
            guard generation == self.generation, isBackground() else {
                center.withdraw()
                return
            }
            defaults.set(key, forKey: Self.deliveredKey)
            LPLog.bo.notice("maturity notification delivered cycle=\(key, privacy: .public)")
        } catch {
            LPLog.bo.error("maturity notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

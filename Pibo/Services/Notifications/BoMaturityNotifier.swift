import Foundation
import UserNotifications
import os

/// Decision 048: one local reminder per real maturity cycle.
///
/// Delivery follows the confirmed ledger fact only — never an estimated ripen
/// time. A cycle is identified by the next collection ordinal
/// (`lifetimeCollected + 1`), so a reminder is posted once per unit, withdrawn
/// on collection, and never re-sent for the same cycle after a relaunch.
/// Tapping it simply opens the forest; nothing is collected automatically.
@MainActor
final class BoMaturityNotifier {
    static let shared = BoMaturityNotifier()
    static let requestID = "pibo.bo.maturity"
    private static let deliveredKey = "pibo.bo.maturity.delivered.v1"

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private var latest = ""
    private var generation = 0

    init(center: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
    }

    func reconcile(ripe: Bool, cycle: Int) {
        let key = ripe ? String(cycle) : ""
        guard key != latest else { return }
        latest = key
        generation += 1
        guard ripe else {
            withdraw()
            return
        }
        let generation = generation
        Task { await publish(key: key, generation: generation) }
    }

    /// Collection happened; an immediate refill from the reserve is already on
    /// screen, so its cycle counts as seen.
    func collected(nextRipe: Bool, nextCycle: Int) {
        generation += 1
        latest = nextRipe ? String(nextCycle) : ""
        defaults.set(latest, forKey: Self.deliveredKey)
        withdraw()
    }

    private func withdraw() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.requestID])
    }

    private func publish(key: String, generation: Int) async {
        guard defaults.string(forKey: Self.deliveredKey) != key else { return }
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        guard generation == self.generation else { return }
        switch settings.authorizationStatus {
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
            guard generation == self.generation else {
                withdraw()
                return
            }
            defaults.set(key, forKey: Self.deliveredKey)
            LPLog.bo.notice("maturity notification delivered cycle=\(key, privacy: .public)")
        } catch {
            LPLog.bo.error("maturity notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

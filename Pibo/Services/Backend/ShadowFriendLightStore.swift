import Foundation
import Observation

struct PendingShadowFriendLight: Codable, Equatable, Sendable, Identifiable {
    static let ttl: TimeInterval = 24 * 60 * 60

    let schemaVersion: Int
    let id: String
    let senderName: String
    let receivedAt: Date
    let expiresAt: Date

    init?(id: String, senderName: String, receivedAt: Date) {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        schemaVersion = 1
        self.id = id
        self.senderName = Self.normalizedName(senderName)
        self.receivedAt = receivedAt
        expiresAt = receivedAt.addingTimeInterval(Self.ttl)
    }

    var message: String { "\(senderName)给你送来一束光" }
    func isExpired(at date: Date) -> Bool { date >= expiresAt }

    private static func normalizedName(_ value: String) -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((name.isEmpty ? "好友" : name).prefix(24))
    }
}

@MainActor
@Observable
final class ShadowFriendLightStore {
    private(set) var pending: PendingShadowFriendLight?
    private(set) var revision = 0

    @ObservationIgnored var onConsumed: ((String) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var activeUserID = ""

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func activate(userID: String, now: Date = .now) {
        activeUserID = userID
        guard let data = defaults.data(forKey: key),
              let value = try? JSONCoding.decoder.decode(PendingShadowFriendLight.self, from: data),
              value.schemaVersion == 1,
              !value.isExpired(at: now) else {
            pending = nil
            defaults.removeObject(forKey: key)
            revision += 1
            return
        }
        pending = value
        revision += 1
    }

    func deactivate() {
        activeUserID = ""
        pending = nil
        revision += 1
    }

    @discardableResult
    func enqueue(id: String, senderName: String, receivedAt: Date = .now) -> Bool {
        guard !activeUserID.isEmpty,
              let value = PendingShadowFriendLight(
                  id: id,
                  senderName: senderName,
                  receivedAt: receivedAt
              ) else { return false }
        pending = value
        persist()
        revision += 1
        return true
    }

    func presentable(now: Date = .now) -> PendingShadowFriendLight? {
        guard let pending else { return nil }
        guard pending.schemaVersion == 1, !pending.isExpired(at: now) else {
            clear()
            return nil
        }
        return pending
    }

    func consume(id: String) {
        guard pending?.id == id else { return }
        clear()
        onConsumed?(id)
    }

    private var key: String { "pibo.shadow.light.account.\(activeUserID).v1" }

    private func persist() {
        guard !activeUserID.isEmpty,
              let pending,
              let data = try? JSONCoding.encoder.encode(pending) else { return }
        defaults.set(data, forKey: key)
    }

    private func clear() {
        pending = nil
        if !activeUserID.isEmpty { defaults.removeObject(forKey: key) }
        revision += 1
    }
}

import Foundation
import Security

/// Keychain-backed storage for the auth token pair. The Keychain is the single
/// source of truth and is thread-safe, so this is a stateless value type whose
/// methods read/write directly — no in-memory caching to keep in sync.
///
/// access(15m) / refresh(7d): on every economy request the client attaches the
/// access token; a 401 triggers a refresh using the refresh token (which the
/// server rotates — always persist the new pair).
struct TokenStore: Sendable {
    static let shared = TokenStore()

    private let service = "fun.tiebao.co.Pibo.auth"
    private let accessKey = "access_token"
    private let refreshKey = "refresh_token"
    private let userIDKey = "user_id"

    var accessToken: String? { read(accessKey) }
    var refreshToken: String? { read(refreshKey) }
    var userId: String? { read(userIDKey) }
    var isLoggedIn: Bool { accessToken != nil && refreshToken != nil }

    func save(access: String, refresh: String, userId: String? = nil) {
        write(accessKey, access)
        write(refreshKey, refresh)
        if let userId, !userId.isEmpty { write(userIDKey, userId) }
    }

    func clear() {
        delete(accessKey)
        delete(refreshKey)
        delete(userIDKey)
    }

    // MARK: - Keychain primitives

    private func write(_ key: String, _ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attrs) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

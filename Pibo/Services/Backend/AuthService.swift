import Foundation
import os

/// App-facing authentication state + flows. Owns the login lifecycle and the
/// observable phase the UI reacts to; delegates transport to `APIClient` and
/// token persistence to `TokenStore`.
///
/// Login is passwordless phone OTP (the server auto-creates the user on first
/// code-login), matching the "必须登录、手机号+短信验证码" MVP decision.
@MainActor
@Observable
final class AuthService {
    enum Phase: Equatable {
        case loggedOut
        case codeSent(phone: String)
        case loggedIn
    }

    private(set) var phase: Phase
    private(set) var userId: String?
    private(set) var isBusy = false
    private(set) var lastError: APIError?

    private let api: APIClient
    private let tokens: TokenStore
    @ObservationIgnored var onSessionChanged: ((String?) -> Void)?

    init(api: APIClient = .shared, tokens: TokenStore = .shared) {
        self.api = api
        self.tokens = tokens
        self.phase = tokens.isLoggedIn ? .loggedIn : .loggedOut
        self.userId = tokens.userId
    }

    /// Restores the account identity after a cold launch. Tokens are opaque;
    /// `/auth/me` is authoritative, while the cached id keeps account-scoped
    /// Shadow state available during a temporary transport outage.
    @discardableResult
    func restoreSession() async -> Bool {
        guard tokens.isLoggedIn else {
            publishLoggedOut()
            return false
        }
        let cachedUserID = tokens.userId
        if let cachedUserID { publishLoggedIn(cachedUserID) }
        do {
            let user: AuthUserInfo = try await api.get("/auth/me", authed: true)
            if let access = tokens.accessToken, let refresh = tokens.refreshToken {
                tokens.save(access: access, refresh: refresh, userId: user.userId)
            }
            publishLoggedIn(user.userId)
            Analytics.setUser(user.userId)
            return true
        } catch {
            if tokens.isLoggedIn, cachedUserID != nil { return true }
            publishLoggedOut()
            return false
        }
    }

    /// Step 1 — request an SMS code. On success the UI advances to code entry.
    @discardableResult
    func startLogin(phone: String) async -> Bool {
        isBusy = true; lastError = nil
        defer { isBusy = false }
        do {
            try await api.postNoContent("/auth/code-login/start",
                                        body: CodeLoginStartRequest(phoneNumber: phone),
                                        authed: false)
            phase = .codeSent(phone: phone)
            return true
        } catch {
            lastError = .from(error)
            LPLog.auth.error("startLogin failed: \(String(describing: error))")
            return false
        }
    }

    /// Step 2 — verify the code, persist the token pair, and land logged-in.
    @discardableResult
    func completeLogin(phone: String, code: String) async -> Bool {
        isBusy = true; lastError = nil
        defer { isBusy = false }
        do {
            let result: AuthResult = try await api.post("/auth/code-login/complete",
                                                        body: CodeLoginCompleteRequest(phoneNumber: phone, code: code),
                                                        authed: false)
            tokens.save(
                access: result.tokens.accessToken,
                refresh: result.tokens.refreshToken,
                userId: result.user.userId
            )
            publishLoggedIn(result.user.userId)
            LPLog.auth.notice("logged in as \(result.user.userId, privacy: .public)")
            Analytics.setUser(result.user.userId)
            Analytics.track(.login)
            return true
        } catch {
            lastError = .from(error)
            LPLog.auth.error("completeLogin failed: \(String(describing: error))")
            return false
        }
    }

    /// Revoke the access token server-side (best-effort) and drop local tokens.
    func logout() async {
        try? await api.postNoContent("/auth/logout", body: EmptyBody(), authed: true)
        await api.clearTokens()
        publishLoggedOut()
        Analytics.track(.logout)
        Analytics.setUser(nil)
    }

    /// Back to the phone-entry step (e.g. user mistyped the number).
    func resetToPhoneEntry() {
        phase = .loggedOut
        lastError = nil
    }

    private func publishLoggedIn(_ userID: String) {
        userId = userID
        phase = .loggedIn
        onSessionChanged?(userID)
    }

    private func publishLoggedOut() {
        userId = nil
        phase = .loggedOut
        onSessionChanged?(nil)
    }
}

/// Empty JSON body for endpoints that take none.
private struct EmptyBody: Encodable {}

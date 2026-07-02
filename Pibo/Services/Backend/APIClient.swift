import Foundation
import os

/// Low-level HTTP/JSON client for pibo-server. An `actor` so token refresh is
/// serialized: concurrent 401s share a single refresh instead of racing (which
/// would make the second caller present an already-rotated, now-revoked refresh
/// token and get logged out).
///
/// Responsibilities: build requests, attach the bearer token, decode JSON,
/// map server errors, and transparently refresh+retry once on a 401. It does
/// NOT own auth UI state — `AuthService` does.
actor APIClient {
    static let shared = APIClient()

    private let config: APIConfig
    private let tokens: TokenStore
    private let session: URLSession
    private let log = Logger(subsystem: "fun.tiebao.co.Pibo", category: "api")

    /// In-flight refresh, shared by all callers that 401 concurrently.
    private var refreshInFlight: Task<Void, Error>?

    init(config: APIConfig = .shared, tokens: TokenStore = .shared, session: URLSession = .shared) {
        self.config = config
        self.tokens = tokens
        self.session = session
    }

    var isLoggedIn: Bool { tokens.isLoggedIn }

    // MARK: - Verbs

    func get<T: Decodable>(_ path: String, authed: Bool) async throws -> T {
        let data = try await requestData(path: path, method: "GET", bodyData: nil, authed: authed)
        return try decode(data)
    }

    /// `timeout` overrides the default 60s request timeout — needed for the slow
    /// VLM food-recognition call (kimi-k2.6 can take 1–2 min).
    func post<B: Encodable, T: Decodable>(_ path: String, body: B, authed: Bool,
                                          timeout: TimeInterval? = nil) async throws -> T {
        let bodyData = try encode(body)
        let data = try await requestData(path: path, method: "POST", bodyData: bodyData, authed: authed, timeout: timeout)
        return try decode(data)
    }

    func postNoContent<B: Encodable>(_ path: String, body: B, authed: Bool) async throws {
        let bodyData = try encode(body)
        _ = try await requestData(path: path, method: "POST", bodyData: bodyData, authed: authed)
    }

    /// Drops the local token pair (logout / unrecoverable 401).
    func clearTokens() { tokens.clear() }

    // MARK: - Core request with 401 refresh-and-retry

    private func requestData(path: String, method: String, bodyData: Data?, authed: Bool, isRetry: Bool = false, timeout: TimeInterval? = nil) async throws -> Data {
        let bearer = authed ? tokens.accessToken : nil
        let (data, http) = try await perform(path: path, method: method, bodyData: bodyData, bearer: bearer, timeout: timeout)

        if http.statusCode == 401 && authed && !isRetry && tokens.refreshToken != nil {
            try await refreshTokens()
            return try await requestData(path: path, method: method, bodyData: bodyData, authed: true, isRetry: true, timeout: timeout)
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                tokens.clear()
                throw APIError.unauthorized
            }
            if let body = try? JSONCoding.decoder.decode(ServerErrorBody.self, from: data) {
                throw APIError.server(status: http.statusCode, code: body.error.code, message: body.error.message)
            }
            throw APIError.unexpectedStatus(http.statusCode)
        }
        return data
    }

    private func perform(path: String, method: String, bodyData: Data?, bearer: String?, timeout: TimeInterval? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: config.baseURL) else {
            throw APIError.invalidRequest
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let timeout { req.timeoutInterval = timeout }
        if let bodyData {
            req.httpBody = bodyData
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearer {
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw APIError.transport("no HTTP response")
            }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    // MARK: - Token refresh (deduped)

    private func refreshTokens() async throws {
        if let existing = refreshInFlight {
            try await existing.value
            return
        }
        let task = Task { [self] in try await doRefresh() }
        refreshInFlight = task
        defer { refreshInFlight = nil }
        try await task.value
    }

    private func doRefresh() async throws {
        guard let refresh = tokens.refreshToken else {
            tokens.clear()
            throw APIError.unauthorized
        }
        do {
            let pair: TokenPair = try await post("/auth/token/refresh",
                                                 body: RefreshRequest(refreshToken: refresh),
                                                 authed: false)
            tokens.save(access: pair.accessToken, refresh: pair.refreshToken)
            log.debug("token refreshed")
        } catch {
            tokens.clear()
            throw APIError.unauthorized
        }
    }

    // MARK: - Coding

    private func encode<B: Encodable>(_ body: B) throws -> Data {
        do { return try JSONCoding.encoder.encode(body) }
        catch { throw APIError.invalidRequest }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONCoding.decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(String(describing: error)) }
    }
}

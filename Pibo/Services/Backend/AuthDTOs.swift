import Foundation

/// Wire types for the auth endpoints. Field names are camelCase; the shared
/// coders convert to/from the server's snake_case (`phone_number`, etc.).

struct CodeLoginStartRequest: Encodable {
    let phoneNumber: String
}

struct CodeLoginCompleteRequest: Encodable {
    let phoneNumber: String
    let code: String
}

struct RefreshRequest: Encodable {
    let refreshToken: String
}

struct TokenPair: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
}

struct AuthUserInfo: Decodable, Sendable {
    let userId: String
    let roles: [String]
    /// RFC3339 string (auth emits no fractional seconds here); kept as a string
    /// since the app doesn't need it as a Date.
    let created: String
}

struct AuthResult: Decodable, Sendable {
    let user: AuthUserInfo
    let tokens: TokenPair
}

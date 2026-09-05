import Foundation

// Wire types for /api/v1/membership/* (Apple IAP verify + status).
// camelCase here ⇄ snake_case on the wire via `JSONCoding`.

/// POST /api/v1/membership/verify — carries a StoreKit 2
/// `Transaction.jwsRepresentation` for server-side verification + persistence.
struct MembershipVerifyRequest: Encodable, Sendable {
    let provider: String
    let signedTransaction: String

    init(provider: String = "apple_iap", signedTransaction: String) {
        self.provider = provider
        self.signedTransaction = signedTransaction
    }
}

struct MembershipAppAccountTokenRequest: Encodable, Sendable {}

struct MembershipAppAccountTokenResponse: Decodable, Sendable {
    let appAccountToken: String
    let serverTime: Date
}

/// Response of both POST /verify and GET /status — the server's authoritative
/// view of the user's membership.
struct MembershipStatusDTO: Decodable, Sendable {
    let isActive: Bool
    let provider: String?
    let plan: String?          // monthly / yearly
    let productId: String?
    let expiresAt: Date?
    let environment: String?   // Production / Sandbox / Xcode
    let signatureVerified: Bool
    let serverTime: Date
}

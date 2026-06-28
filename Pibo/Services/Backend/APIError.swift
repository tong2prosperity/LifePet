import Foundation

/// Errors surfaced by the backend layer. The server encodes failures as
/// `{"error":{"code","message"}}`; `.server` carries the decoded pair.
enum APIError: Error, Equatable {
    /// Couldn't build the request (bad URL/body).
    case invalidRequest
    /// Transport failure (offline, timeout, DNS).
    case transport(String)
    /// Non-2xx with a decoded server error body.
    case server(status: Int, code: String, message: String)
    /// Non-2xx without a parseable body.
    case unexpectedStatus(Int)
    /// Response body failed to decode into the expected type.
    case decoding(String)
    /// 401 that survived a refresh attempt — the caller must re-login.
    case unauthorized
}

extension APIError {
    /// A user-facing message in the 魔丸 register's neighbour — terse, not blamey.
    var displayMessage: String {
        switch self {
        case .invalidRequest: return "请求出错了"
        case .transport: return "连不上 Pibo 的世界…"
        case let .server(_, _, message): return message
        case .unexpectedStatus: return "服务器打了个盹"
        case .decoding: return "数据看不懂啵"
        case .unauthorized: return "需要重新登录"
        }
    }
}

extension APIError {
    /// Coerces any thrown error into an APIError (network layer already throws
    /// APIError; this catches the stray non-APIError).
    static func from(_ error: Error) -> APIError {
        (error as? APIError) ?? .transport(error.localizedDescription)
    }
}

/// Wire shape of a server error body.
struct ServerErrorBody: Decodable {
    struct Inner: Decodable {
        let code: String
        let message: String
    }
    let error: Inner
}

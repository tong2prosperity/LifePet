import Foundation

/// Backend connection settings for pibo-server (auth + economy).
///
/// The base URL resolves in this order:
/// 1. `PIBO_API_BASE_URL` in Info.plist (set per build configuration), else
/// 2. the shared test deployment `https://test-api.navi-bot.com/pibo/v1` — the
///    same base HarmonyOS packages. Nginx strips the `/pibo/v1` prefix, so request
///    paths keep the server's own `/auth/...` and `/api/v1/...` contract.
struct APIConfig: Sendable {
    let baseURL: URL

    /// 服务端 economy 同步暂不开放：bo 账本在本机计算（2026-09-15 用户决定，与
    /// HarmonyOS `BACKEND_ECONOMY_SYNC_ENABLED = false` 对齐）。客户端同步代码保留。
    static let economySyncEnabled = false

    /// Joins a server path onto the base without dropping the base's own path
    /// prefix (`URL(string:relativeTo:)` would resolve `/api/...` against the host).
    func url(for path: String) -> URL? {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + (path.hasPrefix("/") ? path : "/" + path))
    }

    static let shared = APIConfig()

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    init() {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "PIBO_API_BASE_URL") as? String,
           let url = URL(string: raw), !raw.isEmpty {
            baseURL = url
            return
        }
        baseURL = URL(string: "https://test-api.navi-bot.com/pibo/v1")!
    }
}

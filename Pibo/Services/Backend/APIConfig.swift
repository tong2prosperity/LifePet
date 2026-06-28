import Foundation

/// Backend connection settings for pibo-server (auth + economy).
///
/// The base URL resolves in this order:
/// 1. `PIBO_API_BASE_URL` in Info.plist (set per build configuration), else
/// 2. the DEBUG default `http://localhost:8080` (run pibo-server locally and
///    the simulator reaches it via localhost), else
/// 3. the release placeholder — replace once the server is deployed.
struct APIConfig: Sendable {
    let baseURL: URL

    static let shared = APIConfig()

    init() {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "PIBO_API_BASE_URL") as? String,
           let url = URL(string: raw), !raw.isEmpty {
            baseURL = url
            return
        }
        #if DEBUG
        baseURL = URL(string: "http://localhost:8080")!
        #else
        baseURL = URL(string: "https://api.pibo.example.com")!
        #endif
    }
}

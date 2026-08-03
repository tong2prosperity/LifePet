import Foundation
import os
import DataSneaker

/// Pibo 打点 — the app's single seam onto the DataSneaker SDK. Every event
/// name and the tracking endpoint live here; call sites use
/// `Analytics.track(.pat, ["reaction": "spoke"])` and never import the SDK.
///
/// 统一后台打点 URL resolution:
/// 1. `PIBO_ANALYTICS_URL` in the partial `Pibo-Info.plist` at the repo root
///    (currently empty — fill in once the DataSneaker server is deployed), else
/// 2. unset/empty → the SDK is never configured and every call is a no-op.
///
/// Performance: `track` is non-blocking on the calling thread (one lock read +
/// an AsyncStream yield inside the SDK); batching/networking/persistence run on
/// the SDK's pipeline actor. Never add tracking to per-frame paths (drag, pan,
/// SpriteKit update) — instrument discrete user actions only.
enum Analytics {
    /// Stable event names (`event_type` in ClickHouse). Dashboards and funnels
    /// key off these strings — treat renames as a data migration.
    enum Event: String {
        case appLaunch = "app_launch"
        case appForeground = "app_foreground"
        case appBackground = "app_background"
        case healthAuth = "health_auth"
        case pat
        case pluck
        case energyCollected = "energy_collected"
        /// 打开兑换道具面板（首页左上角 bo 存量）。
        case boPanelOpen = "bo_panel_open"
        /// 解锁一件森林物件，扣掉 bo。
        case boUnlock = "bo_unlock"
        /// 亲手点亮物件上的一盏灯（铃兰灯的一个铃铛）。**不产生任何收益** ——
        /// 决定 013 明令不给这件事挂数值奖励，这条打点只是想知道有没有人点。
        case ornamentLight = "ornament_light"
        case cameraOpen = "camera_open"
        case photoSaved = "photo_saved"
        case mealRecognized = "meal_recognized"
        case walkDoodleStart = "walk_doodle_start"
        case walkDoodleSaved = "walk_doodle_saved"
        case gamesOpen = "games_open"
        case miniGameStart = "mini_game_start"
        case miniGameFinish = "mini_game_finish"
        case historyOpen = "history_open"
        case settingsOpen = "settings_open"
        case soundscapeSettingChange = "soundscape_setting_change"
        case themeChange = "theme_change"
        case membershipOpen = "membership_open"
        case purchase
        case purchaseRestore = "purchase_restore"
        case login
        case logout
        case reset
    }

    /// Start the SDK once at launch. With no URL configured this logs and
    /// returns — the whole layer stays inert.
    nonisolated static func start() {
        guard let url = configuredURL else {
            LPLog.app.notice("analytics off — PIBO_ANALYTICS_URL not set")
            return
        }
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        DataSneaker.configure(DataSneakerConfiguration(serverURL: url, debugLogging: debug))
        LPLog.app.notice("analytics → \(url.absoluteString, privacy: .public)")
    }

    nonisolated static func track(_ event: Event,
                                  screen: String? = nil,
                                  _ properties: [String: AnalyticsValue]? = nil) {
        DataSneaker.track(event.rawValue,
                          screenName: screen,
                          properties: properties?.mapValues(\.json))
    }

    /// Attribute events to the logged-in user (pass nil on logout). On login
    /// the device's anonymous history is merged server-side (identity alias).
    nonisolated static func setUser(_ id: String?) {
        DataSneaker.setUserID(id, aliasDevice: id != nil)
    }

    private nonisolated static var configuredURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "PIBO_ANALYTICS_URL") as? String,
              !raw.isEmpty,
              let url = URL(string: raw) else { return nil }
        return url
    }
}

/// In-module property value so call sites don't need `import DataSneaker`
/// (member-import-visibility would otherwise require it for `JSONValue`'s
/// literal conformances). Flat scalars only — event properties stay flat.
nonisolated enum AnalyticsValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
                                 ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }

    nonisolated var json: JSONValue {
        switch self {
        case .string(let value): .string(value)
        case .int(let value): .int(value)
        case .double(let value): .double(value)
        case .bool(let value): .bool(value)
        }
    }
}

import Foundation
import os
import DataSneaker

/// Pibo 打点 — the app's single seam onto the DataSneaker SDK. Every event
/// name and the tracking endpoint live here; call sites use
/// `Analytics.track(.pat, ["reaction": "spoke"])` and never import the SDK.
///
/// 统一后台打点 URL resolution:
/// 1. `PIBO_ANALYTICS_URL` in the partial `Pibo-Info.plist` at the repo root
///    (same deployment and event contract as HarmonyOS), else
/// 2. unset/empty → the SDK is never configured and every call is a no-op.
///
/// Performance: `track` is non-blocking on the calling thread (one lock read +
/// an AsyncStream yield inside the SDK); batching/networking/persistence run on
/// the SDK's pipeline actor. Never add tracking to per-frame paths (drag, pan,
/// SpriteKit update) — instrument discrete user actions only.
enum Analytics {
    nonisolated static let enabledKey = "pibo.analytics.enabled"
    private nonisolated static let consent = OSAllocatedUnfairLock(initialState: true)
    /// Stable event names (`event_type` in ClickHouse). Dashboards and funnels
    /// key off these strings — treat renames as a data migration.
    enum Event: String {
        case appLaunch = "app_launch"
        case appForeground = "app_foreground"
        case appBackground = "app_background"
        case healthAuth = "health_auth"
        case onboardingCheckpoint = "onboarding_checkpoint"
        case onboardingCompleted = "onboarding_completed"
        case onboardingSkipped = "onboarding_skipped"
        case storyConnectionResponded = "story_connection_responded"
        case storyConnectionAccepted = "story_connection_accepted"
        case storyRecoveryOpened = "story_recovery_opened"
        case storyEventAdvanced = "story_event_advanced"
        case pat
        case pluck
        case energyCollected = "energy_collected"
        /// 打开共同物件面板（首页左上角 bo 存量）。
        case boPanelOpen = "bo_panel_open"
        /// Decision 048: a ripe container pulled into the spendable balance.
        case boCollect = "bo_collect"
        /// Decision 054 companion prompts. Custom reply text is never tracked.
        case companionPromptShown = "companion_prompt_shown"
        case companionPromptAnswered = "companion_prompt_answered"
        case companionPromptIgnored = "companion_prompt_ignored"
        case companionEchoShown = "companion_echo_shown"
        /// 解锁一件森林物件，扣掉 bo。
        case boUnlock = "bo_unlock"
        case boUnlockItemSelect = "bo_unlock_item_select"
        case boUnlockPlacementPreview = "bo_unlock_placement_preview"
        case boUnlockAttempt = "bo_unlock_attempt"
        case boUnlockFailed = "bo_unlock_failed"
        case boUnlockReturn = "bo_unlock_return"
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
        case accountDeleted = "account_deleted"
        case reset
        case levelUp = "level_up"
        case wishCompleted = "wish_completed"
        case growthSheetOpen = "growth_sheet_open"
        case decorPlaced = "decor_placed"
        case shootingStarCaught = "shooting_star_caught"
        case deviceShake = "device_shake"
        case mealStickerTap = "meal_sticker_tap"
        case mealMatInvite = "meal_mat_invite"
        case disguiseStart = "disguise_start"
        case disguiseFound = "disguise_found"
        case decoyTapped = "decoy_tapped"
        case findDisplayToggle = "find_display_toggle"
        case decorPurchased = "decor_purchased"
    }

    /// Start the SDK once at launch. With no URL configured this logs and
    /// returns — the whole layer stays inert.
    nonisolated static func start() {
        let enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        consent.withLock { $0 = enabled }
        guard enabled else { return }
        #if DEBUG
        // Preview/test interactions never enter production funnels by default.
        guard ProcessInfo.processInfo.arguments.contains("-PiboEnableAnalytics") else { return }
        #endif
        guard let url = configuredURL else {
            LPLog.app.notice("analytics off — PIBO_ANALYTICS_URL not set")
            return
        }
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        let key = Bundle.main.object(forInfoDictionaryKey: "PIBO_ANALYTICS_APP_KEY") as? String
        DataSneaker.configure(DataSneakerConfiguration(serverURL: url, appKey: key, debugLogging: debug))
        DataSneaker.setUserID(nil)
        LPLog.app.notice("analytics → \(url.absoluteString, privacy: .public)")
    }

    nonisolated static func track(_ event: Event,
                                  screen: String? = nil,
                                  _ properties: [String: AnalyticsValue]? = nil) {
        guard consent.withLock({ $0 }), let sanitized = sanitizedProperties(event, properties) else { return }
        DataSneaker.track(event.rawValue,
                          screenName: screen,
                          properties: sanitized.mapValues(\.json))
    }

    /// Compatibility seam for existing auth call sites. Product analytics stays anonymous.
    nonisolated static func setUser(_ id: String?) {
        // Product analytics is anonymous on both platforms; account state belongs
        // to auth, never to an identity alias in this pipeline.
    }

    nonisolated static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        consent.withLock { $0 = enabled }
        if enabled { start() }
    }

    /// nil rejects retired events; an empty map accepts an event with no properties.
    nonisolated static func sanitizedProperties(_ event: Event, _ properties: [String: AnalyticsValue]?) -> [String: AnalyticsValue]? {
        guard let keys = propertyKeys[event] else { return nil }
        return (properties ?? [:]).filter { key, value in
            guard keys.contains(key) else { return false }
            switch value {
            case .string(let text):
                return !text.isEmpty && text.utf8.count <= 64 && text.utf8.allSatisfy {
                    (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                        || [95, 46, 58, 45].contains($0)
                }
            case .double(let number): return number.isFinite
            case .int, .bool: return true
            }
        }
    }

    private nonisolated static let propertyKeys: [Event: Set<String>] = [
        .appLaunch: [], .appForeground: [], .appBackground: [], .healthAuth: ["granted"],
        .onboardingCheckpoint: ["checkpoint"], .onboardingCompleted: [], .onboardingSkipped: ["checkpoint"],
        .storyConnectionResponded: ["result"], .storyConnectionAccepted: [], .storyRecoveryOpened: [], .storyEventAdvanced: ["event"],
        .pat: [], .boCollect: [], .energyCollected: [], .boPanelOpen: [],
        .companionPromptShown: ["trigger"], .companionPromptAnswered: ["input"],
        .companionPromptIgnored: [], .companionEchoShown: [],
        .boUnlock: ["item", "ornament"], .boUnlockItemSelect: ["item", "ornament"],
        .boUnlockPlacementPreview: ["item", "ornament"], .boUnlockAttempt: ["item", "ornament", "result"],
        .boUnlockFailed: ["item", "ornament"], .boUnlockReturn: ["item", "ornament"],
        .cameraOpen: [], .photoSaved: [], .mealRecognized: ["success", "result"],
        .historyOpen: [], .settingsOpen: [], .levelUp: ["level"], .wishCompleted: ["wish"],
        .growthSheetOpen: ["trigger"], .decorPlaced: ["decor"], .shootingStarCaught: [], .deviceShake: [],
        .mealStickerTap: ["slot_index", "is_fresh"], .mealMatInvite: ["accepted"],
        .disguiseStart: ["form", "decoys"], .disguiseFound: ["form"], .decoyTapped: ["form", "index"],
        .findDisplayToggle: ["item", "action", "scene"], .decorPurchased: ["decor", "cost", "scene"],
        .soundscapeSettingChange: ["enabled"], .themeChange: ["result"], .login: ["result"], .logout: [], .reset: []
    ]

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

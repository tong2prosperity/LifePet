import Foundation
import UserNotifications
import os

/// The moment a stress reading is worth a push. Not every reading notifies —
/// only these transitions do.
enum StressAlertKind: Sendable {
    /// 注意 / 超载 — stress is elevated (escalation or a sustained re-remind).
    case elevated
    /// Back down to 正常 after having been 注意 / 超载 — the "缓过来了" beat.
    case recovered
    /// Reached 优秀 — the best tier, worth a small congratulation.
    case excellent

    /// Body copy. Tone: 傲娇不卖惨 (per Pibo spec). Elevated defers to the
    /// per-tier copy on `StressLevel`.
    func body(for level: StressLevel) -> String {
        switch self {
        case .elevated:  return level.notificationBody
        case .recovered: return "花缓过来一点了……这次先不追究你。"
        case .excellent: return "心跳稳稳的，花也精神……算你今天没白活。"
        }
    }
}

/// Fires the stress local notification — the "实时通知" half of the
/// StressWatch-style feature. Driven from `HealthDataService.postStress`, which
/// runs on every HealthKit wake (foreground *and* background delivery), so a
/// stress change can push even while the app is backgrounded.
///
/// Fires on three transitions (see `alertKind`): stress turning **elevated**
/// (注意/超载), **recovering** back to 正常, and reaching **优秀** — so the user
/// hears both the warning and the "缓过来了 / 今天不错" all-clear.
///
/// Delivery model:
/// - **Foreground** notifications are shown as banners via `AppNotificationRouter`
///   (iOS otherwise suppresses them).
/// - Authorization is requested **provisionally** at launch (quiet, no prompt),
///   so a passive user is covered without ever opening settings; toggling the
///   settings switch on upgrades to a full (audible) authorization.
/// - **Escalation** (a strictly higher tier than last alerted) bypasses the
///   normal cooldown — a worsening spike is the whole point. A sustained
///   elevated tier re-reminds on a long cadence instead of going silent.
/// - **Recovery / 优秀** are one-shot transitions off the last *alerted* tier,
///   floored only enough to dedupe the observer+reconcile race.
@MainActor
@Observable
final class StressNotifier {
    static let shared = StressNotifier()

    /// User-facing toggle (settings). Off silences pushes without revoking the
    /// system authorization. Persisted in standard defaults.
    var pushEnabled: Bool {
        didSet { UserDefaults.standard.set(pushEnabled, forKey: Self.enabledKey) }
    }

    /// Diagnostic mode: fire a notification on **every** HRV computation (not
    /// just tier transitions), carrying the raw RMSSD + tier. Bypasses all the
    /// throttle/quiet-hours logic — noisy by design, meant for verifying "每次
    /// 都在算". Sits *under* `pushEnabled` (that's still the master switch).
    var notifyEveryReading: Bool {
        didSet { UserDefaults.standard.set(notifyEveryReading, forKey: Self.everyKey) }
    }

    /// Whether the once-a-morning sleep summary may post a system banner
    /// (`MorningSleepCoordinator` reads this gate). It shares the app's single
    /// notification grant with stress alerts — turning it on requests full
    /// authorization, which also un-silences stress banners. Default on.
    var sleepSummaryPushEnabled: Bool {
        didSet { UserDefaults.standard.set(sleepSummaryPushEnabled, forKey: Self.sleepEnabledKey) }
    }

    /// System authorization state, refreshed lazily. `false` until authorized
    /// (provisional counts).
    private(set) var authorized = false

    /// Raised when the user taps a stress notification, cleared by `HomeView`
    /// once it has opened the history surface on the 压力卡.
    ///
    /// A flag rather than a counter: the destination is idempotent, so two taps
    /// arriving behind one presentation should still open it exactly once. It
    /// also has to survive a **cold** launch — the tap can arrive before
    /// `HomeView` exists, so the view checks it on appear as well as on change.
    var pendingCardOpen = false

    /// In-flight guard: `maybeNotify` has `await` suspension points between the
    /// throttle check and the state write, and two HK triggers (observer +
    /// `reconcile`) can call it concurrently for the same reading. This blocks
    /// the reentrant second call so they can't both pass the throttle.
    private var isNotifying = false

    // Persisted keys.
    private static let enabledKey = "pibo.stress.push.enabled.v1"
    private static let everyKey = "pibo.stress.push.every.v1"
    private static let sleepEnabledKey = "pibo.sleep.push.enabled.v1"
    private static let lastAtKey = "pibo.stress.push.lastAt.v1"
    private static let lastLevelKey = "pibo.stress.push.lastLevel.v1"
    /// App-Group defaults so the throttle/escalation ratchet survives a
    /// background relaunch (the process that pushed may not be the one still
    /// alive when the user next opens the app).
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PiboWidgetConstants.appGroupID) ?? .standard
    }

    private init() {
        pushEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        notifyEveryReading = UserDefaults.standard.bool(forKey: Self.everyKey)   // default off
        sleepSummaryPushEnabled = UserDefaults.standard.object(forKey: Self.sleepEnabledKey) as? Bool ?? true
    }

    /// Called once at launch. Sets up quiet provisional authorization (so a
    /// passive user is covered without a prompt) or just reflects current state
    /// when the user has turned pushes off.
    func start() async {
        AppNotificationRouter.shared.install()
        if pushEnabled {
            await requestAuthorization(provisional: true)
        } else {
            await refreshAuthState()
        }
    }

    /// Request the system notification authorization. `provisional` grants
    /// quietly with no prompt (Notification Center only) — used at launch. A
    /// full request (`provisional: false`) prompts and enables audible banners;
    /// used when the user explicitly turns the setting on. Call from foreground
    /// only — never from a background wake.
    func requestAuthorization(provisional: Bool = false) async {
        var options: UNAuthorizationOptions = [.alert, .sound]
        if provisional { options.insert(.provisional) }
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: options)
            authorized = granted
            LPLog.app.notice("notification auth granted=\(granted, privacy: .public) provisional=\(provisional, privacy: .public)")
        } catch {
            authorized = false
            LPLog.app.error("notification auth threw: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Refresh `authorized` from the current system settings (no prompt).
    func refreshAuthState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Human-readable snapshot of every gate that can stop a stress push —
    /// system auth, presentation settings, quiet hours, and the two app
    /// toggles. Used by the settings self-check.
    func notificationDiagnostics() async -> String {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        let status: String
        switch s.authorizationStatus {
        case .notDetermined: status = "未决定（授权从未成功）"
        case .denied:        status = "已拒绝（需去系统设置手动开启）"
        case .authorized:    status = "完整授权"
        case .provisional:   status = "临时授权（安静投递·无横幅/声音）"
        case .ephemeral:     status = "临时(App Clip)"
        @unknown default:    status = "未知"
        }
        let banner = s.alertSetting == .enabled ? "开" : "关"
        let sound = s.soundSetting == .enabled ? "开" : "关"
        let hour = Calendar.current.component(.hour, from: Date())
        let quiet = hour >= PiboCoreStressAdapter.alertQuietStartHour
            || hour < PiboCoreStressAdapter.alertQuietEndHour
        let lastLevel = (Self.defaults.object(forKey: Self.lastLevelKey) as? Int)
            .flatMap { StressLevel(rawValue: $0)?.displayName } ?? "无"
        return """
        系统授权: \(status)
        横幅: \(banner) · 声音: \(sound)
        当前静默时段(\(PiboCoreStressAdapter.alertQuietStartHour)–\(PiboCoreStressAdapter.alertQuietEndHour)): \(quiet ? "是（智能模式此刻不推）" : "否")
        总开关 高压力提醒: \(pushEnabled ? "开" : "关")
        每次测量都提醒: \(notifyEveryReading ? "开" : "关")
        上次已通知档位: \(lastLevel)
        """
    }

    /// Fire a bare test notification, bypassing all stress logic — proves
    /// whether the *delivery* path works, independent of the classify/throttle
    /// path. Returns false only when the system won't accept it (unauthorized).
    func sendTestNotification() async -> Bool {
        await refreshAuthState()
        guard authorized else { return false }
        let content = UNMutableNotificationContent()
        content.title = AppLocalization.text("Pibo 测试通知")
        content.body = AppLocalization.text("看到这条就说明通知系统正常。")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "pibo.test.\(UUID().uuidString)",
            content: content,
            trigger: nil)
        do { try await UNUserNotificationCenter.current().add(request); return true }
        catch {
            LPLog.app.error("test push add threw: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Diagnostic push: fire on every reading with the raw RMSSD + tier, no
    /// throttle, no quiet hours, no ratchet updates (kept independent of the
    /// smart-notify state so toggling the mode off resumes clean transitions).
    private func notifyEvery(level: StressLevel, rmssd: Double) async -> Bool {
        guard !isNotifying else { return false }
        isNotifying = true
        defer { isNotifying = false }

        await refreshAuthState()
        guard authorized else { return false }

        let content = UNMutableNotificationContent()
        content.title = AppLocalization.text("压力测量")
        content.body = AppLocalization.format("%@ · RMSSD %d ms",
                                              AppLocalization.text(level.displayName),
                                              Int(rmssd.rounded()))
        content.sound = .default
        content.categoryIdentifier = AppNotificationCategory.stress
        let request = UNNotificationRequest(
            identifier: "pibo.stress.\(UUID().uuidString)",
            content: content,
            trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            LPLog.app.notice("stress verbose push level=\(level.displayName, privacy: .public) rmssd=\(rmssd, privacy: .public)")
            return true
        } catch {
            LPLog.app.error("stress verbose push add threw: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Diagnostic push for a window that **was** measured but failed the quality
    /// gates, so it produced no RMSSD. Only fires in the every-reading mode, whose
    /// contract is "每次测量都提醒" — going silent on a rejected window would read
    /// as "没在算", which is the one conclusion that mode exists to rule out.
    @discardableResult
    func notifySkippedReading() async -> Bool {
        guard pushEnabled, notifyEveryReading else { return false }
        guard !isNotifying else { return false }
        isNotifying = true
        defer { isNotifying = false }

        await refreshAuthState()
        guard authorized else { return false }

        let content = UNMutableNotificationContent()
        content.title = AppLocalization.text("压力测量")
        content.body = AppLocalization.text("测到了，但这段心跳噪声太多，这次不作数。")
        content.sound = .default
        content.categoryIdentifier = AppNotificationCategory.stress
        let request = UNNotificationRequest(
            identifier: "pibo.stress.\(UUID().uuidString)",
            content: content,
            trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            LPLog.app.notice("stress verbose push: series rejected")
            return true
        } catch {
            LPLog.app.error("stress skipped push add threw: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Fire a stress notification if this reading warrants one, respecting all
    /// guards. Returns whether a push was actually delivered (the caller logs
    /// it). Safe to call from a background HK wake — it only *reads* system auth
    /// (never prompts).
    @discardableResult
    func maybeNotify(level: StressLevel, rmssd: Double) async -> Bool {
        guard pushEnabled else { return false }
        // Diagnostic mode: every reading pushes, no throttle. Short-circuits the
        // whole transition/quiet-hours machine below.
        if notifyEveryReading { return await notifyEvery(level: level, rmssd: rmssd) }
        guard !isNotifying else { return false }

        // `lastLevelKey` tracks the last *alerted* tier — the anchor for both
        // escalation ("higher than last alerted") and recovery ("was elevated,
        // now calm"). Only a fired push updates it.
        let prev = (Self.defaults.object(forKey: Self.lastLevelKey) as? Int)
            .flatMap { StressLevel(rawValue: $0) }
        let hour = Calendar.current.component(.hour, from: Date())
        let now = Date()
        let lastAt = Self.defaults.object(forKey: Self.lastAtKey) as? Date
        guard let kind = PiboCoreStressAdapter.alertKind(
            level: level,
            previousAlertedLevel: prev,
            localHour: Double(hour),
            secondsSinceLastAlert: lastAt.map { now.timeIntervalSince($0) }
        ) else { return false }

        isNotifying = true
        defer { isNotifying = false }

        await refreshAuthState()
        guard authorized else { return false }

        let content = UNMutableNotificationContent()
        content.title = AppLocalization.text("Pibo")
        content.body = AppLocalization.text(kind.body(for: level))
        content.sound = .default
        content.categoryIdentifier = AppNotificationCategory.stress
        let request = UNNotificationRequest(
            identifier: "pibo.stress.\(UUID().uuidString)",
            content: content,
            trigger: nil)   // immediate delivery — valid from a background wake

        do {
            try await UNUserNotificationCenter.current().add(request)
            Self.defaults.set(now, forKey: Self.lastAtKey)
            Self.defaults.set(level.rawValue, forKey: Self.lastLevelKey)
            LPLog.app.notice("stress push fired kind=\(String(describing: kind), privacy: .public) level=\(level.displayName, privacy: .public) rmssd=\(rmssd, privacy: .public)")
            return true
        } catch {
            LPLog.app.error("stress push add threw: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

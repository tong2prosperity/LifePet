import Foundation
import UserNotifications
import os

/// The moment a stress reading is worth a push. Not every reading notifies —
/// only these transitions do.
enum StressAlertKind: Sendable, Equatable {
    /// Once-per-day lower reading, and a same-day return to usual.
    case elevated
    case recovered

    /// Body copy reports only the measured HRV tier. It does not infer emotion
    /// or imply that the user's reading changes Pibo's physical condition.
    func body(for level: StressLevel) -> String {
        switch self {
        case .elevated:  return "这次 HRV 比你平时低一些，我先不下结论。"
        case .recovered: return "HRV 回到你平时的样子了。"
        }
    }
}

/// Fires the stress local notification — the "实时通知" half of the
/// StressWatch-style feature. Driven from `HealthDataService.postStress`, which
/// runs on every HealthKit wake (foreground *and* background delivery), so a
/// stress change can push even while the app is backgrounded.
///
/// Decisions 049/055: daily lower-than-usual / same-day return-to-usual
/// reminders. Fresh installs opt in explicitly; launch only reads authorization.
@MainActor
@Observable
final class StressNotifier {
    static let shared = StressNotifier()

    /// User-facing toggle (settings). Off silences pushes without revoking the
    /// system authorization. Persisted in standard defaults.
    var pushEnabled: Bool {
        didSet {
            preferences.set(pushEnabled, forKey: Self.enabledKey)
            if !pushEnabled { deliveryGeneration += 1 }
        }
    }

    /// Report the result of **every** HRV computation (not just tier
    /// transitions), carrying the reading + tier. Bypasses the throttle/quiet-hours
    /// logic — frequent by design, for a user who wants to see that the
    /// measurement is actually running. Sits *under* `pushEnabled` (that's still
    /// the master switch). Available only in DEBUG diagnostics; default off.
    var notifyEveryReading: Bool {
        get {
            #if DEBUG
            preferences.bool(forKey: Self.everyKey)
            #else
            false
            #endif
        }
        set {
            #if DEBUG
            preferences.set(newValue, forKey: Self.everyKey)
            #endif
        }
    }

    /// Whether the once-a-morning sleep summary may post a system banner
    /// (`MorningSleepCoordinator` reads this gate). It shares the app's single
    /// notification grant with stress alerts — turning it on requests full
    /// authorization, which also un-silences stress banners. Default on.
    var sleepSummaryPushEnabled: Bool {
        didSet { preferences.set(sleepSummaryPushEnabled, forKey: Self.sleepEnabledKey) }
    }

    /// System authorization state, refreshed lazily. `false` until authorized
    /// (provisional counts).
    private(set) var authorized = false
    private(set) var alertsVisible = false

    /// Raised when the user taps a stress notification, cleared by `HomeView`
    /// once it has opened the history surface on the 压力卡.
    ///
    /// A flag rather than a counter: the destination is idempotent, so two taps
    /// arriving behind one presentation should still open it exactly once. It
    /// also has to survive a **cold** launch — the tap can arrive before
    /// `HomeView` exists, so the view checks it on appear as well as on change.
    var pendingCardOpen = false
    /// Day start timestamp (seconds since 1970) of the stress notification, if any.
    var pendingStressDay: Double? = nil

    /// In-flight guard: `maybeNotify` has `await` suspension points between the
    /// throttle check and the state write, and two HK triggers (observer +
    /// `reconcile`) can call it concurrently for the same reading. This blocks
    /// the reentrant second call so they can't both pass the throttle.
    private var isNotifying = false
    private var deliveryGeneration = 0

    // Persisted keys.
    private static let enabledKey = "pibo.stress.push.enabled.v1"
    private static let everyKey = "pibo.stress.push.every.v1"
    private static let sleepEnabledKey = "pibo.sleep.push.enabled.v1"
    /// App-Group defaults so the throttle/escalation ratchet survives a
    /// background relaunch (the process that pushed may not be the one still
    /// alive when the user next opens the app).
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PiboWidgetConstants.appGroupID) ?? .standard
    }

    private let changeAlerts: StressChangeAlertStore
    private let preferences: UserDefaults
    private let notifications: any StressNotificationScheduling
    private let clock: @MainActor () -> Date

    init(notifications: (any StressNotificationScheduling)? = nil,
         preferences: UserDefaults = .standard, deliveryDefaults: UserDefaults? = nil,
         clock: @escaping @MainActor () -> Date = { .now }) {
        self.notifications = notifications ?? SystemStressNotificationCenter()
        self.preferences = preferences
        self.clock = clock
        pushEnabled = StressChangeAlertStore.initialPushEnabled(in: preferences)
        changeAlerts = StressChangeAlertStore(defaults: deliveryDefaults ?? Self.defaults, now: clock())
        sleepSummaryPushEnabled = preferences.object(forKey: Self.sleepEnabledKey) as? Bool ?? true
    }

    /// Called once at launch. Only restores the current authorization state:
    /// decision 049 moves the notification choice to the optional Home guide
    /// and explicit Settings toggles, so launch never requests permission.
    func start() async {
        AppNotificationRouter.shared.install()
        await refreshAuthState()
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
            let granted = try await notifications.stressRequestAuthorization(options: options)
            await refreshAuthState()
            LPLog.app.notice("notification auth granted=\(granted, privacy: .public) provisional=\(provisional, privacy: .public)")
        } catch {
            authorized = false
            alertsVisible = false
            LPLog.app.error("notification auth threw: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Refresh `authorized` from the current system settings (no prompt).
    func refreshAuthState() async {
        let settings = await notifications.stressSettings()
        authorized = settings.status == .authorized || settings.status == .provisional
        alertsVisible = settings.status == .authorized && settings.alertsEnabled
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
        return """
        系统授权: \(status)
        横幅: \(banner) · 声音: \(sound)
        当前静默时段(\(PiboCoreStressAdapter.alertQuietStartHour)–\(PiboCoreStressAdapter.alertQuietEndHour)): \(quiet ? "是（智能模式此刻不推）" : "否")
        HRV 变化提醒: \(pushEnabled ? "开" : "关")
        HRV 测量提醒: \(notifyEveryReading ? "开" : "关")
        \(changeAlerts.deliverySummary())
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
        do { try await notifications.stressAdd(request); return true }
        catch {
            LPLog.app.error("test push add threw: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Per-measurement readout: fires on every reading, no throttle, no quiet
    /// hours, no ratchet updates (kept independent of the smart-notify state so
    /// toggling the mode off resumes clean transitions).
    ///
    /// Pibo reports the number itself rather than the system doing it. Measuring,
    /// naming and recording is its characterised behaviour (narrative-rebuild
    /// 005), and every other notification this app sends is Pibo speaking — a
    /// system-voice readout would be the one foreign register on the surface, and
    /// would read as a debug artifact.
    ///
    /// The metric is surfaced as **HRV**, never as RMSSD: RMSSD is the algorithm
    /// we happen to compute (`HRVAnalysis`), not a word the user has to carry.
    /// It is deliberately *not* qualified as "≠ Apple 健康的 HRV" here — that
    /// caveat belongs on the 压力卡, where there is room for it; a notification
    /// body that explains its own metric has already lost the reader.
    func notifyMeasurement(level: StressLevel?, rmssd: Double) async -> Bool {
        #if DEBUG
        guard pushEnabled, notifyEveryReading else { return false }
        guard !isNotifying else { return false }
        isNotifying = true
        defer { isNotifying = false }

        let generation = deliveryGeneration
        await refreshAuthState()
        guard authorized, pushEnabled, !Task.isCancelled, generation == deliveryGeneration else { return false }

        let content = UNMutableNotificationContent()
        content.title = AppLocalization.text("Pibo")
        let result = level.map { AppLocalization.text($0.displayName) }
            ?? AppLocalization.text("仅记录")
        content.body = AppLocalization.format("stress.measurement.body",
                                              Int(rmssd.rounded()),
                                              result)
        content.sound = .default
        content.categoryIdentifier = AppNotificationCategory.stress
        content.userInfo = [
            AppNotificationCategory.stressDayUserInfoKey: Calendar.current.startOfDay(for: clock()).timeIntervalSince1970
        ]
        let request = UNNotificationRequest(
            identifier: "pibo.stress.\(UUID().uuidString)",
            content: content,
            trigger: nil)
        do {
            try await notifications.stressAdd(request)
            guard pushEnabled, notifyEveryReading, !Task.isCancelled, generation == deliveryGeneration else {
                notifications.stressWithdraw(request.identifier)
                return false
            }
            LPLog.app.notice("stress verbose push level=\(level?.displayName ?? "record-only", privacy: .public) rmssd=\(rmssd, privacy: .public)")
            return true
        } catch {
            LPLog.app.error("stress verbose push add threw: \(error.localizedDescription, privacy: .public)")
            return false
        }
        #else
        return false
        #endif
    }

    /// Fire a stress notification if this reading warrants one, respecting all
    /// guards. Returns whether a push was actually delivered (the caller logs
    /// it). Safe to call from a background HK wake — it only *reads* system auth
    /// (never prompts).
    @discardableResult
    func maybeNotify(level: StressLevel, rmssd: Double) async -> Bool {
        guard pushEnabled else { return false }
        // This branch is available only in the separately compiled debug diagnostics.
        if notifyEveryReading { return await notifyMeasurement(level: level, rmssd: rmssd) }
        guard !isNotifying else { return false }

        let now = clock()
        guard let kind = changeAlerts.kind(for: level, now: now) else { return false }

        isNotifying = true
        defer { isNotifying = false }

        let generation = deliveryGeneration
        await refreshAuthState()
        guard authorized, pushEnabled, !Task.isCancelled, generation == deliveryGeneration else { return false }

        let content = UNMutableNotificationContent()
        content.title = AppLocalization.text("Pibo")
        content.body = AppLocalization.text(kind.body(for: level))
        content.sound = .default
        content.categoryIdentifier = AppNotificationCategory.stress
        content.userInfo = [
            AppNotificationCategory.stressDayUserInfoKey: Calendar.current.startOfDay(for: now).timeIntervalSince1970
        ]
        let request = UNNotificationRequest(
            identifier: "pibo.stress.\(UUID().uuidString)",
            content: content,
            trigger: nil)   // immediate delivery — valid from a background wake

        do {
            try await notifications.stressAdd(request)
            guard pushEnabled, !Task.isCancelled, generation == deliveryGeneration else {
                notifications.stressWithdraw(request.identifier)
                return false
            }
            changeAlerts.recordDelivered(kind, at: now)
            LPLog.app.notice("stress push fired kind=\(String(describing: kind), privacy: .public) level=\(level.displayName, privacy: .public) rmssd=\(rmssd, privacy: .public)")
            return true
        } catch {
            LPLog.app.error("stress push add threw: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

import SwiftUI

/// Production settings. Debug diagnostics intentionally live one level deeper
/// and are compiled out of release builds.
struct SettingsView: View {
    /// Matches the rounded-24 card language used throughout the history surface.
    private static let sectionRadius: CGFloat = 24

    @Environment(PetStateStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(StressNotifier.self) private var messageNotifier
    @Environment(WorkoutCompletionNotifier.self) private var workoutNotifier
    @Environment(OnboardingStateStore.self) private var onboarding
    @Environment(HealthDataService.self) private var health
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PiboSeasonStore.self) private var seasons

    @AppStorage(PiboPersistenceKeys.Defaults.ambientSoundEnabled)
    private var ambientSoundEnabled = true
    @AppStorage(PiboPersistenceKeys.Defaults.soundEffectsEnabled)
    private var soundEffectsEnabled = true
    @State private var showLogoutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var showDeleteAccountFailure = false
    @State private var deletingAccount = false
    @State private var showStoryRecovery = false
    @State private var healthRequestInFlight = false
    @State private var showLogin = false
    @AppStorage(Analytics.enabledKey) private var analyticsEnabled = true

    #if DEBUG
    var onReset: () -> Void = {}
    var onSimulateMeal: (MealType) -> Void = { _ in }
    var onSimulateWorkout: () -> Void = {}
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LP.Spacing.xl) {
                if PiboReleaseScope.pixelHome { podHeader }
                accountSection
                connectionSection
                soundSection
                notificationSection
                settingsSection("隐私", icon: PixelIcons.doc) {
                    settingToggle(title: "使用情况统计", subtitle: "匿名记录功能使用，不包含健康数值、照片或回答内容", isOn: $analyticsEnabled)
                        .onChange(of: analyticsEnabled) { _, enabled in Analytics.setEnabled(enabled) }
                }
                aboutSection
                // Login is on demand (only the meal camera needs it), so most
                // people never had an account: no dimmed account actions.
                if auth.phase == .loggedIn {
                    logoutSection
                }
                #if DEBUG
                debugSection
                #endif
            }
            .padding(.horizontal, LP.Spacing.xl)
            .padding(.top, LP.Spacing.m)
            .padding(.bottom, LP.Spacing.xxl)
        }
        .background((PiboReleaseScope.pixelHome ? Color(pixelHex: 0xF1E6D2) : LP.Fill.bgSurfaceSecondary).ignoresSafeArea())
        .navigationTitle(AppLocalization.text(PiboReleaseScope.pixelHome ? "舱内控制面板" : "设置"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            AppLocalization.text("确定要退出登录吗？"),
            isPresented: $showLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.text("退出登录"), role: .destructive) {
                Task { await auth.logout() }
            }
            Button(AppLocalization.text("取消"), role: .cancel) {}
        }
        .alert(
            AppLocalization.text("确定要注销账号吗？"),
            isPresented: $showDeleteAccountConfirmation
        ) {
            Button(AppLocalization.text("取消"), role: .cancel) {}
            Button(AppLocalization.text("注销账号"), role: .destructive) {
                performDeleteAccount()
            }
        } message: {
            Text(AppLocalization.text("注销会删除服务端与本设备上的全部 Pibo 数据，包括健康记录、bo 与餐食历史，且无法恢复。"))
        }
        .alert(
            AppLocalization.text("注销失败，请检查网络后重试"),
            isPresented: $showDeleteAccountFailure
        ) {
            Button(AppLocalization.text("好"), role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showStoryRecovery) {
            HealthAuthView(mode: .storyRecovery) { showStoryRecovery = false }
        }
        .fullScreenCover(isPresented: $showLogin) {
            NavigationStack {
                LoginFlowView(
                    purpose: .account,
                    onComplete: { showLogin = false },
                    onClose: { showLogin = false }
                )
            }
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await messageNotifier.refreshAuthState()
        }
    }

    /// Decision 063: the pixel settings page opens with Pibo's pod. The antenna is bent until
    /// season one fixes it, and with the forest sound on it sends little waves (ArkTS
    /// `podHeader`).
    private var podHeader: some View {
        VStack(spacing: 8) {
            PixelPodPanelView(podFixed: seasons.podFixed, soundOn: ambientSoundEnabled)
                .background(alignment: .bottomTrailing) {
                    Rectangle().fill(PixelUIColor.shadow).offset(x: 3, y: 3)
                }
            PixelText(text: AppLocalization.format("地球第 %@ 天 · Pibo 的舱",
                                                   "\(max(1, store.dayCount))"),
                      textSize: 12, color: PixelUIColor.inkSoft)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Logged out, the row is the way in: login is on demand, never a gate.
    @ViewBuilder
    private var accountSection: some View {
        settingsSection("账号", icon: PixelIcons.pulse) {
            if auth.phase == .loggedIn {
                settingsRow(title: "手机号", detail: accountDetail, showsChevron: false)
                    .accessibilityElement(children: .combine)
            } else {
                Button {
                    LPHaptics.tap()
                    showLogin = true
                } label: {
                    settingsRow(title: "登录 Pibo", detail: "餐食识别使用账号", showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppLocalization.text("登录后可以使用餐食识别"))
            }
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        if PiboReleaseScope.temporaryCooperationOnboarding,
           onboarding.needsStoryRecovery {
            settingsSection("settings.connection.title", icon: PixelIcons.phone) {
                Button {
                    Analytics.track(.storyRecoveryOpened, screen: "settings")
                    showStoryRecovery = true
                } label: {
                    settingsRow(
                        title: "settings.connection.continue",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        } else if SettingsHealthEntryPolicy.showsConnectRow(
            temporaryCooperationEnabled: PiboReleaseScope.temporaryCooperationOnboarding,
            storyAccepted: onboarding.snapshot.connection == .accepted,
            hasObservedHealthSource: onboarding.hasObservedHealthSource,
            healthAuthState: health.authState
        ) {
            settingsSection("settings.connection.title", icon: PixelIcons.phone) {
                Button {
                    connectHealthRecords()
                } label: {
                    settingsRow(
                        title: "settings.connection.health",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(healthRequestInFlight)
            }
        }
    }

    private func connectHealthRecords() {
        guard !healthRequestInFlight else { return }
        healthRequestInFlight = true
        Task {
            await health.requestAuthorization()
            let readiness = await health.onboardingReadiness()
            if PiboReleaseScope.temporaryCooperationOnboarding {
                onboarding.markHealthRequestCompleted(readiness: readiness)
            }
            Analytics.track(
                .healthAuth,
                screen: "settings",
                ["observed_source": .bool(readiness.isReady)]
            )
            healthRequestInFlight = false
        }
    }

    private var soundSection: some View {
        settingsSection("声音", icon: PixelIcons.speaker) {
            VStack(spacing: 0) {
                settingToggle(title: "环境声音", isOn: $ambientSoundEnabled)
                    .onChange(of: ambientSoundEnabled) { _, enabled in
                        LPHaptics.tap()
                        Analytics.track(
                            .soundscapeSettingChange,
                            screen: "settings",
                            ["enabled": .bool(enabled)]
                        )
                    }
                Divider().overlay(LP.Separator.primary)
                settingToggle(
                    title: "互动音效",
                    subtitle: "拍一拍、bo 与物件的轻声反馈",
                    isOn: $soundEffectsEnabled
                )
                .onChange(of: soundEffectsEnabled) { _, enabled in
                    LPHaptics.tap()
                    PiboSoundEffectService.shared.setEnabled(enabled)
                }
            }
        }
    }

    private var reminderWanted: Bool {
        messageNotifier.pushEnabled || messageNotifier.sleepSummaryPushEnabled || workoutNotifier.pushEnabled
    }

    private var notificationSection: some View {
        settingsSection("通知", icon: PixelIcons.bell) {
            VStack(spacing: 0) {
                settingToggle(
                    title: "HRV 变化提醒",
                    subtitle: "比你平时低时提醒一次；当天回到平时再说一声",
                    isOn: messageNotificationsBinding
                )
                Divider().overlay(LP.Separator.primary)
                settingToggle(
                    title: "睡眠总结提醒",
                    subtitle: "睡醒后，把昨晚睡了多久整理成一条提醒",
                    isOn: sleepSummaryNotificationsBinding
                )
                Divider().overlay(LP.Separator.primary)
                settingToggle(
                    title: "运动完成提醒",
                    subtitle: "后台同步运动时提醒；打开 Pibo 后在森林里回应",
                    isOn: workoutNotificationsBinding
                )
                Divider().overlay(LP.Separator.primary)

                if reminderWanted && !messageNotifier.alertsVisible {
                    Divider().overlay(LP.Separator.primary)
                    Button {
                        LPHaptics.tap()
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        settingsRow(
                            title: messageNotifier.authorized ? "横幅没开，提醒可能静默送达" : "通知没开，提醒发不出去",
                            detail: "去开启",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var aboutSection: some View {
        settingsSection("关于", icon: PixelIcons.doc) {
            VStack(spacing: 0) {
                NavigationLink {
                    LegalDocumentView(document: LegalDocuments.privacyPolicy)
                } label: {
                    settingsRow(title: "隐私协议", showsChevron: true)
                }
                .buttonStyle(.plain)
                Divider().overlay(LP.Separator.primary)
                NavigationLink {
                    LegalDocumentView(document: LegalDocuments.userAgreement)
                } label: {
                    settingsRow(title: "用户协议", showsChevron: true)
                }
                .buttonStyle(.plain)
                Divider().overlay(LP.Separator.primary)
                NavigationLink {
                    AboutPiboView()
                } label: {
                    settingsRow(title: "关于我们", showsChevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var logoutSection: some View {
        VStack(spacing: LP.Spacing.m) {
            logoutButton
            deleteAccountButton
        }
    }

    private var deleteAccountButton: some View {
        Button {
            LPHaptics.tap()
            showDeleteAccountConfirmation = true
        } label: {
            Text(AppLocalization.text(deletingAccount ? "正在注销…" : "注销账号"))
                .font(PiboReleaseScope.pixelHome ? PixelFont.font(15) : .system(size: 15, weight: .medium))
                .foregroundStyle(PiboReleaseScope.pixelHome ? PixelUIColor.warn : LP.Fill.foundationError)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(deletingAccount)
        .background(
            Group {
                if PiboReleaseScope.pixelHome {
                    PixelUIColor.paper
                        .overlay(Rectangle().strokeBorder(PixelUIColor.warn, lineWidth: 2))
                        .background(alignment: .bottomTrailing) {
                            Rectangle().fill(PixelUIColor.shadow).offset(x: 3, y: 3)
                        }
                } else {
                    RoundedRectangle(cornerRadius: Self.sectionRadius, style: .continuous)
                        .fill(LP.Fill.bgContainer)
                }
            }
        )
        .accessibilityHint(AppLocalization.text("永久删除服务端与本设备上的全部 Pibo 数据"))
    }

    private func performDeleteAccount() {
        guard !deletingAccount else { return }
        deletingAccount = true
        Task {
            // Success publishes logged-out + bumps `accountDeletionRevision`;
            // `RootView` then schedules the local wipe and returns to first run.
            let erased = await auth.deleteAccount()
            deletingAccount = false
            if !erased { showDeleteAccountFailure = true }
        }
    }

    private var logoutButton: some View {
        Button {
            LPHaptics.tap()
            showLogoutConfirmation = true
        } label: {
            Text(AppLocalization.text("退出登录"))
                .font(PiboReleaseScope.pixelHome ? PixelFont.font(15) : .system(size: 15, weight: .medium))
                .foregroundStyle(PiboReleaseScope.pixelHome ? PixelUIColor.ink : LP.Content.primary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Group {
                if PiboReleaseScope.pixelHome {
                    PixelUIColor.paper
                        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                        .background(alignment: .bottomTrailing) {
                            Rectangle().fill(PixelUIColor.shadow).offset(x: 3, y: 3)
                        }
                } else {
                    RoundedRectangle(cornerRadius: Self.sectionRadius, style: .continuous)
                        .fill(LP.Fill.bgContainer)
                }
            }
        )
    }

    #if DEBUG
    private var debugSection: some View {
        settingsSection("开发", icon: PixelIcons.wrench) {
            VStack(spacing: 0) {
                Button {
                    LPHaptics.tap()
                    onSimulateWorkout()
                } label: {
                    settingsRow(
                        title: "模拟运动完成",
                        detail: "24 分钟跑步",
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pibo.debug.simulate-workout")
                .accessibilityHint("返回首页并播放完整运动完成流程")

                Divider().overlay(LP.Separator.primary)

                NavigationLink {
                    DebugSettingsView(onReset: onReset, onSimulateMeal: onSimulateMeal)
                } label: {
                    settingsRow(title: "调试设置", showsChevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }
    #endif

    private var accountDetail: String {
        switch auth.phase {
        case .loggedIn:
            // Sessions from before the masked value was recorded show 已登录
            // until the next login.
            return auth.accountPhone ?? AppLocalization.text("已登录")
        case .codeSent, .loggedOut:
            return AppLocalization.text("未登录")
        }
    }

    private var messageNotificationsBinding: Binding<Bool> {
        Binding(
            get: { messageNotifier.pushEnabled },
            set: { enabled in
                LPHaptics.tap()
                messageNotifier.pushEnabled = enabled
                if enabled {
                    Task { await messageNotifier.requestAuthorization() }
                }
            }
        )
    }

    private var sleepSummaryNotificationsBinding: Binding<Bool> {
        Binding(
            get: { messageNotifier.sleepSummaryPushEnabled },
            set: { enabled in
                LPHaptics.tap()
                messageNotifier.sleepSummaryPushEnabled = enabled
                if enabled {
                    Task { await messageNotifier.requestAuthorization() }
                }
            }
        )
    }

    private var workoutNotificationsBinding: Binding<Bool> {
        Binding(
            get: { workoutNotifier.pushEnabled },
            set: { enabled in
                LPHaptics.tap()
                workoutNotifier.pushEnabled = enabled
                if enabled {
                    Task { await workoutNotifier.requestAuthorization() }
                }
            }
        )
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        icon: [String]? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            if PiboReleaseScope.pixelHome {
                HStack(spacing: 6) {
                    if let icon {
                        PixelIcon(rows: icon, iconSize: 13)
                    }
                    Text(AppLocalization.text(title))
                        .font(PixelFont.font(13))
                        .foregroundStyle(PixelUIColor.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                content()
                    .background(PixelUIColor.paper)
                    .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                    .background(alignment: .bottomTrailing) {
                        Rectangle().fill(PixelUIColor.shadow).offset(x: 3, y: 3)
                    }
            } else {
                Text(AppLocalization.text(title))
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(LP.Content.quarternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                content()
                    .background(
                        RoundedRectangle(cornerRadius: Self.sectionRadius, style: .continuous)
                            .fill(LP.Fill.bgContainer)
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: Self.sectionRadius, style: .continuous)
                    )
            }
        }
        .task {
            await messageNotifier.refreshAuthState()
        }
    }

    @ViewBuilder
    private func settingToggle(
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        if PiboReleaseScope.pixelHome {
            HStack(spacing: LP.Spacing.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.text(title))
                        .font(PixelFont.font(14))
                        .foregroundStyle(PixelUIColor.ink)
                    if let subtitle {
                        Text(AppLocalization.text(subtitle))
                            .font(.system(size: 12))
                            .foregroundStyle(PixelUIColor.inkSoft)
                            .lineSpacing(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PixelSwitch(
                    isOn: isOn.wrappedValue,
                    label: AppLocalization.text(title),
                    switchID: title
                ) { newValue in
                    isOn.wrappedValue = newValue
                    PiboSoundEffectService.shared.play(.switchClick)
                }
            }
            .padding(.horizontal, LP.Spacing.xl)
            .padding(.vertical, subtitle == nil ? 10 : 12)
            .frame(minHeight: subtitle == nil ? 52 : 64)
        } else {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                    Text(AppLocalization.text(title))
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.primary)
                    if let subtitle {
                        Text(AppLocalization.text(subtitle))
                            .lpText(LP.Typography.b4Regular)
                            .foregroundStyle(LP.Content.secondary)
                    }
                }
            }
            .tint(LP.Fill.foundationAccent)
            .padding(.horizontal, LP.Spacing.xl)
            .frame(minHeight: subtitle == nil ? 52 : 64)
        }
    }

    private func settingsRow(
        title: String,
        detail: String? = nil,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: LP.Spacing.s) {
            Text(AppLocalization.text(title))
                .font(PiboReleaseScope.pixelHome ? PixelFont.font(14) : .system(size: 15, weight: .medium))
                .foregroundStyle(PiboReleaseScope.pixelHome ? PixelUIColor.ink : LP.Content.primary)
            Spacer(minLength: LP.Spacing.s)
            if let detail {
                Text(detail)
                    .font(PiboReleaseScope.pixelHome ? PixelFont.font(13) : .system(size: 13))
                    .foregroundStyle(PiboReleaseScope.pixelHome ? PixelUIColor.inkSoft : LP.Content.secondary)
                    .lineLimit(1)
            }
            if showsChevron {
                if PiboReleaseScope.pixelHome {
                    Text("›")
                        .font(PixelFont.font(16))
                        .foregroundStyle(PixelUIColor.inkSoft)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LP.Content.quarternary)
                }
            }
        }
        .padding(.horizontal, LP.Spacing.xl)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// Whether Settings offers 「连接健康记录」. With the temporary-cooperation story
/// paused, observed-source facts are never written, so the real HealthKit
/// request state decides (mirrors HarmonyOS `store.healthConnected`).
enum SettingsHealthEntryPolicy {
    static func showsConnectRow(
        temporaryCooperationEnabled: Bool,
        storyAccepted: Bool,
        hasObservedHealthSource: Bool,
        healthAuthState: HealthDataService.AuthState
    ) -> Bool {
        if temporaryCooperationEnabled {
            return storyAccepted && !hasObservedHealthSource
        }
        switch healthAuthState {
        case .granted, .unavailable, .requesting: return false
        case .unknown, .denied: return true
        }
    }
}

private struct AboutPiboView: View {
    @Environment(PiboSeasonStore.self) private var seasons

    var body: some View {
        VStack(spacing: LP.Spacing.l) {
            if PiboReleaseScope.pixelHome {
                VStack(spacing: 12) {
                    PixelPodPanelView(podFixed: seasons.podFixed, soundOn: false)
                        .frame(maxWidth: 240)
                    Text("Pibo")
                        .font(PixelFont.font(24))
                        .foregroundStyle(PixelUIColor.ink)
                    Text(AppLocalization.text("让健康数据成为一段可以共同经历的旅程。"))
                        .font(.system(size: 15))
                        .foregroundStyle(PixelUIColor.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(PixelUIColor.paper)
                .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
                .background(alignment: .bottomTrailing) {
                    Rectangle().fill(PixelUIColor.shadow).offset(x: 3, y: 3)
                }
            } else {
                Text("Pibo")
                    .lpText(LP.Typography.b1Medium)
                    .foregroundStyle(LP.Content.primary)
                Text(AppLocalization.text("让健康数据成为一段可以共同经历的旅程。"))
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(LP.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((PiboReleaseScope.pixelHome ? Color(pixelHex: 0xF1E6D2) : LP.Fill.bgSurfaceSecondary).ignoresSafeArea())
        .navigationTitle(AppLocalization.text("关于我们"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

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

    @AppStorage(PiboPersistenceKeys.Defaults.ambientSoundEnabled)
    private var ambientSoundEnabled = true
    @State private var showLogoutConfirmation = false
    @State private var showStoryRecovery = false
    @State private var healthRequestInFlight = false

    #if DEBUG
    var onReset: () -> Void = {}
    var onSimulateMeal: (MealType) -> Void = { _ in }
    var onSimulateWorkout: () -> Void = {}
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LP.Spacing.xl) {
                accountSection
                connectionSection
                soundSection
                notificationSection
                aboutSection
                logoutSection
                #if DEBUG
                debugSection
                #endif
            }
            .padding(.horizontal, LP.Spacing.xl)
            .padding(.top, LP.Spacing.m)
            .padding(.bottom, LP.Spacing.xxl)
        }
        .background(LP.Fill.bgSurfaceSecondary.ignoresSafeArea())
        .navigationTitle(AppLocalization.text("设置"))
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
        .fullScreenCover(isPresented: $showStoryRecovery) {
            HealthAuthView(mode: .storyRecovery) { showStoryRecovery = false }
        }
    }

    private var accountSection: some View {
        settingsSection("账号") {
            NavigationLink {
                BackendLoginView()
            } label: {
                settingsRow(title: "用户名", detail: accountDetail, showsChevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        if PiboReleaseScope.temporaryCooperationOnboarding,
           onboarding.needsStoryRecovery {
            settingsSection("settings.connection.title") {
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
        } else if !onboarding.hasObservedHealthSource,
                  (!PiboReleaseScope.temporaryCooperationOnboarding
                    || onboarding.snapshot.connection == .accepted) {
            settingsSection("settings.connection.title") {
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
        settingsSection("声音") {
            settingToggle(title: "环境声音", isOn: $ambientSoundEnabled)
                .onChange(of: ambientSoundEnabled) { _, enabled in
                    LPHaptics.tap()
                    Analytics.track(
                        .soundscapeSettingChange,
                        screen: "settings",
                        ["enabled": .bool(enabled)]
                    )
                }
        }
    }

    private var notificationSection: some View {
        settingsSection("通知") {
            VStack(spacing: 0) {
                settingToggle(
                    title: "消息通知",
                    subtitle: "第一时间收到Pibo的消息",
                    isOn: messageNotificationsBinding
                )
                Divider().overlay(LP.Separator.primary)
                settingToggle(
                    title: "运动完成提醒",
                    subtitle: "运动同步后，Pibo 会确认记录已收到",
                    isOn: workoutNotificationsBinding
                )
                Divider().overlay(LP.Separator.primary)
                // Frequent by design — a reading lands whenever the watch writes a
                // heartbeat series, so this stays off unless the user asks for it.
                // Gated on 消息通知 because `StressNotifier.pushEnabled` is the
                // master switch: with it off this toggle would silently do nothing.
                settingToggle(
                    title: "HRV 测量提醒",
                    subtitle: "每次测到 HRV 都告诉你结果，会比较频繁",
                    isOn: hrvReadingNotificationsBinding
                )
                .disabled(!messageNotifier.pushEnabled)
                .opacity(messageNotifier.pushEnabled ? 1 : 0.44)
            }
        }
    }

    private var aboutSection: some View {
        settingsSection("关于") {
            VStack(spacing: 0) {
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    settingsRow(title: "隐私协议", showsChevron: true)
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
        Button {
            LPHaptics.tap()
            showLogoutConfirmation = true
        } label: {
            Text(AppLocalization.text("退出登录"))
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.primary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(auth.phase != .loggedIn)
        .opacity(auth.phase == .loggedIn ? 1 : 0.44)
        .background(
            RoundedRectangle(cornerRadius: Self.sectionRadius, style: .continuous)
                .fill(LP.Fill.bgContainer)
        )
    }

    #if DEBUG
    private var debugSection: some View {
        settingsSection("开发") {
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
            return store.ownerName.isEmpty ? AppLocalization.text("已登录") : store.ownerName
        case .codeSent(let phone):
            return maskedPhone(phone)
        case .loggedOut:
            return AppLocalization.text("未登录")
        }
    }

    private var messageNotificationsBinding: Binding<Bool> {
        Binding(
            get: { messageNotifier.pushEnabled && messageNotifier.sleepSummaryPushEnabled },
            set: { enabled in
                LPHaptics.tap()
                messageNotifier.pushEnabled = enabled
                messageNotifier.sleepSummaryPushEnabled = enabled
                if enabled {
                    Task { await messageNotifier.requestAuthorization() }
                }
            }
        )
    }

    private var hrvReadingNotificationsBinding: Binding<Bool> {
        Binding(
            get: { messageNotifier.notifyEveryReading },
            set: { enabled in
                LPHaptics.tap()
                messageNotifier.notifyEveryReading = enabled
                // Provisional auth delivers silently to Notification Center only,
                // which for a per-reading readout reads as "没提醒". Upgrading to
                // full auth here is the same move the 消息通知 toggle makes.
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
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
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

    private func settingToggle(
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) -> some View {
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

    private func settingsRow(
        title: String,
        detail: String? = nil,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: LP.Spacing.s) {
            Text(AppLocalization.text(title))
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.primary)
            Spacer(minLength: LP.Spacing.s)
            if let detail {
                Text(detail)
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LP.Content.quarternary)
            }
        }
        .padding(.horizontal, LP.Spacing.xl)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private func maskedPhone(_ phone: String) -> String {
        guard phone.count > 7 else { return phone }
        return "\(phone.prefix(3)) **** \(phone.suffix(4))"
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            Text(AppLocalization.text("Pibo 仅在获得授权后读取健康数据，用于在设备上生成状态与历史。我们不会出售你的健康数据。通知、声音与健康权限可随时在设置中关闭。"))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(LP.Content.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(LP.Spacing.l)
        }
        .background(LP.Fill.bgSurfaceSecondary.ignoresSafeArea())
        .navigationTitle(AppLocalization.text("隐私协议"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutPiboView: View {
    var body: some View {
        VStack(spacing: LP.Spacing.m) {
            Text("Pibo")
                .lpText(LP.Typography.b1Medium)
                .foregroundStyle(LP.Content.primary)
            Text(AppLocalization.text("让健康数据成为一段可以共同经历的旅程。"))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(LP.Content.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(LP.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LP.Fill.bgSurfaceSecondary.ignoresSafeArea())
        .navigationTitle(AppLocalization.text("关于我们"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

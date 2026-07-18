import SwiftUI
#if DEBUG
import HealthKit
#endif

/// Settings behind the home gear. The forest is the single production home
/// appearance; this sheet owns membership, notifications, diagnostics and reset.
struct SettingsSheet: View {
    @Environment(PetStateStore.self) private var store
    @Environment(MembershipService.self) private var membership
    @Environment(StressNotifier.self) private var notifier
    @Environment(\.dismiss) private var dismiss
    #if DEBUG
    @Environment(MorningSleepCoordinator.self) private var morningSleep
    #endif

    /// Performs the actual reset (store wipe + onboarding flag) — owned by
    /// `HomeView` because the onboarding flag lives there.
    var onReset: () -> Void
    /// DEBUG-only: run the full 拍餐识别 path with a synthetic photo (the
    /// simulator has no camera). Owned by `HomeView` (holds recognizer + history).
    var onSimulateMeal: (MealType) -> Void = { _ in }

    @State private var showResetConfirm = false
    @State private var showMembership = false
    @State private var showStressLog = false
    @AppStorage(PiboPersistenceKeys.Defaults.ambientSoundEnabled) private var ambientSoundEnabled = true
    #if DEBUG
    @State private var showStressProbe = false
    @State private var showWaterLab = false
    @State private var stressProbeText = ""
    @State private var schedulingSleepMock = false
    @State private var showSleepMockError = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LP.Spacing.xl) {
                header
                membershipSection
                soundSection
                notifySection
                dangerSection
                #if DEBUG
                debugSection
                #endif
            }
            .padding(LP.Spacing.l)
        }
        .background(LP.Fill.bgSurface)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showMembership) {
            MembershipSheet()
                .onAppear { Analytics.track(.membershipOpen, screen: "settings") }
        }
        .sheet(isPresented: $showStressLog) {
            StressLogView()
        }
        #if DEBUG
        .alert("压力诊断", isPresented: $showStressProbe) {
            Button("好") {}
        } message: {
            Text(stressProbeText)
        }
        .alert("睡眠 Mock", isPresented: $showSleepMockError) {
            Button("好") {}
        } message: {
            Text("测试通知发送失败。请先在系统设置中允许 Pibo 通知。")
        }
        .fullScreenCover(isPresented: $showWaterLab) {
            WaterLabView()
        }
        #endif
        .confirmationDialog(
            AppLocalization.text("重置后会回到首启流程"),
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.text("重新开始"), role: .destructive) {
                onReset()
                dismiss()
            }
            Button(AppLocalization.text("取消"), role: .cancel) {}
        }
    }

    // MARK: 环境声音

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(AppLocalization.text("声音"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)

            Toggle(isOn: $ambientSoundEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.text("环境声音"))
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Content.primary)
                    Text(AppLocalization.text("森林、雨声与雷声"))
                        .lpText(LP.Typography.c2Regular)
                        .foregroundStyle(LP.Content.tertiary)
                }
            }
            .tint(LP.Fill.foundationAccent)
            .onChange(of: ambientSoundEnabled) { _, enabled in
                LPHaptics.tap()
                Analytics.track(
                    .soundscapeSettingChange,
                    screen: "settings",
                    ["enabled": .bool(enabled)]
                )
            }
            .padding(.horizontal, LP.Spacing.m)
            .padding(.vertical, LP.Spacing.s + 2)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
        }
    }

    private var header: some View {
        Text(AppLocalization.text("设置"))
            .lpText(LP.Typography.uiH4)
            .foregroundStyle(LP.Content.primary)
            .padding(.top, LP.Spacing.s)
    }

    // MARK: 会员

    private var membershipSection: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(AppLocalization.text("会员"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)

            Button {
                LPHaptics.tap()
                showMembership = true
            } label: {
                HStack(spacing: LP.Spacing.m) {
                    Text(AppLocalization.text("Pibo 会员"))
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Content.primary)
                    Spacer(minLength: 0)
                    Text(membership.isMember ? AppLocalization.text("已开通") : AppLocalization.text("未开通"))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(membership.isMember ? LP.Fill.foundationAccent : LP.Content.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LP.Content.quarternary)
                }
                .padding(.horizontal, LP.Spacing.m)
                .padding(.vertical, LP.Spacing.s + 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
        }
    }

    // MARK: 高压力提醒

    private var notifySection: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(AppLocalization.text("提醒"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)

            VStack(spacing: 0) {
                HStack(spacing: LP.Spacing.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLocalization.text("压力提醒"))
                            .lpText(LP.Typography.b2Medium)
                            .foregroundStyle(LP.Content.primary)
                        Text(AppLocalization.text("压力偏高、缓过来或状态很好时 Pibo 都会说一声"))
                            .lpText(LP.Typography.c2Regular)
                            .foregroundStyle(LP.Content.tertiary)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { notifier.pushEnabled },
                        set: { on in
                            LPHaptics.tap()
                            notifier.pushEnabled = on
                            if on { Task { await notifier.requestAuthorization() } }
                        }))
                        .labelsHidden()
                        .tint(LP.Fill.foundationAccent)
                }
                .padding(.horizontal, LP.Spacing.m)
                .padding(.vertical, LP.Spacing.s + 2)

                Divider().overlay(LP.Separator.primary)

                HStack(spacing: LP.Spacing.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLocalization.text("每次测量都提醒"))
                            .lpText(LP.Typography.b2Medium)
                            .foregroundStyle(notifier.pushEnabled ? LP.Content.primary : LP.Content.quarternary)
                        Text(AppLocalization.text("诊断用：每次 HRV 计算都推一条（含 RMSSD），会很频繁"))
                            .lpText(LP.Typography.c2Regular)
                            .foregroundStyle(LP.Content.tertiary)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { notifier.notifyEveryReading },
                        set: { on in
                            LPHaptics.tap()
                            notifier.notifyEveryReading = on
                        }))
                        .labelsHidden()
                        .tint(LP.Fill.foundationAccent)
                        .disabled(!notifier.pushEnabled)
                }
                .padding(.horizontal, LP.Spacing.m)
                .padding(.vertical, LP.Spacing.s + 2)

                Divider().overlay(LP.Separator.primary)

                Button {
                    LPHaptics.tap()
                    showStressLog = true
                } label: {
                    HStack(spacing: LP.Spacing.m) {
                        Text(AppLocalization.text("压力测量记录"))
                            .lpText(LP.Typography.b2Medium)
                            .foregroundStyle(LP.Content.primary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LP.Content.quarternary)
                    }
                    .padding(.horizontal, LP.Spacing.m)
                    .padding(.vertical, LP.Spacing.s + 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().overlay(LP.Separator.primary)

                HStack(spacing: LP.Spacing.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLocalization.text("睡眠总结提醒"))
                            .lpText(LP.Typography.b2Medium)
                            .foregroundStyle(LP.Content.primary)
                        Text(AppLocalization.text("睡醒后把昨晚睡眠整理成一条提醒。开启会请求通知权限，系统横幅对所有 Pibo 提醒生效"))
                            .lpText(LP.Typography.c2Regular)
                            .foregroundStyle(LP.Content.tertiary)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { notifier.sleepSummaryPushEnabled },
                        set: { on in
                            LPHaptics.tap()
                            notifier.sleepSummaryPushEnabled = on
                            if on { Task { await notifier.requestAuthorization() } }
                        }))
                        .labelsHidden()
                        .tint(LP.Fill.foundationAccent)
                }
                .padding(.horizontal, LP.Spacing.m)
                .padding(.vertical, LP.Spacing.s + 2)
            }
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
        }
    }

    // MARK: 重置

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(AppLocalization.text("其他"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)

            Button {
                showResetConfirm = true
            } label: {
                HStack {
                    Text(AppLocalization.text("重新开始"))
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Fill.foundationError)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, LP.Spacing.m)
                .padding(.vertical, LP.Spacing.s + 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
        }
    }

    // MARK: Debug (sprout-flow rehearsal)

    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text("DEV")
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)

            VStack(spacing: 0) {
                Button {
                    guard !schedulingSleepMock else { return }
                    LPHaptics.tap()
                    schedulingSleepMock = true
                    Task {
                        let scheduled = await morningSleep.debugScheduleFixtureNotification()
                        schedulingSleepMock = false
                        if scheduled {
                            dismiss()
                        } else {
                            showSleepMockError = true
                        }
                    }
                } label: {
                    debugRow(
                        schedulingSleepMock
                            ? "正在安排睡眠通知…"
                            : "模拟睡眠通知（点通知查看卡片）"
                    )
                }
                .buttonStyle(.plain)
                .disabled(schedulingSleepMock)
                Divider().overlay(LP.Separator.primary)
                Button {
                    store.debugInjectWorkout()
                    dismiss()
                } label: {
                    debugRow("模拟运动完成（发芽流程）")
                }
                .buttonStyle(.plain)
                Divider().overlay(LP.Separator.primary)
                Button {
                    store.debugResetSproutGrowth()
                } label: {
                    debugRow("回到未发芽（「?」卷芽）")
                }
                .buttonStyle(.plain)
                Divider().overlay(LP.Separator.primary)
                Button {
                    onSimulateMeal(.lunch)
                    dismiss()
                } label: {
                    debugRow("模拟拍一张午餐（走后台 Kimi 识别）")
                }
                .buttonStyle(.plain)
                Divider().overlay(LP.Separator.primary)
                Button {
                    store.debugInjectStress()
                    dismiss()
                } label: {
                    debugRow("模拟高压力（超载 + 本地通知）")
                }
                .buttonStyle(.plain)
                Divider().overlay(LP.Separator.primary)
                Button {
                    Task { await runStressProbe() }
                } label: {
                    debugRow("诊断压力测量（心跳系列是否可读）")
                }
                .buttonStyle(.plain)
                Divider().overlay(LP.Separator.primary)
                Button {
                    Task { await reauthorizeHealth() }
                } label: {
                    debugRow("补授权健康（含心跳系列）")
                }
                .buttonStyle(.plain)
                Divider().overlay(LP.Separator.primary)
                Button {
                    Task { await runNotifSelfCheck() }
                } label: {
                    debugRow("通知自检（发一条测试通知）")
                }
                .buttonStyle(.plain)
                Divider().overlay(LP.Separator.primary)
                Button {
                    LPHaptics.tap()
                    showWaterLab = true
                } label: {
                    debugRow("生产流水实验")
                }
                .buttonStyle(.plain)
                Divider().overlay(LP.Separator.primary)
                weatherDebugRow
                Divider().overlay(LP.Separator.primary)
                dayPhaseDebugRow
            }
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
        }
    }

    /// 天气切换 — 驱动首页场景下雨三件套(雨幕 / 地面水花 / 滴在 Pibo 上)。
    /// 接入 WeatherKit 前用它演示;选中即写 `store.weather` → 场景实时响应。
    private var weatherDebugRow: some View {
        HStack(spacing: LP.Spacing.s) {
            Text("天气")
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.secondary)
            Spacer(minLength: 0)
            ForEach([PiboWeather.clear, .rain, .thunderstorm], id: \.self) { w in
                let on = store.weather == w
                Button {
                    LPHaptics.tap()
                    store.weather = w
                } label: {
                    Text(w.displayName)
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(on ? LP.Fill.foundationOnAccent : LP.Content.secondary)
                        .padding(.horizontal, LP.Spacing.s)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(on ? LP.Fill.foundationAccent : LP.Fill.bgSurfaceSecondary)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, LP.Spacing.m)
        .padding(.vertical, LP.Spacing.s + 2)
    }

    private var dayPhaseDebugRow: some View {
        HStack(spacing: LP.Spacing.s) {
            Text("森林时间")
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.secondary)
            Spacer(minLength: 0)
            Menu {
                Button("自动（本地时间）") { store.debugForestHour = nil }
                ForEach([6.5, 12.0, 18.5, 23.0], id: \.self) { hour in
                    Button(Self.forestHourLabel(hour)) { store.debugForestHour = hour }
                }
            } label: {
                Text(store.debugForestHour.map(Self.forestHourLabel) ?? "自动")
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .padding(.horizontal, LP.Spacing.s)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(LP.Fill.bgSurfaceSecondary))
            }
        }
        .padding(.horizontal, LP.Spacing.m)
        .padding(.vertical, LP.Spacing.s + 2)
    }

    nonisolated private static func forestHourLabel(_ hour: Double) -> String {
        let totalMinutes = Int((hour * 60).rounded()) % (24 * 60)
        return String(format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60)
    }

    private func debugRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LP.Spacing.m)
        .padding(.vertical, LP.Spacing.s + 2)
        .contentShape(Rectangle())
    }

    // MARK: 压力诊断 (DEV)

    /// Probe the stress data path and surface a plain-language verdict, so a
    /// tester can tell whether the heartbeat series is readable at all.
    private func runStressProbe() async {
        let p = await HeartbeatSeriesReader.diagnose(store: HKHealthStore())
        stressProbeText = Self.formatProbe(p)
        showStressProbe = true
    }

    /// Re-request read auth for the full metric set. HealthKit only prompts for
    /// types the user has *never* answered — so this补的正是后加的「心跳系列」。
    private func reauthorizeHealth() async {
        let read = Set(HealthMetric.allCases).hkReadTypes
            .union([HKObjectType.activitySummaryType()])
        try? await HKHealthStore().requestAuthorization(toShare: [], read: read)
        stressProbeText = "已重新请求健康授权。若刚才弹出授权页，请把「心率 / 心跳系列」等全部打开，然后彻底退出并重启 App（让后台投递重新注册）。"
        showStressProbe = true
    }

    /// Dump every notification gate + fire a bare test push, so a tester can
    /// tell "通知没发" apart into: unauthorized / provisional-silent / throttled
    /// / just-normal-so-nothing-to-say.
    private func runNotifSelfCheck() async {
        let diag = await notifier.notificationDiagnostics()
        let sent = await notifier.sendTestNotification()
        let logged = StressLogStore.entries
        let notifiedCount = logged.filter(\.notified).count
        let testLine = sent
            ? "测试通知：已投递 ✅（留意横幅或下拉通知中心；若只进通知中心不横幅，多为『临时授权』）"
            : "测试通知：投递失败 ❌（未授权——先开『高压力提醒』总开关触发授权，或去系统设置手动开启）"
        let logLine = "测量记录：\(logged.count) 条 · 其中已通知 \(notifiedCount) 条"
        let hint = notifiedCount == 0
            ? "提示：0 条通知很正常——智能模式只在档位变化（注意/超载/回复/优秀）时才推，一直『正常』不推。想每次都推就开『每次测量都提醒』，或用『模拟高压力』验证一次。"
            : ""
        stressProbeText = [diag, testLine, logLine, hint]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        showStressProbe = true
    }

    private static func formatProbe(_ p: HeartbeatSeriesReader.StressProbe) -> String {
        let df = DateFormatter()
        df.dateFormat = "M-d HH:mm"
        func d(_ x: Date?) -> String { x.map { df.string(from: $0) } ?? "无" }
        let rmssd = p.rmssd.map { String(format: "%.0f ms", $0) } ?? "无"
        let stats = [
            "HealthKit 可用: \(p.healthAvailable ? "是" : "否")",
            "HRV(SDNN) 近30天: \(p.hrvCount) 条 · 最新 \(d(p.hrvLatest))",
            "心跳系列 近30天: \(p.seriesCount) 条 · 最新 \(d(p.seriesLatest))",
            "最新系列: \(p.rrCount) 拍 · RMSSD \(rmssd)",
        ].joined(separator: "\n")

        let verdict: String
        if !p.healthAvailable {
            verdict = "→ 此设备无健康数据（模拟器？）。需真机 + 已配对 Apple Watch。"
        } else if p.seriesCount > 0 && p.rmssd != nil {
            verdict = "→ 数据链路正常。记录仍空多为后台投递未触发：把 App 切到前台停留几秒会走 reconcile 补算。"
        } else if p.seriesCount == 0 && p.hrvCount > 0 {
            verdict = "→ ⚠️ 极可能「心跳系列」未授权（HRV 有数据但系列为 0）。点『补授权健康』，弹窗里全部打开，再重启 App。"
        } else if p.seriesCount == 0 {
            verdict = "→ 这 30 天手表没测到 HRV / 心跳系列。Apple 后台 HRV 很稀疏；在手表『正念』做一次 1–2 分钟呼吸可立刻生成一条，再来诊断。"
        } else {
            verdict = "→ 系列存在但拍数不足以算 RMSSD（<2）。等一次更完整的测量。"
        }
        return stats + "\n\n" + verdict
    }
    #endif
}

#Preview {
    SettingsSheet(onReset: {})
        .environment(PetStateStore(demoMode: true))
        .environment(MembershipService())
        .environment(StressNotifier.shared)
        .environment(MorningSleepCoordinator())
}

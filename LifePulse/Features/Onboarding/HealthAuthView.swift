import SwiftUI
import os

/// First-launch screen. Asks the user to share HealthKit reads, then hands
/// control back to `RootView`. The actual auth round-trip lives in
/// `HealthDataService.requestAuthorization()`; this view is just the
/// presentation + copy.
///
/// We surface three buttons:
/// - **Connect** — primary; runs the system dialog.
/// - **Demo only** — proceeds with hard-coded demo data (`DemoMode = true`).
/// - **Maybe later** — closes the gate without touching HK; the home shows
///   the demo defaults until the user opens this screen again.
struct HealthAuthView: View {
    @Environment(HealthDataService.self) private var health
    @Environment(PetStateStore.self) private var store

    /// Called by `RootView` when the gate should close — either auth was
    /// granted, the user accepted demo mode, or they tapped "later".
    let onContinue: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LP.Spacing.s5) {
                hero
                why
                Spacer(minLength: LP.Spacing.s5)
                actions
            }
            .padding(LP.Spacing.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .lpPaper(.app)
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s2) {
            Text("LIFEPET")
                .lpText(LP.Typography.monoLabel)
                .foregroundStyle(LP.Colors.coral)
            Text("先把你身体里的小生物\n接进来。")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(LP.Colors.ink)
                .lineSpacing(4)
            Text("你不是喂宠物，你的身体就是宠物的食物。")
                .lpText(LP.Typography.serifItalic)
                .foregroundStyle(LP.Colors.muted)
        }
    }

    private var why: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s3) {
            Text("LifePet 会读取（不写入）")
                .lpText(LP.Typography.monoTiny)
                .foregroundStyle(LP.Colors.muted)
            VStack(alignment: .leading, spacing: LP.Spacing.s2) {
                row(emoji: "💪", title: "步数 / 运动 / 卡路里", subtitle: "→ 体力")
                row(emoji: "⚡", title: "睡眠 · 深睡 · REM", subtitle: "→ 精力")
                row(emoji: "❤️", title: "HRV / 心率 / 冥想", subtitle: "→ 心情")
                row(emoji: "🏃", title: "已完成的运动", subtitle: "→ 自动打勾今日卡片")
            }
            .lpStampedCard(fill: LP.Colors.paperCard)
        }
    }

    private func row(emoji: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LP.Spacing.s3) {
            Text(emoji).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LP.Colors.ink)
                Text(subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(LP.Colors.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actions: some View {
        Group {
            switch health.authState {
            case .unavailable:
                VStack(spacing: LP.Spacing.s3) {
                    Text("当前设备不支持 HealthKit · 仅 Demo 模式可用")
                        .lpText(LP.Typography.caption)
                        .foregroundStyle(LP.Colors.muted)
                        .multilineTextAlignment(.center)
                    LPButton("用 Demo 数据继续", variant: .primary, action: continueWithDemo)
                }
            case .requesting:
                HStack(spacing: LP.Spacing.s3) {
                    ProgressView()
                    Text("等你授权…")
                        .lpText(LP.Typography.caption)
                        .foregroundStyle(LP.Colors.muted)
                }
            default:
                VStack(spacing: LP.Spacing.s3) {
                    LPButton("连接 HealthKit", variant: .primary, action: connect)
                    LPButton("用 Demo 数据继续", variant: .secondary, action: continueWithDemo)
                    LPButton("以后再说", variant: .ghost, action: deferAuth)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func connect() {
        LPLog.onboarding.notice("User chose: connect HealthKit")
        Task {
            await health.requestAuthorization()
            store.demoMode = false
            LPLog.onboarding.notice("Onboarding finished (auth=\(String(describing: health.authState), privacy: .public))")
            onContinue()
        }
    }

    private func continueWithDemo() {
        LPLog.onboarding.notice("User chose: demo mode")
        store.demoMode = true
        onContinue()
    }

    private func deferAuth() {
        LPLog.onboarding.notice("User chose: maybe later")
        onContinue()
    }
}

#Preview {
    HealthAuthView(onContinue: {})
        .environment(HealthDataService(metrics: []))
        .environment(PetStateStore())
}
